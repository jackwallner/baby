#!/usr/bin/env python3
"""Check an archive against the caller's repo before any TestFlight upload."""
from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path


def setting(key: str, text: str) -> str | None:
    match = re.search(rf"^\s*{key}:\s*[\"']?([\w.\-]+)[\"']?\s*(?:#.*)?$", text, re.M)
    return match.group(1) if match else None


def app_bundle_id(text: str) -> str | None:
    """The iOS application target's bundle ID. A framework or extension
    target listed first (Sports' Shared framework) is not the archive's app."""
    targets = re.search(r"^targets:\s*\n(.*?)(?=^\S|\Z)", text, re.M | re.S)
    if targets:
        for block in re.split(r"^  (?=[\w\-]+:\s*$)", targets.group(1), flags=re.M):
            if re.search(r"^\s+type:\s*application\s*$", block, re.M) and \
                    re.search(r"^\s+platform:\s*iOS\s*$", block, re.M):
                found = setting("PRODUCT_BUNDLE_IDENTIFIER", block)
                if found:
                    return found
    return setting("PRODUCT_BUNDLE_IDENTIFIER", text)


def validate(spec: Path, archive: Path) -> None:
    text = spec.read_text()
    expected = {
        "PRODUCT_BUNDLE_IDENTIFIER": app_bundle_id(text),
        "MARKETING_VERSION": setting("MARKETING_VERSION", text),
        "CURRENT_PROJECT_VERSION": setting("CURRENT_PROJECT_VERSION", text),
    }
    for key, value in expected.items():
        if not value:
            raise SystemExit(f"cannot establish {key} from {spec}; refusing upload")
    with (archive / "Info.plist").open("rb") as stream:
        properties = plistlib.load(stream)["ApplicationProperties"]
    app_path = (archive / "Products" / properties["ApplicationPath"]).resolve()
    if not app_path.is_relative_to(archive.resolve()):
        raise SystemExit("archive app path escapes the archive; refusing upload")
    with (app_path / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    for key, field in (("PRODUCT_BUNDLE_IDENTIFIER", "CFBundleIdentifier"),
                       ("MARKETING_VERSION", "CFBundleShortVersionString"),
                       ("CURRENT_PROJECT_VERSION", "CFBundleVersion")):
        actual = str(info.get(field, ""))
        if actual != expected[key]:
            raise SystemExit(f"archive {field}={actual!r}, repo expects {expected[key]!r}; refusing upload")
    print(f"==> Archive identity verified: {info['CFBundleIdentifier']} {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: testflight_archive.py PROJECT_YML ARCHIVE")
    validate(Path(sys.argv[1]), Path(sys.argv[2]))
