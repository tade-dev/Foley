# Foley proxy

A Cloudflare Worker that holds the API keys so the app never does.

| Route | Does |
| --- | --- |
| `POST /scene` | Sends the typed scene to OpenAI, which splits it into 4–6 named sounds with tints and kinds. |
| `POST /sound` | Forwards one sound spec to ElevenLabs and streams the audio back as `audio/mpeg`. |

Both routes require an `X-Device-ID` header (the app generates a UUID once and keeps it in `UserDefaults`).

## Deploy

```bash
cd proxy
npx wrangler login
npx wrangler deploy                          # creates the Worker, prints your workers.dev URL
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
npx wrangler deploy                          # redeploy so the secrets are live
```

Then put that host in `Config/Local.xcconfig` (gitignored) in the app, **without** the scheme —
an xcconfig reads `//` as the start of a comment, so a pasted `https://` URL arrives truncated:

```
FOLEY_PROXY_URL = foley-proxy.<your-account>.workers.dev
```

Leave it empty and the app runs in demo-only mode: the bundled scenes still play.

## Limits

Per device per UTC day: 10 scenes, 40 sounds. App-wide: 50 scenes and 300 sounds per day.
Bursts: 20 requests per 60 seconds, keyed by address as well as device id.

Counts live in a Durable Object rather than KV. KV is eventually consistent, so three concurrent
requests all read the same value and all wrote value + 1 — the app generates three sounds at a
time, so the caps came out roughly three times looser than they read.
Hitting a cap returns `429 {"error":"quota"}`, which the app shows as "Daily limit reached" without retrying.
An ElevenLabs 429 comes back as `{"error":"busy"}`, which the app retries with backoff.

## Try it

```bash
U=https://foley-proxy.<your-account>.workers.dev
curl -s -X POST $U/scene -H 'content-type: application/json' -H 'X-Device-ID: smoke' \
  -d '{"prompt":"Campfire at night with crickets"}' | jq .
curl -s -X POST $U/sound -H 'content-type: application/json' -H 'X-Device-ID: smoke' \
  -d '{"text":"single wooden knock","duration_seconds":2,"loop":false,"prompt_influence":0.3}' \
  -o /tmp/knock.mp3 && file /tmp/knock.mp3
```

Each ElevenLabs generation costs about 200 credits, so the app caches every file by a hash of its spec and never
asks for the same sound twice.

## Tests

```bash
npm test      # node --test: validation repair and the daily counters
```
