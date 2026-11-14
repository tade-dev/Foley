#!/bin/bash
# Screenshot the running simulator to the given path (default docs/qa/shot.png).
cd "$(dirname "$0")/.."
SIM_NAME="${SIM:-iPhone 17}"
UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(dev['udid'] for rt,devs in d['devices'].items() for dev in devs if dev['name']=='$SIM_NAME'))")
mkdir -p docs/qa
xcrun simctl io "$UDID" screenshot --type=png "${1:-docs/qa/shot.png}" >/dev/null && echo "${1:-docs/qa/shot.png}"
