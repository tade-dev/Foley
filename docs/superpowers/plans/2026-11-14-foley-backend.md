# Foley Backend (Phase B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Real sound generation end to end: a Cloudflare Worker proxy (OpenAI scene parsing, ElevenLabs sound generation, rate limits), the app's live generation service behind the Phase A protocol, real demo audio, and the public README with a demo GIF.

**Architecture:** The Worker is the only holder of keys. `POST /scene` asks OpenAI for a strict-JSON scene; `POST /sound` forwards to ElevenLabs and streams audio back. KV counters enforce per-device and global daily caps. The app's `LiveGenerationService` implements `GenerationService` with concurrency handled by `SceneStore` (Phase A), a cache check before every call, and typed errors mapped from the Worker's JSON error bodies.

**Tech Stack:** Cloudflare Workers (JavaScript, `npx wrangler@4`), Workers KV, Workers rate-limiting binding, OpenAI Chat Completions with `response_format: { type: "json_schema", strict: true }`, ElevenLabs `POST /v1/sound-generation` with `eleven_text_to_sound_v2`, `URLSession` in Swift, Node 22 test runner (`node --test`) for the Worker's pure functions, ffmpeg for the GIF.

**Spec:** `docs/superpowers/specs/2026-11-14-foley-design.md` (Proxy host, Proxy URL, Rate limiting, Demo audio rows) and `docs/handoff/HANDOFF.md` (API contracts). Phase A plan: `docs/superpowers/plans/2026-11-14-foley-client.md` (interfaces for `GenerationService`, `GenerationError`, `AudioCache`, `SceneResponse`, `SoundRequest`, `ProxyConfig`, `AppEnvironment`).

## Global Constraints

- Keys only as Worker secrets: `OPENAI_API_KEY`, `ELEVENLABS_API_KEY`. Never in `wrangler.toml`, the repo, or the app.
- The Worker URL is never committed; it goes in the gitignored `Config/Local.xcconfig` (`FOLEY_PROXY_URL = https://foley-proxy.<account>.workers.dev`).
- Contracts exactly as the handoff: `/scene` request `{ "prompt" }`, response `{ title, mood, sounds: [{ name, keyword, tint, kind, prompt, duration }] }`; `/sound` request `{ text, duration_seconds, loop, prompt_influence }`, response `audio/mpeg`.
- Error bodies: `{ "error": "<code>" }` with codes `bad_prompt` (422), `llm_error` (502), `invalid_scene` (502), `elevenlabs_error` (502), `busy` (429, ElevenLabs 429), `quota` (429, daily cap), `rate_limited` (429, burst), `proxy_error` (500), `not_found` (404). The app maps `busy` → `GenerationError.busy`, `quota`/`rate_limited` → `.quota`, 5xx → `.server(code)`, URL errors → `.offline`.
- Limits: per device 10 scenes/day, 40 sounds/day; global 300 sounds/day; burst 20 requests / 60 s per device. Device ID = header `X-Device-ID` (a UUID the app creates once and stores in `UserDefaults`); missing header → 422 `bad_device`.
- Worker stays under ~150 lines excluding the prompt text and tests. Credits: demo audio ≈ 2,000 credits total, generated once.
- Commit after every task.

## Review Focus

1. **OpenAI returns valid JSON that still violates the contract** (9 sounds, a tint outside the list, a keyword with different casing than the prompt): the Worker must repair what it can (tints, counts, durations) and only fail with `invalid_scene` when there is no usable sound. Test in Task 1 (`validateScene`).
2. **ElevenLabs responds 200 with a non-audio body** (HTML error page, empty body): the app must not cache it; `LiveGenerationService` rejects anything under 1 KB or without an `audio/` content type as `.invalidResponse`. Test in Task 3.
3. **The daily cap trips halfway through a 6-pad scene**: three pads succeed, three show "Daily limit reached" with Retry, and Retry does not spin (no auto-retry for `quota`). Covered by Phase A `SceneStore` tests plus Task 3's error mapping test.
4. **Two devices share the global counter at the day boundary (UTC)**: counters are keyed by `YYYY-MM-DD` in UTC and expire after 48 h, so a stuck counter can never block forever. Test in Task 1 (`counterKey`).
5. **The proxy URL is set but unreachable** (typo, Worker deleted): Build scene must fail within ~15 s with "You're offline"-class copy and Retry, not hang. Test in Task 3 (`URLSession` timeout 15 s, `.offline` mapping).

---

### Task 1: Worker: scene route on OpenAI, validation, pure helpers with tests

**Files:**
- Create: `proxy/src/index.js`, `proxy/src/scene.js`, `proxy/src/validate.js`, `proxy/src/limits.js`, `proxy/wrangler.toml`, `proxy/package.json`, `proxy/.gitignore`, `proxy/test/validate.test.js`, `proxy/test/limits.test.js`, `proxy/README.md`

**Interfaces:**
- `validate.js`: `export const TINTS = ['amber','blue','teal','lavender','sky','pink']`; `export function validateScene(parsed, prompt) → { title, mood, sounds }` — title trimmed to 5 words (fallback: first 5 words of the prompt), mood from `TINTS` else `'blue'`, sounds: drop entries without `name`/`prompt`, max 8, `tint` from the list else `TINTS[i % 6]`, `kind` `'loop'` or `'oneShot'` (accept `one_shot`/`one-shot`), `keyword` kept only if it occurs in `prompt` case-insensitively (keep the prompt's own casing substring), `duration` clamped 0.5–22 (loop default 12, one-shot default 3). Throws `new Error('invalid_scene')` when no sound survives.
- `limits.js`: `export function counterKey(kind, deviceId, now = new Date()) → \`${kind}:${deviceId}:${YYYY-MM-DD UTC}\``; `export async function consume(kv, key, limit) → boolean` (reads the integer, returns false when `>= limit`, else writes +1 with `expirationTtl: 172800`); `export const LIMITS = { scenesPerDevice: 10, soundsPerDevice: 40, soundsGlobal: 300 }`.
- `scene.js`: `export async function sceneRoute(prompt, env)` — OpenAI `POST https://api.openai.com/v1/chat/completions` with `model: env.OPENAI_MODEL ?? 'gpt-4o-mini'`, `temperature: 0.7`, `response_format: { type: 'json_schema', json_schema: { name: 'scene', strict: true, schema } }` where `schema` is the handoff contract with `tint`/`mood` as enums and `kind` as enum `['loop','oneShot']`, `required` on every field, `additionalProperties: false`. System prompt = the handoff `SCENE_SYSTEM` text plus "Return 4 to 6 sounds unless the description clearly has fewer. Use the user's exact wording for keyword." Returns `validateScene(JSON.parse(content), prompt)`.
- `index.js`: `fetch(request, env)` routing `POST /scene` and `POST /sound`, CORS none (native app only), `X-Device-ID` check, burst limit via `env.BURST.limit({ key: deviceId })` (rate-limiting binding `[[unsafe.bindings]] name = "BURST" type = "ratelimit" namespace_id = "1001" simple = { limit = 20, period = 60 }`), KV binding `COUNTERS`, JSON error helper.
- `wrangler.toml`: `name = "foley-proxy"`, `main = "src/index.js"`, `compatibility_date = "2026-11-01"`, KV namespace placeholder id (filled in Task 2), the rate-limit binding, `[vars] OPENAI_MODEL = "gpt-4o-mini"`.
- `package.json`: `{ "private": true, "type": "module", "scripts": { "test": "node --test test/", "dev": "wrangler dev", "deploy": "wrangler deploy" }, "devDependencies": { "wrangler": "^4" } }`.

- [ ] **Step 1: Write the failing tests**

```js
// proxy/test/validate.test.js
import { test } from 'node:test'; import assert from 'node:assert/strict';
import { validateScene } from '../src/validate.js';
test('repairs tints, kinds, counts and keywords', () => {
  const prompt = 'Heavy rain, howling wind and a grumpy cat';
  const sounds = Array.from({ length: 9 }, (_, i) => ({ name: `S${i}`, keyword: i === 0 ? 'heavy RAIN' : 'zzz', tint: 'neon', kind: 'one_shot', prompt: 'p', duration: 99 }));
  const r = validateScene({ title: 'A very long title with far too many words', mood: 'neon', sounds }, prompt);
  assert.equal(r.sounds.length, 8); assert.equal(r.mood, 'blue');
  assert.equal(r.title.split(' ').length, 5);
  assert.equal(r.sounds[0].keyword, 'Heavy rain'); assert.equal(r.sounds[1].keyword, '');
  assert.equal(r.sounds[0].kind, 'oneShot'); assert.equal(r.sounds[0].duration, 22);
  assert.ok(['amber','blue','teal','lavender','sky','pink'].includes(r.sounds[0].tint));
});
test('throws invalid_scene when nothing usable', () => {
  assert.throws(() => validateScene({ title: 't', mood: 'blue', sounds: [{ name: '', prompt: '' }] }, 'x'), /invalid_scene/);
});
// proxy/test/limits.test.js
import { test } from 'node:test'; import assert from 'node:assert/strict';
import { counterKey, consume } from '../src/limits.js';
test('counter key is per UTC day', () => {
  assert.equal(counterKey('sounds', 'dev1', new Date('2026-11-15T23:59:00Z')), 'sounds:dev1:2026-11-15');
  assert.equal(counterKey('sounds', 'dev1', new Date('2026-11-16T00:01:00Z')), 'sounds:dev1:2026-11-16');
});
test('consume stops at the limit', async () => {
  const store = new Map();
  const kv = { get: async k => store.get(k) ?? null, put: async (k, v) => { store.set(k, v); } };
  for (let i = 0; i < 3; i++) assert.equal(await consume(kv, 'k', 3), true);
  assert.equal(await consume(kv, 'k', 3), false);
});
```

- [ ] **Step 2: Run `cd proxy && npm test`** — Expected: FAIL (modules missing).
- [ ] **Step 3: Implement `validate.js`, `limits.js`, `scene.js`, `index.js`, config files, and `proxy/README.md`** (secrets, KV creation, deploy, curl examples for both routes).
- [ ] **Step 4: Run `npm test`** — Expected: PASS. `npx wrangler deploy --dry-run --outdir /tmp/foley-dry` — Expected: bundles without error.
- [ ] **Step 5: Commit** `feat(proxy): worker with OpenAI scene route, validation and daily limits`

---

### Task 2: Worker: sound route, deploy, live smoke test

**Files:**
- Create: `proxy/src/sound.js`
- Modify: `proxy/src/index.js`, `proxy/wrangler.toml` (real KV id)

**Interfaces:**
- `sound.js`: `export async function soundRoute(body, env)` — validates `text` (1–500 chars), clamps `duration_seconds` to 0.5–22 or `null`, `prompt_influence` 0–1 default 0.3, `loop` boolean; forwards to `https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128` with `model_id: 'eleven_text_to_sound_v2'`; maps upstream 429 → `busy` (429), 401/5xx/other → `elevenlabs_error` (502), success → streams `res.body` with `content-type: audio/mpeg`.
- `index.js` order for `/sound`: device check → burst → per-device sounds counter → global sounds counter → route. For `/scene`: device check → burst → scenes counter → route. Counters are consumed before the upstream call (a failed upstream still counts; keeps the Worker simple).

- [ ] **Step 1: Implement `sound.js` and wire it.** `npm test` still PASS; `npx wrangler deploy --dry-run` OK.
- [ ] **Step 2: Owner-run setup** (interactive; ask the owner to run in the terminal with `!`):

```bash
cd proxy && npx wrangler login
npx wrangler kv namespace create COUNTERS      # paste the id into wrangler.toml
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
npx wrangler deploy                            # note the workers.dev URL
```

- [ ] **Step 3: Smoke test with curl** (one scene, one 2-second sound ≈ 200 credits):

```bash
U=https://foley-proxy.<account>.workers.dev
curl -s -X POST $U/scene -H 'content-type: application/json' -H 'X-Device-ID: smoke' -d '{"prompt":"Campfire at night with crickets"}' | jq .
curl -s -X POST $U/sound -H 'content-type: application/json' -H 'X-Device-ID: smoke' -d '{"text":"single wooden knock","duration_seconds":2,"loop":false,"prompt_influence":0.3}' -o /tmp/knock.mp3 && file /tmp/knock.mp3
curl -s -X POST $U/sound -d '{}' -H 'content-type: application/json' | jq .   # expect bad_device 422
```

Expected: JSON scene with 4–6 sounds and tints from the list; `/tmp/knock.mp3` is `Audio file with ID3 ... MPEG`; the last call returns `{"error":"bad_device"}`.

- [ ] **Step 4: Put the URL in `Config/Local.xcconfig`** (not committed). Commit `feat(proxy): sound route and deploy config`.

---

### Task 3: LiveGenerationService and app wiring

**Files:**
- Create: `Foley/Services/LiveGenerationService.swift`, `Foley/Services/DeviceID.swift`
- Modify: `Foley/App/AppEnvironment.swift`, `Foley/Screens/CreateView.swift` (ProxySetupCard condition), `Foley/App/ProxyConfig.swift` (if needed)
- Test: `FoleyTests/LiveGenerationServiceTests.swift`

**Interfaces:**
- `enum DeviceID { static var current: String }` — UUID string stored under `UserDefaults` key `foley.deviceID`, created on first access.
- `protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`; `struct URLSessionTransport: HTTPTransport` (timeout 15 s request, 60 s resource).
- `final class LiveGenerationService: GenerationService { init(baseURL: URL, cache: AudioCache, transport: HTTPTransport = URLSessionTransport(), deviceID: String = DeviceID.current) }` — `buildScene`: POST `/scene` `{prompt}`, decode `SceneResponse`, `.validated(for: prompt)`; `generateSound`: cache hit returns at once; else POST `/sound` with `SoundRequest(spec)`; a 2xx response with `Content-Type` not starting `audio/` or fewer than 1,024 bytes → `.invalidResponse`; otherwise `cache.store(data, key: spec.cacheKey)`. Error mapping per Global Constraints: parse `{"error": code}` from non-2xx bodies; `URLError` → `.offline`.
- `AppEnvironment`: `generation = proxy.isConfigured ? LiveGenerationService(baseURL:cache:) : MockGenerationService(cache:)`; expose `var isDemoOnly: Bool { !proxy.isConfigured }`. `CreateView` shows `ProxySetupCard` when `env.isDemoOnly` instead of calling the mock (the mock stays available for previews and tests through a `#if DEBUG` launch argument `-FoleyUseMock`).

- [ ] **Step 1: Write the failing tests** (a `FakeTransport` returning scripted responses per path)

```swift
@Suite struct LiveGenerationServiceTests {
    final class FakeTransport: HTTPTransport, @unchecked Sendable {
        var responses: [String: (Int, [String: String], Data)] = [:]; var requests: [URLRequest] = []
        func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(r)
            let (code, headers, body) = responses[r.url!.path]!
            return (body, HTTPURLResponse(url: r.url!, statusCode: code, httpVersion: nil, headerFields: headers)!)
        }
    }
    func make() throws -> (LiveGenerationService, FakeTransport, AudioCache) { /* temp cache, base https://example.test */ }
    @Test func sendsDeviceHeaderAndDecodesScene() async throws {
        let (svc, t, _) = try make()
        t.responses["/scene"] = (200, ["Content-Type": "application/json"], Data(#"{"title":"T","mood":"blue","sounds":[{"name":"Rain","keyword":"rain","tint":"teal","kind":"loop","prompt":"p","duration":10}]}"#.utf8))
        let r = try await svc.buildScene(prompt: "soft rain")
        #expect(r.sounds.first?.name == "Rain")
        #expect(t.requests[0].value(forHTTPHeaderField: "X-Device-ID")?.isEmpty == false)
    }
    @Test func mapsErrorCodes() async throws {
        let (svc, t, _) = try make(); let spec = SoundSpec(prompt: "x", duration: 2, loop: false)
        t.responses["/sound"] = (429, [:], Data(#"{"error":"busy"}"#.utf8))
        await #expect(throws: GenerationError.busy) { try await svc.generateSound(spec) }
        t.responses["/sound"] = (429, [:], Data(#"{"error":"quota"}"#.utf8))
        await #expect(throws: GenerationError.quota) { try await svc.generateSound(spec) }
        t.responses["/sound"] = (502, [:], Data(#"{"error":"elevenlabs_error"}"#.utf8))
        await #expect(throws: GenerationError.server(502)) { try await svc.generateSound(spec) }
    }
    @Test func rejectsNonAudioAndCachesAudio() async throws {
        let (svc, t, cache) = try make(); let spec = SoundSpec(prompt: "y", duration: 2, loop: false)
        t.responses["/sound"] = (200, ["Content-Type": "text/html"], Data(repeating: 0, count: 5000))
        await #expect(throws: GenerationError.invalidResponse) { try await svc.generateSound(spec) }
        #expect(!cache.contains(spec.cacheKey))
        t.responses["/sound"] = (200, ["Content-Type": "audio/mpeg"], Data(repeating: 1, count: 5000))
        _ = try await svc.generateSound(spec); #expect(cache.contains(spec.cacheKey))
        _ = try await svc.generateSound(spec); #expect(t.requests.filter { $0.url!.path == "/sound" }.count == 2)
    }
}
```

- [ ] **Step 2: Run `scripts/test.sh LiveGenerationServiceTests`** — Expected: FAIL to compile.
- [ ] **Step 3: Implement** the service, transport, device ID, and wiring.
- [ ] **Step 4: Run all tests and build; simulator check** with the real URL in `Local.xcconfig`: type "Campfire at night with crickets and an owl" → chips appear from OpenAI → Build → 4–6 real pads play. Then clear the URL, rebuild, and confirm the Typing screen shows `ProxySetupCard` and the demo scenes still play. Restore the URL.
- [ ] **Step 5: Commit** `feat: live generation service behind the proxy`

---

### Task 4: Real demo audio

**Files:**
- Create: `scripts/generate_demo_audio.sh`
- Modify: `Foley/Resources/Demo/*.m4a` (10 files replaced)

**Interfaces:**
- `scripts/generate_demo_audio.sh`: reads `ELEVENLABS_API_KEY` from the environment (exits with a message if unset), reads `Foley/Resources/Demo/demo-scenes.json` with `jq`, and for each sound calls ElevenLabs directly (`eleven_text_to_sound_v2`, `output_format=mp3_44100_128`, the sound's `prompt`, `duration`, `loop = kind == loop`, `prompt_influence 0.35`), then converts to AAC `.m4a` with `ffmpeg -i in.mp3 -c:a aac -b:a 128k`, writing to `Foley/Resources/Demo/<file>.m4a`. Skips files that already exist unless `--force`. Prints the credit estimate before starting and asks for a `y` confirmation.

- [ ] **Step 1: Write the script.** Run it with `ELEVENLABS_API_KEY=... scripts/generate_demo_audio.sh` after the owner confirms the spend (≈ 2,000 credits). Expected: 10 files, `ffprobe` durations match the JSON ±0.5 s.
- [ ] **Step 2: Listen on the simulator**: both demo scenes, loops seamless enough (if a loop clicks at the seam, apply a 50 ms crossfade in the script with ffmpeg's `afade` and re-encode, no new credits).
- [ ] **Step 3: Confirm the key never touched the repo**: `git status` shows only the `.m4a` files changed; `git grep -n "xi-api\|sk_" ` empty.
- [ ] **Step 4: Commit** `feat: real demo audio for the bundled scenes`

---

### Task 5: README, demo GIF, final acceptance

**Files:**
- Create: `README.md`, `docs/demo.gif`, `docs/architecture.md` (mermaid from the design doc)
- Modify: `.gitignore` (keep `docs/qa/` ignored)

- [ ] **Step 1: Record the demo**: `xcrun simctl io booted recordVideo --codec h264 docs/qa/demo.mp4` while walking Home → chip → Build (real generation) → play → Orbit → Rec → Mix saved. Trim to ≤ 20 s and convert: `ffmpeg -i docs/qa/demo.mp4 -vf "fps=15,scale=390:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" docs/demo.gif`. Expected: GIF under 8 MB.
- [ ] **Step 2: Write `README.md`**: one-paragraph pitch, the GIF, "Run it" (clone, open in Xcode 27, press Run: demo scenes work with no keys), "Generate your own scenes" (deploy the Worker: the five commands from Phase B Task 2, then `Config/Local.xcconfig`), architecture diagram, design notes (tokens, motion, audio-reactive UI), tests (`scripts/test.sh`), "Sounds generated with ElevenLabs", licence.
- [ ] **Step 3: Fresh-clone acceptance** in the scratchpad: clone, copy the example xcconfig, `scripts/build.sh`, `scripts/test.sh`, run on the simulator, both demo scenes play. Then set the URL and run the "typed scene → playable pads in under ~20 s" check with a stopwatch. Walk the design doc's acceptance list and tick each item in the commit message.
- [ ] **Step 4: Secret scan of history**: `git log -p | grep -iE "sk-[A-Za-z0-9]{10}|xi-api-key: [a-z0-9]|workers\.dev"` returns nothing.
- [ ] **Step 5: Commit** `docs: README with demo GIF, architecture and proxy setup`
