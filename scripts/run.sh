#!/bin/bash
# Build, install and launch Foley on the simulator. Extra args are passed to the app.
cd "$(dirname "$0")/.."
UDID=$(scripts/sim.sh) || exit 1
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
scripts/build.sh || exit 1
APP=$(xcodebuild -showBuildSettings -project Foley.xcodeproj -scheme Foley -destination "id=$UDID" 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $3}')/Foley.app
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" com.tade.Foley 2>/dev/null
xcrun simctl launch "$UDID" com.tade.Foley "$@" >/dev/null
echo "$UDID"
