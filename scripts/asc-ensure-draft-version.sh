#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="$HOME/.baseball_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi
exec python3 "$(dirname "$0")/asc-ensure-draft-version.py" "$@"
