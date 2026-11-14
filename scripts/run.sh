#!/bin/bash
# Build, install and launch Foley on the simulator. Extra args are passed to the app.
cd "$(dirname "$0")/.."
SIM_NAME="${SIM:-iPhone 17}"
UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(dev['udid'] for rt,devs in d['devices'].items() for dev in devs if dev['name']=='$SIM_NAME'))")
scripts/build.sh || exit 1
APP=$(xcodebuild -showBuildSettings -project Foley.xcodeproj -scheme Foley -destination "platform=iOS Simulator,name=$SIM_NAME" 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $3}')/Foley.app
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" com.tade.Foley 2>/dev/null
xcrun simctl launch "$UDID" com.tade.Foley "$@" >/dev/null
echo "$UDID"
