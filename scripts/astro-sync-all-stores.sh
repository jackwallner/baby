#!/bin/bash
# Sync Astro keywords for all fastlane locales → App Store countries.
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONPATH="$(dirname "$0"):${PYTHONPATH:-}"
exec python3 "$(dirname "$0")/astro-sync-all-stores.py" "$@"
