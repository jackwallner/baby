#!/usr/bin/env python3
"""Remove checksum-identical App Store screenshot retry duplicates."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib

BUNDLE_ID = "com.jackwallner.baby"
VERSION = "1.0"
LOCALE = "en-US"


def main() -> None:
    client = asc_lib.ASCClient.from_credentials()
    app = asc_lib.find_app(client, BUNDLE_ID)
    versions = asc_lib.list_all(client, f"/apps/{app['id']}/appStoreVersions")
    version = next(item for item in versions if item["attributes"]["versionString"] == VERSION)
    localizations = asc_lib.list_all(
        client,
        f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
    )
    localization = next(item for item in localizations if item["attributes"]["locale"] == LOCALE)
    screenshot_sets = asc_lib.list_all(
        client,
        f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets",
    )

    deleted = 0
    for screenshot_set in screenshot_sets:
        display_type = screenshot_set["attributes"]["screenshotDisplayType"]
        screenshots = asc_lib.list_all(
            client,
            f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots",
        )
        seen: set[str] = set()
        for screenshot in screenshots:
            attributes = screenshot["attributes"]
            checksum = attributes.get("sourceFileChecksum") or screenshot["id"]
            if checksum not in seen:
                seen.add(checksum)
                continue
            client.delete(f"/appScreenshots/{screenshot['id']}")
            deleted += 1
            print(f"deleted duplicate {display_type}: {attributes.get('fileName')}")
        print(f"{display_type}: {len(seen)} unique screenshots")

    print(f"removed {deleted} duplicate screenshots")


if __name__ == "__main__":
    main()
