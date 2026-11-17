#!/bin/bash
# Replaces the synthesised placeholder demo sounds with real ElevenLabs audio.
# Run once, from the repo root:
#   ELEVENLABS_API_KEY=sk_... scripts/generate_demo_audio.sh [--force]
# Costs roughly 200 credits per sound (10 sounds, about 2,000 credits).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -n "${ELEVENLABS_API_KEY:-}" ] || { echo "Set ELEVENLABS_API_KEY first (it is never stored in this repo)."; exit 1; }
command -v jq >/dev/null || { echo "jq is required: brew install jq"; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is required: brew install ffmpeg"; exit 1; }

FORCE=${1:-}
JSON=Foley/Resources/Demo/demo-scenes.json
COUNT=$(jq '[.scenes[].sounds[]] | length' "$JSON")

echo "About to generate $COUNT sounds with ElevenLabs (~$((COUNT * 200)) credits)."
read -r -p "Continue? [y/N] " reply
[ "$reply" = "y" ] || { echo "Nothing generated."; exit 0; }

jq -r '.scenes[].sounds[] | [.file, .prompt, (.duration|tostring), (if .kind == "loop" then "true" else "false" end)] | @tsv' "$JSON" |
while IFS=$'\t' read -r file prompt duration loop; do
  out="Foley/Resources/Demo/$file.m4a"
  if [ -f "$out" ] && [ "$FORCE" != "--force" ] && [ -n "${SKIP_EXISTING:-}" ]; then
    echo "skip   $file (exists)"; continue
  fi
  echo "make   $file (${duration}s, loop=$loop)"
  tmp=$(mktemp -t foley).mp3
  http=$(curl -sS -w '%{http_code}' -o "$tmp" -X POST \
    'https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128' \
    -H "xi-api-key: $ELEVENLABS_API_KEY" -H 'content-type: application/json' \
    -d "$(jq -nc --arg t "$prompt" --argjson d "$duration" --argjson l "$loop" \
        '{text:$t, duration_seconds:$d, loop:$l, prompt_influence:0.35, model_id:"eleven_text_to_sound_v2"}')")
  if [ "$http" != "200" ]; then
    echo "  failed (HTTP $http): $(head -c 200 "$tmp")"; rm -f "$tmp"; continue
  fi
  # Loops get a 50 ms crossfade at the seam so they repeat without a click.
  if [ "$loop" = "true" ]; then
    ffmpeg -y -loglevel error -i "$tmp" -af "afade=t=in:st=0:d=0.05,afade=t=out:st=$(echo "$duration - 0.05" | bc):d=0.05" \
      -ac 2 -c:a aac -b:a 128k "$out"
  else
    ffmpeg -y -loglevel error -i "$tmp" -ac 2 -c:a aac -b:a 128k "$out"
  fi
  rm -f "$tmp"
done

echo
echo "Done. Listen to both demo scenes in the simulator, then commit the .m4a files."
