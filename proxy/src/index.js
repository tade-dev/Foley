// Foley proxy — the only holder of the API keys.
//   POST /scene  → OpenAI splits a prompt into named sounds
//   POST /sound  → ElevenLabs sound generation, streamed back as audio/mpeg
// Secrets: wrangler secret put OPENAI_API_KEY / ELEVENLABS_API_KEY
import { sceneRoute } from './scene.js';
import { soundRoute, parseSoundRequest } from './sound.js';
import { counterKey, LIMITS } from './limits.js';
export { SpendCounter } from './counter.js';

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
        // Keyed by address as well as device id: the id is client-minted and rotatable.
        const address = request.headers.get('CF-Connecting-IP') ?? 'unknown';
        const { success } = await env.BURST.limit({ key: `${address}:${deviceId}` });
        if (!success) throw new Error('rate_limited');
      }

      const body = await request.json().catch(() => null);

      if (pathname === '/scene') {
        const prompt = String(body?.prompt || '').trim();
        if (!prompt || prompt.length > 500) throw new Error('bad_prompt');
        await spend(env, [
          [counterKey('scenes', deviceId), LIMITS.scenesPerDevice],
          [counterKey('scenes', 'global'), LIMITS.scenesGlobal],
        ]);
        return Response.json(await sceneRoute(prompt, env));
      }

      const soundRequest = parseSoundRequest(body);
      await spend(env, [
        [counterKey('sounds', deviceId), LIMITS.soundsPerDevice],
        [counterKey('sounds', 'global'), LIMITS.soundsGlobal],
      ]);
      return await soundRoute(soundRequest, env);
    } catch (e) {
      const code = STATUS[e.message] ? e.message : 'proxy_error';
      return json(code, STATUS[code] ?? 500);
    }
  },
};

/**
 * Counters are spent before the upstream call: a failed upstream still counts, which keeps this
 * simple and errs toward protecting the account. All keys or none, through a Durable Object so
 * concurrent requests cannot lose increments. Fails closed — a missing binding stops traffic
 * rather than silently removing every spending limit.
 */
async function spend(env, pairs) {
  if (!env.SPEND) throw new Error('quota');
  const day = new Date().toISOString().slice(0, 10);
  const stub = env.SPEND.get(env.SPEND.idFromName(day));
  const res = await stub.fetch('https://counter/spend', {
    method: 'POST',
    body: JSON.stringify(pairs.map(([key, limit]) => ({ key, limit }))),
  });
  if (res.status === 429) throw new Error('quota');
  if (!res.ok) throw new Error('proxy_error');
}
