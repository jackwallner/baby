#!/bin/bash
# Push screenshots + metadata to App Store Connect via fastlane 2.234+ (Deliverfile languages).
set -e
cd "$(dirname "$0")/.."

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="$HOME/.baseball_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  echo "error: ASC_API_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH must be set" >&2
  exit 1
fi

if [[ -z "${ASC_APP_VERSION:-}" ]]; then
  ASC_APP_VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"?([^" ]+)"?.*/\1/')
  export ASC_APP_VERSION
  echo "==> Using app version $ASC_APP_VERSION"
fi

FL="$(dirname "$0")/fastlane-bin.sh"
chmod +x "$FL"
"$FL" upload_metadata "$@"
exec "$FL" upload_screenshots "$@"
