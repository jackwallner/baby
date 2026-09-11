#!/bin/bash
# Re-push scripts/astro-keywords-{store}.json to Astro (no ASC pull).
#
# Usage:
#   ./scripts/sync-astro-keywords.sh
#   ./scripts/sync-astro-keywords.sh --dry-run
set -euo pipefail
cd "$(dirname "$0")/.."

STORE="${ASTRO_STORE:-us}"
MCP_URL="${ASTRO_MCP_URL:-http://127.0.0.1:8089/mcp}"
LIST="scripts/astro-keywords-${STORE}.json"
CONFIG="scripts/.astro-app.json"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

[[ -f "$LIST" ]] || { echo "error: $LIST missing — run ./scripts/astro-setup.sh first" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "error: $CONFIG missing — run ./scripts/astro-setup.sh first" >&2; exit 1; }

read -r APP_ID ASTRO_APP_NAME <<< "$(python3 -c "import json; c=json.load(open('$CONFIG')); print(c['appId'], c.get('astroAppName',''))")"

if ! curl -sf -o /dev/null -m 2 "$MCP_URL" -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"sync-script","version":"1.0"}}}'; then
  echo "error: Astro MCP not reachable at $MCP_URL" >&2
  exit 1
fi

export PYTHONPATH="$(dirname "$0"):${PYTHONPATH:-}"
python3 - "$LIST" "$APP_ID" "$ASTRO_APP_NAME" "$STORE" "$MCP_URL" "$DRY_RUN" <<'PY'
import json, sys
from astro_mcp import add_keywords

list_path, app_id, astro_app_name, store, mcp_url, dry_run = sys.argv[1:7]
keywords = json.load(open(list_path))["keywords"]
if dry_run == "true":
    label = astro_app_name or app_id
    print(f"Would add {len(keywords)} keywords to {label} ({store})")
    sys.exit(0)
result = add_keywords(
    mcp_url,
    app_id,
    store,
    keywords,
)
for i, batch in enumerate(result["batches"]):
    if isinstance(batch, dict):
        print(f"Batch {i+1}: added={batch.get('added')}, failed={batch.get('failed')}")
print("Done.")
PY
