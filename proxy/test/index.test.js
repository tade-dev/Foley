import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

import { SpendCounter } from '../src/counter.js';

/** A SPEND binding backed by one in-process Durable Object, as the Worker sees it. */
const kv = () => {
  const map = new Map();
  const counter = new SpendCounter({
    storage: {
      async get(k) { return map.get(k); },
      async put(k, v) { map.set(k, v); },
      async setAlarm() {},
    },
  });
  return {
    store: map,
    idFromName: name => name,
    get: () => ({ fetch: (url, init) => counter.fetch(new Request('https://do/spend', init)) }),
  };
};
const post = (path, body, headers = { 'X-Device-ID': 'dev1' }) =>
  new Request(`https://proxy.test${path}`, { method: 'POST', headers, body: JSON.stringify(body) });

test('rejects non-POST and unknown paths', async () => {
  const get = new Request('https://proxy.test/scene', { method: 'GET' });
  assert.equal((await worker.fetch(get, {})).status, 404);
  assert.equal((await worker.fetch(post('/nope', {}), {})).status, 404);
});

test('requires a device id', async () => {
  const res = await worker.fetch(post('/scene', { prompt: 'rain' }, {}), { SPEND: kv() });
  assert.equal(res.status, 422);
  assert.equal((await res.json()).error, 'bad_device');
});

test('fails closed when the counter binding is missing', async () => {
  const res = await worker.fetch(post('/scene', { prompt: 'rain' }), {});
  assert.equal(res.status, 429);
  assert.equal((await res.json()).error, 'quota');
});

test('a rotated device id still hits the global scene ceiling', async () => {
  const env = { SPEND: kv(), OPENAI_API_KEY: 'x' };
  let seen = 0;
  globalThis.fetch = async () => { seen += 1; throw new Error('llm_error'); };
  for (let i = 0; i < 60; i++) {
    await worker.fetch(post('/scene', { prompt: 'rain' }, { 'X-Device-ID': `dev-${i}` }), env);
  }
  const res = await worker.fetch(post('/scene', { prompt: 'rain' }, { 'X-Device-ID': 'dev-fresh' }), env);
  assert.equal((await res.json()).error, 'quota');
  assert.ok(seen < 60, 'every rotated id reached the upstream');
});

test('an invalid sound body does not burn a counter', async () => {
  const env = { SPEND: kv(), ELEVENLABS_API_KEY: 'x' };
  const res = await worker.fetch(post('/sound', { text: '' }), env);
  assert.equal((await res.json()).error, 'bad_prompt');
  assert.equal(env.SPEND.store.size, 0, 'a rejected request spent quota');
});
