#!/bin/bash
# Close gaps after "go": draft version, version locs (API), full metadata via fastlane 2.234+.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="$HOME/.baseball_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi

echo "==> fastlane $(scripts/fastlane-bin.sh --version 2>&1 | awk '/fastlane [0-9]/{print $2; exit}')"

echo "==> Ensure editable ASC draft version"
eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"

echo "==> Version localizations via API (fast pre-pass)"
ASC_APP_VERSION="$ASC_APP_VERSION" python3 scripts/asc-add-missing-localizations.py \
  --draft-only \
  --from-fastlane \
  --all-supported

echo "==> PATCH keywords/descriptions via API"
./scripts/asc-upload-metadata.sh

echo "==> deliver: appInfo + all locales (fastlane 2.234 Deliverfile languages)"
export SKIP_SCREENSHOTS="${SKIP_SCREENSHOTS:-true}"
./scripts/upload-appstore-metadata.sh

echo "==> Done. Draft: $ASC_APP_VERSION (scripts/.asc-state.json)"
echo "    Submit with a build in App Store Connect to ship."
echo "    Full screenshot upload: SKIP_SCREENSHOTS=false ./scripts/upload-appstore-metadata.sh"
