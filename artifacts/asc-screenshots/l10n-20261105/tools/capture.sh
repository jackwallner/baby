#!/bin/bash
set -euo pipefail

TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
KIT_DIR=$(cd "$TOOLS_DIR/.." && pwd)
SELECTION=${1:-all}
SCENE_SELECTION=${2:-all}
GH_SIM_ACTION=${GH_SIM_ACTION:-launch}
ID_FILE=$(mktemp)
MAP_FILE=$(mktemp)
trap 'rm -f "$ID_FILE" "$MAP_FILE"' EXIT

python3 - "$KIT_DIR/app.json" "$SELECTION" "$SCENE_SELECTION" "$MAP_FILE" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
locale_selection, scene_selection = sys.argv[2:4]
targets = config["targets"]
if locale_selection == "all":
    selected = targets
else:
    names = {name for name in locale_selection.split(",") if name}
    by_name = {target["store_locale"]: target for target in targets}
    unknown = sorted(names - set(by_name))
    if unknown:
        raise SystemExit("unknown locale(s): " + ", ".join(unknown))
    selected = [target for target in targets if target["store_locale"] in names]

routes = [("log", "0"), ("history", "2"), ("first_weeks", "1"), ("summary", "3")]
if scene_selection == "all":
    scenes = routes
else:
    names = {name for name in scene_selection.split(",") if name}
    by_name = dict(routes)
    unknown = sorted(names - set(by_name))
    if unknown:
        raise SystemExit("unknown scene(s): " + ", ".join(unknown))
    scenes = [route for route in routes if route[0] in names]

locales = [{"store_locale": "en-US", "language": "en", "region": "en_US"}]
locales.extend({
    "store_locale": target["store_locale"],
    "language": target["lang"],
    "region": target["apple_locale"],
} for target in selected)

output = Path(sys.argv[4])
with output.open("w", encoding="utf-8") as stream:
    for locale in locales:
        for scene, tab in scenes:
            values = [locale["store_locale"], locale["language"], locale["region"], scene, tab]
            stream.write("|".join(values) + "\n")
PY

screen_args=()
while IFS='|' read -r locale language region scene tab; do
    args=(-SeedScreenshotData -NoCloudKit -ScreenshotTab "$tab" -AppleLanguages "($language)" -AppleLocale "$region")
    if [[ "$scene" == "summary" ]]; then
        args+=(-ScreenshotSummaryPreview)
    fi
    screen_args+=(--screen "${args[*]}")
done < "$MAP_FILE"

(cd "$KIT_DIR/../../.." && gh-sim "$GH_SIM_ACTION" \
    --scheme Baby \
    --device "iPhone 17 Pro Max" \
    --wait 14 \
    --id-file "$ID_FILE" \
    "${screen_args[@]}")

python3 - "$KIT_DIR" "$(cat "$ID_FILE")" "$MAP_FILE" <<'PY'
import shutil
import sys
from pathlib import Path

kit, run_id, mapping = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
run = Path.home() / ".gh-sim" / "results" / run_id
shots = run / "shots"
rows = [line.strip().split("|") for line in mapping.read_text(encoding="utf-8").splitlines() if line.strip()]

for number, (locale, _, _, scene, _) in enumerate(rows, start=1):
    matches = sorted(shots.glob(f"screen{number}-*.png"))
    if len(matches) != 1:
        raise SystemExit(f"expected one screen{number} capture in {shots}, found {len(matches)}")
    target = kit / "raw" / locale / "phone" / f"{scene}.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(matches[0], target)

print(f"captured {len(rows)} phone frames ({run_id})")
PY
