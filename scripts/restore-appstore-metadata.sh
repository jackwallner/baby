#!/bin/bash
# Restore fastlane/metadata from a pull snapshot (metadata.bak.<timestamp>/).
#
# Usage:
#   ./scripts/restore-appstore-metadata.sh                    # latest backup
#   ./scripts/restore-appstore-metadata.sh 20260525-163657    # specific stamp
#   ./scripts/restore-appstore-metadata.sh --list             # list backups
#
# This only restores LOCAL files. To push restored metadata to ASC:
#   ASC_APP_VERSION=1.3.0 ./scripts/upload-appstore-metadata.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--list" ]]; then
  ls -dt fastlane/metadata.bak.* 2>/dev/null | sed 's|.*/metadata.bak.||' || echo "(no backups)"
  exit 0
fi

if [[ -n "${1:-}" && "${1}" != --* ]]; then
  BAK="fastlane/metadata.bak.$1"
else
  BAK="$(ls -dt fastlane/metadata.bak.* 2>/dev/null | head -1)"
fi

[[ -d "$BAK" ]] || {
  echo "error: backup not found: ${BAK:-"(none)"}" >&2
  echo "Run: ./scripts/restore-appstore-metadata.sh --list" >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -d fastlane/metadata ]]; then
  cp -R fastlane/metadata "fastlane/metadata.bak.pre-restore.$STAMP"
  echo "snapshot before restore: fastlane/metadata.bak.pre-restore.$STAMP"
fi

rm -rf fastlane/metadata
cp -R "$BAK" fastlane/metadata
echo "restored: $BAK -> fastlane/metadata/"
echo ""
echo "Diff against live ASC (optional): ASC_APP_VERSION=1.3.0 ./scripts/pull-appstore-metadata.sh"
echo "Push to App Store Connect:       ./scripts/upload-appstore-metadata.sh"
