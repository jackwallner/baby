#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="$HOME/.baseball_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi
if [[ -z "${ASC_APP_VERSION:-}" ]]; then
  echo "error: set ASC_APP_VERSION (e.g. 1.3.0)" >&2
  exit 1
fi
exec python3 "$(dirname "$0")/asc-upload-metadata.py" --create-missing "$@"
