// Repairs an LLM scene response into the contract the app decodes.

export const TINTS = ['amber', 'blue', 'teal', 'lavender', 'sky', 'pink'];
export const MAX_SOUNDS = 8;
const DURATION = { min: 0.5, max: 22, loop: 12, oneShot: 3 };

const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));
const words = (s, n) => String(s || '').trim().split(/\s+/).filter(Boolean).slice(0, n).join(' ');

/** Sentence case: the app's copy rule, applied here because models ignore it in the prompt. */
function sentenceCase(text) {
  const trimmed = String(text || '').trim();
  if (!trimmed) return trimmed;
  const lowered = trimmed.toLowerCase();
  return lowered[0].toUpperCase() + lowered.slice(1);
}

/** The prompt's own casing for `keyword`, or '' when it does not occur in the prompt. */
function matchKeyword(keyword, prompt) {
  const k = String(keyword || '').trim();
  if (!k) return '';
  const i = prompt.toLowerCase().indexOf(k.toLowerCase());
  return i === -1 ? '' : prompt.slice(i, i + k.length);
}

export function validateScene(parsed, prompt) {
  const sounds = (parsed?.sounds || [])
    .filter(s => String(s?.name || '').trim() && String(s?.prompt || '').trim())
    .slice(0, MAX_SOUNDS)
    .map((s, i) => {
      const kind = String(s.kind || '').toLowerCase().replace(/[-_]/g, '') === 'loop' ? 'loop' : 'oneShot';
      const duration = Number(s.duration);
      return {
        name: sentenceCase(words(s.name, 4)),
        keyword: matchKeyword(s.keyword, prompt),
        tint: TINTS.includes(s.tint) ? s.tint : TINTS[i % TINTS.length],
        kind,
        prompt: String(s.prompt).trim(),
        duration: Number.isFinite(duration) && duration > 0
          ? clamp(duration, DURATION.min, DURATION.max)
          : (kind === 'loop' ? DURATION.loop : DURATION.oneShot),
      };
    });

  if (sounds.length === 0) throw new Error('invalid_scene');

  return {
    title: sentenceCase(words(parsed?.title, 5) || words(prompt, 5)),
    mood: TINTS.includes(parsed?.mood) ? parsed.mood : 'blue',
    sounds,
  };
}
