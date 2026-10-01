#!/bin/zsh
# Paired iPhone + Watch simulators, real WatchConnectivity: the phone's
# summary reaches the Watch, a wrist Poop is saved on the phone, and a wrist
# Pee followed by Undo leaves no Pee behind. Checks the phone's own store.
#   scripts/watch-e2e.sh <owner>   (a lease taken with `agent-sim checkout <owner> --watch`)
set -euo pipefail
cd "$(dirname "$0")/.."
OWNER=${1:?lease owner}
PHONE=$(agent-sim udid "$OWNER")
WATCH=$(agent-sim watch-udid "$OWNER")
agent-sim boot "$OWNER" --watch >/dev/null
# DERIVED_DATA=<dir> builds into its own folder, for a second pair running
# beside another build of this project.
DD_ARGS=()
PRODUCTS=~/Library/Developer/Xcode/DerivedData/Baby-*/Build/Products
if [[ -n "${DERIVED_DATA:-}" ]]; then
  DD_ARGS=(-derivedDataPath "$DERIVED_DATA")
  PRODUCTS="$DERIVED_DATA/Build/Products"
fi

xcodebuild -project Baby.xcodeproj -scheme Baby -destination "id=$PHONE" "${DD_ARGS[@]}" build -quiet
PHONE_APP=$(eval find $PRODUCTS/Debug-iphonesimulator -maxdepth 1 -name "Baby.app" | head -1)
xcrun simctl terminate "$PHONE" com.jackwallner.baby 2>/dev/null || true
xcrun simctl uninstall "$WATCH" com.jackwallner.baby.watch 2>/dev/null || true
xcrun simctl install "$PHONE" "$PHONE_APP"
xcrun simctl launch "$PHONE" com.jackwallner.baby -SeedScreenshotData >/dev/null
sleep 8

STORE="$(xcrun simctl get_app_container "$PHONE" com.jackwallner.baby group.com.jackwallner.baby)/BabyData/private.sqlite"
count() { sqlite3 "file:$STORE?mode=ro" "select count(*) from ZLOGEVENT where ZKIND='$1';"; }
WET_BEFORE=$(count wet); DIRTY_BEFORE=$(count dirty)

# A Watch app's first session after install takes minutes to activate in
# the simulator. Install and open it once, and wait for the phone to be
# reachable, so the test measures the app rather than the simulator.
xcodebuild -project Baby.xcodeproj -scheme BabyWatch -destination "id=$WATCH" "${DD_ARGS[@]}" build -quiet
WATCH_APP=$(eval find $PRODUCTS/Debug-watchsimulator -maxdepth 1 -name "BabyWatch.app" | head -1)
xcrun simctl install "$WATCH" "$WATCH_APP"
for attempt in {1..60}; do
  xcrun simctl launch --terminate-running-process "$WATCH" com.jackwallner.baby.watch >/dev/null
  sleep 5
  if xcrun simctl spawn "$WATCH" log show --last 10s --predicate 'process == "BabyWatch" AND eventMessage CONTAINS "reachable: YES"' 2>/dev/null | grep -q "reachable: YES"; then
    echo "watch session ready after $((attempt * 5))s"; break
  fi
done
xcrun simctl terminate "$WATCH" com.jackwallner.baby.watch 2>/dev/null || true

TEST_RUNNER_BABY_WATCH_E2E=1 xcodebuild test -project Baby.xcodeproj -scheme BabyWatch \
  -destination "id=$WATCH" "${DD_ARGS[@]}" -only-testing:BabyWatchUITests/WatchPhoneSyncUITests -quiet

sleep 2
WET_AFTER=$(count wet); DIRTY_AFTER=$(count dirty)
echo "phone store: dirty $DIRTY_BEFORE -> $DIRTY_AFTER, wet $WET_BEFORE -> $WET_AFTER"
[[ $DIRTY_AFTER -eq $((DIRTY_BEFORE + 1)) ]] || { echo "FAIL: the wrist Poop is not in the phone's store"; exit 1; }
[[ $WET_AFTER -eq $WET_BEFORE ]] || { echo "FAIL: the undone wrist Pee is still in the phone's store"; exit 1; }
echo "WATCH E2E PASSED"
