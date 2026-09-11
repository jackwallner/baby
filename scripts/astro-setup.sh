#!/bin/bash
# Full ASC pull + Astro keyword setup for the current app repo.
#
# Usage (from any app root):
#   ./scripts/astro-setup.sh
#   ./scripts/astro-setup.sh --dry-run
#   ./scripts/astro-setup.sh --skip-pull    # use existing fastlane/metadata
#   ./scripts/astro-setup.sh --extra "phrase one" "phrase two"
#
# Requires: Astro app open, MCP enabled (:8089), ASC API key (~/.baseball_credentials)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY_RUN=false
SKIP_PULL=false
STORE="${ASTRO_STORE:-us}"
MCP_URL="${ASTRO_MCP_URL:-http://127.0.0.1:8089/mcp}"
EXTRA_PHRASES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --skip-pull) SKIP_PULL=true ;;
    --store) STORE="$2"; shift ;;
    --extra)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do EXTRA_PHRASES+=("$1"); shift; done
      continue
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

META_DIR="fastlane/metadata/en-US"
if [[ "$STORE" != "us" ]]; then
  # Map us -> en-US; other stores need locale dirs (extend as needed)
  META_DIR="fastlane/metadata/en-US"
fi

for f in "$META_DIR/name.txt" fastlane/Appfile; do
  [[ -f "$f" ]] || { echo "error: missing $f — run from an app repo with fastlane" >&2; exit 1; }
done

BUNDLE_ID="$(grep -E '^app_identifier' fastlane/Appfile | head -1 | sed 's/.*"\(.*\)".*/\1/')"
APP_NAME="$(tr -d '\n' < "$META_DIR/name.txt")"

echo "==> App: $APP_NAME"
echo "    Bundle: $BUNDLE_ID"
echo "    Store:  $STORE"

if [[ "$SKIP_PULL" == false ]]; then
  if [[ -x scripts/pull-appstore-metadata.sh ]]; then
    echo "==> Pulling ASC metadata..."
    ./scripts/pull-appstore-metadata.sh
  else
    echo "warn: scripts/pull-appstore-metadata.sh not found — using existing metadata" >&2
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PYTHONPATH="$SCRIPT_DIR:${PYTHONPATH:-}"

if ! python3 -c "from astro_mcp import ping; import sys; sys.exit(0 if ping('$MCP_URL') else 1)"; then
  echo "error: Astro MCP not reachable at $MCP_URL — open Astro and enable MCP Server" >&2
  exit 1
fi

BUILD_ARGS=(--meta-dir "$META_DIR" --store "$STORE")
[[ ${#EXTRA_PHRASES[@]} -gt 0 ]] && BUILD_ARGS+=(--extra "${EXTRA_PHRASES[@]}")
python3 "$SCRIPT_DIR/astro-build-keywords.py" "${BUILD_ARGS[@]}"

LIST="scripts/astro-keywords-${STORE}.json"
CONFIG="scripts/.astro-app.json"

if [[ "$DRY_RUN" == true ]]; then
  python3 <<PY
import json
from astro_mcp import list_apps, find_app_id

apps = list_apps("$MCP_URL")
app_id = find_app_id(apps, """$APP_NAME""")
print("Dry run — would sync to Astro app_id:", app_id or "(NOT FOUND — add app in Astro first)")
data = json.load(open("$LIST"))
print(f"Keywords ({len(data['keywords'])}):")
for k in data["keywords"][:20]:
    print(" ", k)
if len(data["keywords"]) > 20:
    print(f"  ... +{len(data['keywords'])-20} more")
PY
  exit 0
fi

python3 <<PY
import json
from datetime import datetime, timezone
from pathlib import Path

from astro_mcp import (
    add_keywords,
    call,
    ensure_tag,
    find_app_id,
    list_apps,
    tag_keyword,
)

mcp_url = "$MCP_URL"
store = "$STORE"
app_name = """$APP_NAME"""
bundle_id = "$BUNDLE_ID"
list_path = Path("$LIST")
config_path = Path("$CONFIG")

data = json.loads(list_path.read_text())
keywords = data["keywords"]
asc_tokens = [t.strip().lower() for t in data.get("ascKeywords", "").split(",") if t.strip()]

apps = list_apps(mcp_url)
app_id = find_app_id(apps, app_name)
if not app_id:
    raise SystemExit(
        f"error: '{app_name}' not found in Astro. Add it in Astro UI, then re-run."
    )

print(f"==> Astro app_id: {app_id}")
result = add_keywords(mcp_url, app_id, store, keywords)
added = sum(
    b.get("added", 0) for b in result["batches"] if isinstance(b, dict)
)
print(f"==> Keywords sync done (added ~{added} new)")

for tag, color in [("asc-field", "blue"), ("priority", "red"), ("phrase", "green")]:
    ensure_tag(mcp_url, tag, color)

priority_seed = [
    app_name.lower(),
    *asc_tokens[:5],
    *[k for k in keywords if " " in k][:8],
]
priority_seed = list(dict.fromkeys(priority_seed))[:12]

for t in asc_tokens:
    try:
        tag_keyword(mcp_url, app_id, store, t, "asc-field")
    except Exception:
        pass
for t in priority_seed:
    try:
        tag_keyword(mcp_url, app_id, store, t, "priority")
    except Exception:
        pass

config = {
    "appId": app_id,
    "appName": app_name,
    "bundleId": bundle_id,
    "store": store,
    "syncedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
config_path.write_text(json.dumps(config, indent=2) + "\n")
print(f"==> Wrote {config_path}")

kws = call(mcp_url, "get_app_keywords", {"appId": app_id, "store": store})
ranked = sorted(
    [k for k in kws if k.get("currentRanking", 1000) < 200],
    key=lambda x: x["currentRanking"],
)[:15]
print("==> Top rankings:")
for k in ranked:
    print(f"    #{k['currentRanking']:4}  {k['keyword']}")

ratings = call(mcp_url, "get_app_ratings", {"appId": app_id, "store": store})
if ratings:
    r = ratings[0]
    print(f"==> Ratings {store}: {r.get('currentRating')} ({r.get('currentCount')} reviews)")
PY

echo "==> Done. See ~/ios/aso/astro-setup-process.md to generate docs/astro-aso-setup.md and remove junk keywords."
