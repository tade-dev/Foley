import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SpendCounter } from '../src/counter.js';

/** Minimal stand-in for Durable Object storage: a map with the same async shape. */
function fakeState() {
  const map = new Map();
  return {
    storage: {
      async get(key) { return map.get(key); },
      async put(key, value) { map.set(key, value); },
      async setAlarm() {},
    },
    map,
  };
}

const spend = (counter, pairs) =>
  counter.fetch(new Request('https://do/spend', { method: 'POST', body: JSON.stringify(pairs) }));

test('counts every increment, including concurrent ones', async () => {
  const counter = new SpendCounter(fakeState(), {});
  const results = await Promise.all(
    Array.from({ length: 3 }, () => spend(counter, [{ key: 'scenes:dev:2026-11-17', limit: 10 }]))
  );
  for (const r of results) assert.equal(r.status, 200);
  const after = await spend(counter, [{ key: 'scenes:dev:2026-11-17', limit: 10 }]);
  assert.equal(await after.text(), '4', 'concurrent increments were lost');
});

test('refuses at the limit and does not consume on refusal', async () => {
  const counter = new SpendCounter(fakeState(), {});
  for (let i = 0; i < 2; i++) assert.equal((await spend(counter, [{ key: 'k', limit: 2 }])).status, 200);
  assert.equal((await spend(counter, [{ key: 'k', limit: 2 }])).status, 429);
  assert.equal((await spend(counter, [{ key: 'k', limit: 3 }])).status, 200, 'a refused call must not have consumed a unit');
});

test('all keys or none: a blocked ceiling leaves the per-device count untouched', async () => {
  const counter = new SpendCounter(fakeState(), {});
  await spend(counter, [{ key: 'global', limit: 1 }]);
  const res = await spend(counter, [{ key: 'device', limit: 40 }, { key: 'global', limit: 1 }]);
  assert.equal(res.status, 429);
  const check = await spend(counter, [{ key: 'device', limit: 40 }]);
  assert.equal(await check.text(), '1', 'the device was charged for a request the ceiling blocked');
});
