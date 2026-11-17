// Per-device and app-wide daily caps, kept in Workers KV.

// Per-device caps keep one person polite; the global ceilings are what protect the account's
// balance, because X-Device-ID is client-minted and can be rotated freely.
export const LIMITS = {
  scenesPerDevice: 10,
  soundsPerDevice: 40,
  scenesGlobal: 50,
  soundsGlobal: 300,
};
/** `<kind>:<device>:<YYYY-MM-DD in UTC>` — the day boundary is UTC for every device. */
export function counterKey(kind, deviceId, now = new Date()) {
  return `${kind}:${deviceId}:${now.toISOString().slice(0, 10)}`;
}
