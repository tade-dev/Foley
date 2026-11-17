import { test } from 'node:test';
import assert from 'node:assert/strict';
import { counterKey, consume, LIMITS } from '../src/limits.js';

test('counter key is per UTC day', () => {
  assert.equal(counterKey('sounds', 'dev1', new Date('2026-11-15T23:59:00Z')), 'sounds:dev1:2026-11-15');
  assert.equal(counterKey('sounds', 'dev1', new Date('2026-11-16T00:01:00Z')), 'sounds:dev1:2026-11-16');
});

test('consume stops at the limit and expires keys', async () => {
  const store = new Map(); const ttls = [];
  const kv = { get: async k => store.get(k) ?? null, put: async (k, v, opts) => { store.set(k, v); ttls.push(opts?.expirationTtl); } };
  for (let i = 0; i < 3; i++) assert.equal(await consume(kv, 'k', 3), true);
  assert.equal(await consume(kv, 'k', 3), false);
  assert.ok(ttls.every(t => t === 172800));
});

test('limits match the design', () => {
  assert.deepEqual(LIMITS, { scenesPerDevice: 10, soundsPerDevice: 40, soundsGlobal: 300 });
});
