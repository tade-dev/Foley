#!/bin/bash
# Run the unit tests on the iOS simulator. Pass a suite name to run only that suite.
cd "$(dirname "$0")/.."
LOG=${TEST_LOG:-$(mktemp)}
ONLY=""
[ -n "$1" ] && ONLY="-only-testing:FoleyTests/$1"
xcodebuild test -project Foley.xcodeproj -scheme Foley \
  -destination "id=$(scripts/sim.sh)" $ONLY >"$LOG" 2>&1
STATUS=$?
grep -E "error:|Test Suite|Test Case|Executed|passed|failed|◇|✘|✔" "$LOG" | grep -v "^$" | tail -40
[ $STATUS -ne 0 ] && tail -30 "$LOG"
exit $STATUS
