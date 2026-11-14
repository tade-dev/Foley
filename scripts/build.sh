#!/bin/bash
# Build Foley for the iOS simulator. SIM overrides the device name.
cd "$(dirname "$0")/.."
LOG=$(mktemp)
xcodebuild build -project Foley.xcodeproj -scheme Foley \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 17}" -quiet >"$LOG" 2>&1
STATUS=$?
if [ $STATUS -ne 0 ]; then grep -E "^/.*error:|error: (the compiler|Multiple)|\*\* BUILD" "$LOG" | grep -v "swift-frontend" | sort -u | head -40; fi
rm -f "$LOG"
exit $STATUS
