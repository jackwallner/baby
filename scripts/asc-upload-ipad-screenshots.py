#!/usr/bin/env python3
"""Replace the 13-inch iPad screenshot set on the editable version, per locale.

    python3 scripts/asc-upload-ipad-screenshots.py [--dry-run] [locale ...]

Reads `fastlane/screenshots/<locale>/NN_APP_IPAD_PRO_3GEN_129_<scene>.png`
(2064x2752, built by `artifacts/asc-screenshots/ipad-20261112/compose.py`),
deletes the images in each locale's iPad set and uploads the files in order.
Touches no other display type. It never submits the version for review.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import asc_lib as A  # noqa: E402

spec = importlib.util.spec_from_file_location("iphone_upload", HERE / "asc-replace-iphone-screenshots.py")
iphone_upload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(iphone_upload)

BUNDLE_ID = "com.jackwallner.baby"
DISPLAY_TYPE = "APP_IPAD_PRO_3GEN_129"
SHOTS = HERE.parent / "fastlane" / "screenshots"


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry_run = "--dry-run" in sys.argv
    locales = args or sorted(p.name for p in SHOTS.iterdir()
                             if p.is_dir() and any(p.glob(f"*_{DISPLAY_TYPE}_*.png")))
    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    version = A.find_editable_version(client, app["id"])
    if version is None:
        raise SystemExit("error: no editable version; run scripts/asc-ensure-draft-version.py")
    print(f"version {version['attributes']['versionString']} ({version['attributes']['appStoreState']})")
    localizations = {
        l["attributes"]["locale"]: l for l in A.list_all(
            client, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")}
    for locale in locales:
        files = sorted(SHOTS.joinpath(locale).glob(f"*_{DISPLAY_TYPE}_*.png"),
                       key=lambda p: int(p.name.split("_", 1)[0]))
        if not files or locale not in localizations:
            raise SystemExit(f"error: {locale}: {len(files)} files, localization "
                             f"{'present' if locale in localizations else 'missing'}")
        loc = localizations[locale]
        sets = A.list_all(client, f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")
        target = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE), None)
        if target is None and not dry_run:
            target = client.post("/appScreenshotSets", {"data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {"appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}},
            }})["data"]
        existing = A.list_all(client, f"/appScreenshotSets/{target['id']}/appScreenshots") if target else []
        print(f"{locale}: {len(existing)} existing, {len(files)} to upload")
        for shot in existing:
            if not dry_run:
                client.delete(f"/appScreenshots/{shot['id']}")
        for path in files:
            print(f"  upload {path.name}")
            if not dry_run:
                iphone_upload.upload_one(client, target["id"], path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
