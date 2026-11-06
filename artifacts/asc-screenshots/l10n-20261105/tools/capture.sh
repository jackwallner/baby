#!/bin/bash
set -euo pipefail

TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
KIT_DIR=$(cd "$TOOLS_DIR/.." && pwd)
REPO_ROOT=$(cd "$KIT_DIR/../../.." && pwd)
SELECTION=${1:-all}
ID_FILE=$(mktemp)
LOCALE_FILE="$REPO_ROOT/BabyUITests/StoreScreenshotLocales.json"
LOCALE_BACKUP=$(mktemp)
cp "$LOCALE_FILE" "$LOCALE_BACKUP"
restore() {
    cp "$LOCALE_BACKUP" "$LOCALE_FILE"
    rm -f "$ID_FILE" "$LOCALE_BACKUP"
}
trap restore EXIT

python3 - "$KIT_DIR/app.json" "$LOCALE_FILE" "$SELECTION" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
output = Path(sys.argv[2])
selection = sys.argv[3]
targets = config["targets"]
if selection == "all":
    selected = targets
else:
    names = {name for name in selection.split(",") if name}
    by_name = {target["store_locale"]: target for target in targets}
    unknown = sorted(names - set(by_name))
    if unknown:
        raise SystemExit("unknown locale(s): " + ", ".join(unknown))
    selected = [target for target in targets if target["store_locale"] in names]

locales = [{
    "store_locale": "en-US",
    "apple_languages": "(en)",
    "apple_locale": "en_US",
}]
locales.extend({
    "store_locale": target["store_locale"],
    "apple_languages": target["apple_languages"],
    "apple_locale": target["apple_locale"],
} for target in selected)
output.write_text(json.dumps(locales, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

(cd "$REPO_ROOT" && gh-sim test \
    --scheme BabyUITests \
    --device "iPhone 17 Pro Max" \
    --only BabyUITests/LocalizedStoreScreenshotUITests/testCaptureAllLocales \
    --id-file "$ID_FILE")

python3 - "$KIT_DIR" "$(cat "$ID_FILE")" "$SELECTION" <<'PY'
import json
import shutil
import sys
from pathlib import Path

kit = Path(sys.argv[1])
run_id = sys.argv[2]
selection = sys.argv[3]
config = json.loads((kit / "app.json").read_text(encoding="utf-8"))
targets = config["targets"]
if selection == "all":
    locales = [target["store_locale"] for target in targets]
else:
    names = {name for name in selection.split(",") if name}
    locales = [target["store_locale"] for target in targets if target["store_locale"] in names]
locales = ["en-US", *locales]
routes = ["log", "history", "first_weeks", "summary"]
attachments = Path.home() / ".gh-sim" / "results" / run_id / "attachments"
manifest = json.loads((attachments / "manifest.json").read_text(encoding="utf-8"))
files = {}
for test in manifest:
    for item in test.get("attachments", []):
        name = item.get("suggestedHumanReadableName", "")
        exported = item.get("exportedFileName")
        if name and exported:
            files[name] = attachments / exported

for locale in locales:
    for scene in routes:
        expected = f"{locale}__{scene}"
        matches = [path for name, path in files.items() if name.startswith(expected + "_")]
        if len(matches) != 1:
            names = ", ".join(sorted(files))
            raise SystemExit(f"expected one attachment named {expected}, found {len(matches)}; attachments={names}")
        target = kit / "raw" / locale / "phone" / f"{scene}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(matches[0], target)

print(f"captured {len(locales) * len(routes)} phone frames for {', '.join(locales)} ({run_id})")
PY
