#!/bin/bash
# Screenshot the running simulator to the given path (default docs/qa/shot.png).
cd "$(dirname "$0")/.."
UDID=$(scripts/sim.sh) || exit 1
mkdir -p docs/qa
xcrun simctl io "$UDID" screenshot --type=png "${1:-docs/qa/shot.png}" >/dev/null && echo "${1:-docs/qa/shot.png}"
