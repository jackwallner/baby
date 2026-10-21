#!/bin/sh
# Two simulators logging one baby, joined by SimPartnerRelay in place of
# iCloud (DEBUG builds only; no Apple ID needed). Jack's phone starts with the
# day-three log, Elsa's empty, and Elsa's fills from the relay.
#
#   scripts/two-phone-sim.sh <jack-udid> <elsa-udid> [delay-seconds]
#
# Lease both with agent-sim first (e.g. `agent-sim checkout baby` and
# `agent-sim checkout baby-watch`), and check them in after. Each phone writes
# <folder>/<name>.log: what it sent, what it received and how late, and every
# redraw with what Now then showed. Drive the phones with taps and compare.
set -eu
jack=$1
elsa=$2
delay=${3:-2}
root=$(cd "$(dirname "$0")/.." && pwd)
relay=${RELAY_DIR:-$root/build/two-phone-relay}
app=$root/build/twophone/Build/Products/Debug-iphonesimulator/Baby.app

cd "$root"
xcodegen generate >/dev/null
xcodebuild build -project Baby.xcodeproj -scheme Baby -destination "id=$jack" \
  -derivedDataPath build/twophone -quiet
rm -rf "$relay"
mkdir -p "$relay"
for device in "$jack" "$elsa"; do
  xcrun simctl uninstall "$device" com.jackwallner.baby || true
  xcrun simctl install "$device" "$app"
done
xcrun simctl launch "$jack" com.jackwallner.baby -SeedScreenshotData -NoCloudKit -SimRelay "$relay" jack -SimRelayDelay "$delay"
xcrun simctl launch "$elsa" com.jackwallner.baby -NoCloudKit -SimRelay "$relay" elsa -SimRelayDelay "$delay"
echo "relay logs: $relay/jack.log $relay/elsa.log"
