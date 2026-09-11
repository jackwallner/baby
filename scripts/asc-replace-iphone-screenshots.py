#!/usr/bin/env python3
"""Replace the iPhone screenshot set on the editable version, in order.

Not fastlane deliver. `deliver` walks the whole screenshot tree and has
double-uploaded a set on retry, and an interrupted run leaves a half-written
set that still reports as present. This deletes the existing images in the
iPhone set and uploads the named files in the order given, and touches no
other display type, so the Apple Watch set survives untouched.

    python3 scripts/asc-replace-iphone-screenshots.py [--dry-run]

The files come from `fastlane/screenshots/en-US`, ordered by the numeric
prefix fastlane uses. Every other storefront falls back to en-US, which is the
fleet shape.
"""
from __future__ import annotations

import hashlib
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402

BUNDLE_ID = "com.jackwallner.baby"
SHOTS = Path(__file__).resolve().parent.parent / "fastlane" / "screenshots" / "en-US"
DISPLAY_TYPE = "APP_IPHONE_67"


def upload_one(client: A.ASCClient, set_id: str, path: Path) -> str:
    data = path.read_bytes()
    created = client.post("/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileSize": len(data), "fileName": path.name},
        "relationships": {"appScreenshotSet": {
            "data": {"type": "appScreenshotSets", "id": set_id}}},
    }})["data"]

    for operation in created["attributes"]["uploadOperations"]:
        chunk = data[operation["offset"]:operation["offset"] + operation["length"]]
        request = urllib.request.Request(
            operation["url"], data=chunk, method=operation["method"])
        for header in operation["requestHeaders"]:
            request.add_header(header["name"], header["value"])
        with urllib.request.urlopen(request, timeout=300) as response:
            response.read()

    client.patch(f"/appScreenshots/{created['id']}", {"data": {
        "type": "appScreenshots",
        "id": created["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()},
    }})
    return created["id"]


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    files = sorted(SHOTS.glob("*_APP_IPHONE_*.png"),
                   key=lambda p: int(p.name.split("_", 1)[0]))
    if not files:
        raise SystemExit(f"error: no iPhone screenshots in {SHOTS}")

    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    version = A.find_editable_version(client, app["id"])
    localizations = A.list_all(
        client, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
    en_us = next(l for l in localizations if l["attributes"]["locale"] == "en-US")

    sets = A.list_all(client, f"/appStoreVersionLocalizations/{en_us['id']}/appScreenshotSets")
    target = next((s for s in sets
                   if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE), None)
    if target is None:
        target = client.post("/appScreenshotSets", {"data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": en_us["id"]}}},
        }})["data"]

    existing = A.list_all(client, f"/appScreenshotSets/{target['id']}/appScreenshots")
    print(f"version {version['attributes']['versionString']} "
          f"({version['attributes']['appStoreState']}), "
          f"{len(existing)} existing, {len(files)} to upload")
    for screenshot in existing:
        print(f"  delete {screenshot['attributes'].get('fileName')}")
        if not dry_run:
            client.delete(f"/appScreenshots/{screenshot['id']}")
    for path in files:
        print(f"  upload {path.name}")
        if not dry_run:
            upload_one(client, target["id"], path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
