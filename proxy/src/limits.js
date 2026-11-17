// Per-device and app-wide daily caps, kept in Workers KV.

export const LIMITS = { scenesPerDevice: 10, soundsPerDevice: 40, soundsGlobal: 300 };
const TTL_SECONDS = 172800; // two days: a stuck counter can never outlive the day it belongs to

/** `<kind>:<device>:<YYYY-MM-DD in UTC>` — the day boundary is UTC for every device. */
export function counterKey(kind, deviceId, now = new Date()) {
  return `${kind}:${deviceId}:${now.toISOString().slice(0, 10)}`;
}

/** Increments the counter and returns false once it has reached `limit`. */
export async function consume(kv, key, limit) {
  const current = Number(await kv.get(key)) || 0;
  if (current >= limit) return false;
  await kv.put(key, String(current + 1), { expirationTtl: TTL_SECONDS });
  return true;
}
