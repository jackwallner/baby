#!/bin/bash
# Prune junk keywords on all 91 Astro stores (Step 7).
set -euo pipefail
cd "$(dirname "$0")/.."
STORES=$(python3 -c "import json; print(' '.join(s['code'] for s in json.load(open('scripts/astro-stores-2026.json'))['stores']))")
for s in $STORES; do
  echo "==> prune $s"
  python3 scripts/astro-optimize.py --store "$s" --prune || true
  sleep 1.2
done
