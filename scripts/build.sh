#!/bin/bash
# Build Foley for the iOS simulator. SIM overrides the device name.
cd "$(dirname "$0")/.."
LOG=$(mktemp)
xcodebuild build -project Foley.xcodeproj -scheme Foley \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 17}" -quiet >"$LOG" 2>&1
STATUS=$?
if [ $STATUS -ne 0 ]; then grep -E "error:|warning: unre|\*\* BUILD" "$LOG" | head -60; tail -20 "$LOG"; fi
rm -f "$LOG"
exit $STATUS
