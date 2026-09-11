#!/usr/bin/env bash
# Bump, archive, and upload Baby Tracker to TestFlight.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CURRENT_BUILD=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?.*/\1/')
NEXT_BUILD=$((CURRENT_BUILD + 1))
echo "==> Bump build $CURRENT_BUILD -> $NEXT_BUILD"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION:[[:space:]]*\")$CURRENT_BUILD/\1$NEXT_BUILD/" project.yml

echo "==> Generate project"
xcodegen generate

echo "==> Resolve packages"
xcodebuild -resolvePackageDependencies -project Baby.xcodeproj -scheme Baby

ARCHIVE="$ROOT/build/Baby.xcarchive"
rm -rf "$ARCHIVE"

echo "==> Archive Release"
xcodebuild -project Baby.xcodeproj \
  -scheme Baby \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

echo "==> Upload build $NEXT_BUILD"
"$ROOT/scripts/upload-testflight.sh" "$ARCHIVE"

git add project.yml
git commit -m "chore: bump build $CURRENT_BUILD to $NEXT_BUILD for TestFlight"
echo "==> Build $NEXT_BUILD uploaded"
