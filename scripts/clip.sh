#!/bin/bash
# Turn a simulator recording into a 9:16 MP4 ready to post.
#   scripts/clip.sh <in.mp4> <out.mp4> <start-seconds> <duration-seconds>
set -euo pipefail
IN=$1; OUT=$2; SS=$3; T=$4
ffmpeg -y -loglevel error -ss "$SS" -t "$T" -i "$IN" \
  -vf "scale=-2:1920,pad=1080:1920:(ow-iw)/2:0:color=0x0A0A0C,fps=30,format=yuv420p" \
  -c:v libx264 -preset slow -crf 20 -movflags +faststart -an "$OUT"
printf "%s  %ss  %s\n" "$(basename "$OUT")" "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" | cut -d. -f1)" "$(du -h "$OUT" | cut -f1)"
