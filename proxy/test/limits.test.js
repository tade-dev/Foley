import { test } from 'node:test';
import assert from 'node:assert/strict';
import { counterKey, LIMITS } from '../src/limits.js';

test('counter key is per UTC day', () => {
  assert.equal(counterKey('sounds', 'dev1', new Date('2026-11-15T23:59:00Z')), 'sounds:dev1:2026-11-15');
  assert.equal(counterKey('sounds', 'dev1', new Date('2026-11-16T00:01:00Z')), 'sounds:dev1:2026-11-16');
});

test('limits match the design', () => {
  assert.deepEqual(LIMITS, { scenesPerDevice: 10, soundsPerDevice: 40, scenesGlobal: 50, soundsGlobal: 300 });
});

test('a global scene ceiling exists so one rotated device id cannot drain the account', () => {
  assert.equal(typeof LIMITS.scenesGlobal, 'number');
  assert.ok(LIMITS.scenesGlobal > 0);
});
