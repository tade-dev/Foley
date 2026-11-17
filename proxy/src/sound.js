const MODEL_ID = 'eleven_text_to_sound_v2';
const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));

/** Validated before any quota is spent, so a malformed request never costs the caller a unit. */
export function parseSoundRequest(body) {
  const text = String(body?.text || '').trim();
  if (!text || text.length > 500) throw new Error('bad_prompt');
  const duration = Number(body?.duration_seconds);
  const influence = Number(body?.prompt_influence);
  return {
    text,
    duration_seconds: Number.isFinite(duration) ? clamp(duration, 0.5, 22) : null,
    loop: !!body?.loop,
    prompt_influence: Number.isFinite(influence) ? clamp(influence, 0, 1) : 0.3,
  };
}

export async function soundRoute(request, env) {
  const res = await fetch('https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128', {
    method: 'POST',
    headers: { 'xi-api-key': env.ELEVENLABS_API_KEY, 'content-type': 'application/json' },
    body: JSON.stringify({ ...request, model_id: MODEL_ID }),
  });

  if (res.status === 429) throw new Error('busy');
  if (!res.ok) throw new Error('elevenlabs_error');
  return new Response(res.body, { headers: { 'content-type': 'audio/mpeg' } });
}
