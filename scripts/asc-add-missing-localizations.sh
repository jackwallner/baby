#!/bin/bash
# Create missing ASC localizations via App Store Connect API, then optional pull.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="$HOME/.baseball_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi

export PYTHONPATH="$(dirname "$0"):${PYTHONPATH:-}"
python3 "$(dirname "$0")/asc-add-missing-localizations.py" "$@"
