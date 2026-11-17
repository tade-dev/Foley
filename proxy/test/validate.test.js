import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateScene } from '../src/validate.js';

test('repairs tints, kinds, counts and keywords', () => {
  const prompt = 'Heavy rain, howling wind and a grumpy cat';
  const sounds = Array.from({ length: 9 }, (_, i) => ({
    name: `S${i}`, keyword: i === 0 ? 'heavy RAIN' : 'zzz', tint: 'neon', kind: 'one_shot', prompt: 'p', duration: 99,
  }));
  const r = validateScene({ title: 'A very long title with far too many words', mood: 'neon', sounds }, prompt);
  assert.equal(r.sounds.length, 8);
  assert.equal(r.mood, 'blue');
  assert.equal(r.title.split(' ').length, 5);
  assert.equal(r.sounds[0].keyword, 'Heavy rain');
  assert.equal(r.sounds[1].keyword, '');
  assert.equal(r.sounds[0].kind, 'oneShot');
  assert.equal(r.sounds[0].duration, 22);
  assert.ok(['amber', 'blue', 'teal', 'lavender', 'sky', 'pink'].includes(r.sounds[0].tint));
});

test('defaults durations by kind and keeps valid input intact', () => {
  const r = validateScene({ title: 'Café', mood: 'teal', sounds: [
    { name: 'Rain', keyword: 'rain', tint: 'teal', kind: 'loop', prompt: 'p' },
    { name: 'Cup', keyword: 'cup', tint: 'pink', kind: 'oneShot', prompt: 'p' },
  ] }, 'rain and a cup');
  assert.equal(r.sounds[0].duration, 12);
  assert.equal(r.sounds[1].duration, 3);
  assert.equal(r.sounds[0].tint, 'teal');
  assert.equal(r.title, 'Café');
});

test('throws invalid_scene when nothing usable', () => {
  assert.throws(() => validateScene({ title: 't', mood: 'blue', sounds: [{ name: '', prompt: '' }] }, 'x'), /invalid_scene/);
});
