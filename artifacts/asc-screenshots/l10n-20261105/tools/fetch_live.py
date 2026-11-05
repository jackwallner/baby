#!/usr/bin/env python3
"""Download the live en-US frames named in en-live.json into en-live/<set>/.

Uses the repo's own copy when its md5 matches; the CDN needs no key. Run from anywhere.
"""
from __future__ import annotations

import hashlib
import json
import urllib.request
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
REPO = BASE.parents[2]


def main() -> None:
    local = {hashlib.md5(p.read_bytes()).hexdigest(): p for p in (REPO / "fastlane/screenshots/en-US").rglob("*.png")}
    for name, s in json.loads((BASE / "en-live.json").read_text()).items():
        out = BASE / "en-live" / name
        out.mkdir(parents=True, exist_ok=True)
        for i, f in enumerate(s["frames"], 1):
            target = out / f"{i:02d}_{f['file']}" if not f["file"][:2].isdigit() else out / f["file"]
            src = local.get(f["md5"])
            target.write_bytes(src.read_bytes() if src else urllib.request.urlopen(f["url"], timeout=120).read())
        print(name, len(s["frames"]), "frames", s["frames"][0]["w"], "x", s["frames"][0]["h"], s["display_type"])


if __name__ == "__main__":
    main()
