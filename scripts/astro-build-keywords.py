#!/usr/bin/env python3
"""
Build Astro keyword list from fastlane en-US metadata.

Outputs scripts/astro-keywords-{store}.json
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

# Generic high-intent phrases — agent should extend per app in ~/ios/aso/astro-setup-process.md
GENERIC_PHRASES = [
    "app tracker",
    "daily tracker",
    "free tracker",
    "health app",
    "apple health",
    "healthkit",
]


def read_meta(meta_dir: Path, field: str) -> str:
    path = meta_dir / f"{field}.txt"
    return path.read_text().strip() if path.exists() else ""


def tokens_from_keywords_field(raw: str) -> list[str]:
    return [t.strip().lower() for t in raw.split(",") if t.strip()]


def bigrams_from_text(text: str, min_len: int = 3) -> list[str]:
    words = re.findall(r"[a-z0-9]+", text.lower())
    phrases = []
    for i in range(len(words) - 1):
        a, b = words[i], words[i + 1]
        if len(a) >= min_len and len(b) >= min_len:
            phrases.append(f"{a} {b}")
    return phrases


def name_subtitle_phrases(name: str, subtitle: str) -> list[str]:
    out = []
    for text in (name, subtitle):
        text = text.lower()
        # strip common suffix patterns
        for sep in (" - ", " – ", " — "):
            if sep in text:
                parts = [p.strip() for p in text.split(sep)]
                out.extend(parts)
        out.append(text)
    return out


def dedupe(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out = []
    for item in items:
        k = item.strip().lower()
        if k and k not in seen:
            seen.add(k)
            out.append(k)
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--meta-dir", default="fastlane/metadata/en-US")
    parser.add_argument("--store", default="us")
    parser.add_argument("--extra", nargs="*", default=[], help="Extra phrases from agent")
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    meta = Path(args.meta_dir)
    name = read_meta(meta, "name")
    subtitle = read_meta(meta, "subtitle")
    keywords_raw = read_meta(meta, "keywords")
    description = read_meta(meta, "description")[:2000]

    asc_tokens = tokens_from_keywords_field(keywords_raw)
    phrases = (
        name_subtitle_phrases(name, subtitle)
        + bigrams_from_text(f"{name} {subtitle}")
        + bigrams_from_text(description)
        + GENERIC_PHRASES
        + list(args.extra)
    )

    keywords = dedupe(asc_tokens + phrases)
    out_path = Path(args.out or f"scripts/astro-keywords-{args.store}.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "store": args.store,
        "appName": name,
        "ascKeywords": keywords_raw,
        "keywords": keywords,
    }
    out_path.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"Wrote {len(keywords)} keywords to {out_path}")


if __name__ == "__main__":
    main()
