import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

const kv = () => {
  const store = new Map();
  return { store, get: async k => store.get(k) ?? null, put: async (k, v) => { store.set(k, v); } };
};
const post = (path, body, headers = { 'X-Device-ID': 'dev1' }) =>
  new Request(`https://proxy.test${path}`, { method: 'POST', headers, body: JSON.stringify(body) });

test('rejects non-POST and unknown paths', async () => {
  const get = new Request('https://proxy.test/scene', { method: 'GET' });
  assert.equal((await worker.fetch(get, {})).status, 404);
  assert.equal((await worker.fetch(post('/nope', {}), {})).status, 404);
});

test('requires a device id', async () => {
  const res = await worker.fetch(post('/scene', { prompt: 'rain' }, {}), { COUNTERS: kv() });
  assert.equal(res.status, 422);
  assert.equal((await res.json()).error, 'bad_device');
});

test('fails closed when the counter namespace is missing', async () => {
  const res = await worker.fetch(post('/scene', { prompt: 'rain' }), {});
  assert.equal(res.status, 429);
  assert.equal((await res.json()).error, 'quota');
});

test('a rotated device id still hits the global scene ceiling', async () => {
  const env = { COUNTERS: kv(), OPENAI_API_KEY: 'x' };
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
  const env = { COUNTERS: kv(), ELEVENLABS_API_KEY: 'x' };
  const res = await worker.fetch(post('/sound', { text: '' }), env);
  assert.equal((await res.json()).error, 'bad_prompt');
  assert.equal(env.COUNTERS.store.size, 0, 'a rejected request spent quota');
});
