#!/bin/bash
# Raw 13 inch iPad captures for the store frames, one GitHub simulator job.
#   ./capture.sh [locale,locale]   (default: all six live screenshot locales)
#   CAPTURE_ONLY="it/log pt-BR/summary" ./capture.sh it,pt-BR   (retake single frames)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
LOCALES=${1:-en-US,de-DE,es-ES,es-MX,it,pt-BR}
ID_FILE=$(mktemp)
MAP_FILE=$(mktemp)
trap 'rm -f "$ID_FILE" "$MAP_FILE"' EXIT

# scene|DuoStop
SCENES=("log|log" "history|calendar" "first_weeks|weeks" "summary|reports")

screen_args=()
IFS=',' read -ra codes <<< "$LOCALES"
for code in "${codes[@]}"; do
    case "$code" in
        en-US) lang=en; region=en_US ;;
        de-DE) lang=de; region=de_DE ;;
        es-ES) lang=es; region=es_ES ;;
        es-MX) lang=es-MX; region=es_MX ;;
        it) lang=it; region=it_IT ;;
        pt-BR) lang=pt-BR; region=pt_BR ;;
        *) echo "unknown locale $code" >&2; exit 1 ;;
    esac
    for entry in "${SCENES[@]}"; do
        scene=${entry%%|*}; stop=${entry##*|}
        # CAPTURE_ONLY="pt-BR/summary it/log" retakes just those frames.
        if [ -n "${CAPTURE_ONLY:-}" ] && [[ " $CAPTURE_ONLY " != *" $code/$scene "* ]]; then continue; fi
        echo "$code|$scene" >> "$MAP_FILE"
        screen_args+=(--screen "-SeedScreenshotData -NoCloudKit -DemoPro -DuoStop $stop -AppleLanguages ($lang) -AppleLocale $region")
    done
done

# An evening zone for a run around 16:00 UTC, so the seeded Today is full.
(cd "$REPO" && gh-sim ${GH_SIM_ACTION:-launch} --scheme Baby --device "iPad Pro 13-inch (M5)" \
    --wait ${CAPTURE_WAIT:-25} --env TZ=${CAPTURE_TZ:-Asia/Dubai} --id-file "$ID_FILE" "${screen_args[@]}")

python3 - "$HERE" "$(cat "$ID_FILE")" "$MAP_FILE" <<'PY'
import shutil
import sys
from pathlib import Path

here, run_id, mapping = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
shots = Path.home() / ".gh-sim" / "results" / run_id / "shots"
rows = [line.strip().split("|") for line in mapping.read_text().splitlines() if line.strip()]
for number, (locale, scene) in enumerate(rows, start=1):
    matches = sorted(shots.glob(f"screen{number}-*.png"))
    if len(matches) != 1:
        raise SystemExit(f"expected one screen{number} capture in {shots}, found {len(matches)}")
    target = here / "raw" / locale / f"{scene}.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(matches[0], target)
print(f"captured {len(rows)} iPad frames ({run_id})")
PY
