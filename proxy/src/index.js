// Foley proxy — the only holder of the API keys.
//   POST /scene  → OpenAI splits a prompt into named sounds
//   POST /sound  → ElevenLabs sound generation, streamed back as audio/mpeg
// Secrets: wrangler secret put OPENAI_API_KEY / ELEVENLABS_API_KEY
import { sceneRoute } from './scene.js';
import { soundRoute } from './sound.js';
import { counterKey, consume, LIMITS } from './limits.js';

const STATUS = {
  bad_device: 422, bad_prompt: 422,
  rate_limited: 429, quota: 429, busy: 429,
  llm_error: 502, invalid_scene: 502, elevenlabs_error: 502,
};

const json = (error, status) => new Response(JSON.stringify({ error }), {
  status, headers: { 'content-type': 'application/json' },
});

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (request.method !== 'POST' || !['/scene', '/sound'].includes(pathname)) {
      return json('not_found', 404);
    }

    const deviceId = request.headers.get('X-Device-ID');
    if (!deviceId || deviceId.length > 64) return json('bad_device', 422);

    try {
      if (env.BURST) {
        const { success } = await env.BURST.limit({ key: deviceId });
        if (!success) throw new Error('rate_limited');
      }

      const body = await request.json().catch(() => null);

      if (pathname === '/scene') {
        const prompt = String(body?.prompt || '').trim();
        if (!prompt || prompt.length > 500) throw new Error('bad_prompt');
        await spend(env, [[counterKey('scenes', deviceId), LIMITS.scenesPerDevice]]);
        return Response.json(await sceneRoute(prompt, env));
      }

      await spend(env, [
        [counterKey('sounds', deviceId), LIMITS.soundsPerDevice],
        [counterKey('sounds', 'global'), LIMITS.soundsGlobal],
      ]);
      return await soundRoute(body, env);
    } catch (e) {
      const code = STATUS[e.message] ? e.message : 'proxy_error';
      return json(code, STATUS[code] ?? 500);
    }
  },
};

/** Counters are spent before the upstream call: a failed upstream still counts, and that keeps this simple. */
async function spend(env, pairs) {
  if (!env.COUNTERS) return;
  for (const [key, limit] of pairs) {
    if (!(await consume(env.COUNTERS, key, limit))) throw new Error('quota');
  }
}
