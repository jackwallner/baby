#!/bin/bash
# Pull current metadata from App Store Connect into ./fastlane/metadata/.
# Run this before editing locally so subsequent uploads do not clobber ASC web edits.
# Snapshots prior state into ./fastlane/metadata.bak.<timestamp>/ for diff/restore.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="$HOME/.baseball_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  echo "error: ASC_API_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH must be set" >&2
  echo "       see ~/.baseball_credentials" >&2
  exit 1
fi

if [[ ! -d fastlane ]]; then
  echo "error: fastlane/ not configured in $(pwd)" >&2
  exit 1
fi

if [[ -d fastlane/metadata ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BAK="fastlane/metadata.bak.$STAMP"
  cp -R fastlane/metadata "$BAK"
  echo "snapshot: $BAK"
fi

TMPKEY="$(mktemp -t asc_api_key.XXXXXX.json)"
trap 'rm -f "$TMPKEY"' EXIT
P8_CONTENTS="$(<"$ASC_KEY_PATH")"
python3 - "$ASC_API_KEY_ID" "$ASC_ISSUER_ID" "$P8_CONTENTS" "$TMPKEY" <<'PY'
import json
import sys

key_id, issuer_id, p8, output = sys.argv[1:5]
with open(output, "w", encoding="utf-8") as handle:
    json.dump(
        {"key_id": key_id, "issuer_id": issuer_id, "key": p8, "in_house": False},
        handle,
    )
PY

DELIVER_EXTRA=()
if [[ -n "${ASC_APP_VERSION:-}" ]]; then
  DELIVER_EXTRA+=(--app_version "$ASC_APP_VERSION")
fi

FL="$(dirname "$0")/fastlane-bin.sh"
chmod +x "$FL"
exec "$FL" deliver download_metadata \
  --api_key_path "$TMPKEY" \
  --metadata_path ./fastlane/metadata \
  --force true \
  --skip_screenshots true \
  ${DELIVER_EXTRA[@]+"${DELIVER_EXTRA[@]}"} \
  "$@"
