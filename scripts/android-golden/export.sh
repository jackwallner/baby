#!/bin/sh
# Compiles the iOS model, summary, report, guidance, stain and reminder
# sources with a small exporter and writes the answers they compute to the
# Android JVM test resources. Rerun after changing any of those Swift files.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
out="$root/android/app/src/test/resources/golden.json"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$(dirname "$out")"
swiftc -swift-version 5 -o "$work/golden" \
  "$root/Shared/Models/BabyModel.swift" \
  "$root/Shared/Models/TrackedKinds.swift" \
  "$root/Shared/Models/DiaperWords.swift" \
  "$root/Shared/Services/NowSummary.swift" \
  "$root/Shared/Services/SummaryReport.swift" \
  "$root/Shared/Services/Reminders.swift" \
  "$root/Shared/Utilities/DateHelpers.swift" \
  "$root/Shared/Utilities/Guidance.swift" \
  "$root/Shared/Utilities/StainGuide.swift" \
  "$root/scripts/android-golden/AppGroupStub.swift" \
  "$root/scripts/android-golden/main.swift"
TZ=America/Los_Angeles LANG=en_US.UTF-8 "$work/golden" "$out"
