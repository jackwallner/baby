#!/usr/bin/env python3
"""Write `fastlane/metadata/<locale>/` for every storefront from the copy in
`scripts/locale_copy/`.

Each locale carries its own name, subtitle, keywords, promotional text and the
paragraphs of its description. The description always ends with the
subscription disclosure, the non-medical disclaimer, a note that the app itself
is in English, and working Terms of Use and Privacy Policy links (App Review
3.1.2 checks every storefront, not only en-US).

Keywords drop any word already in that locale's name or subtitle (Apple
indexes those anyway), then keep terms in order until the next one would pass
100 characters.

    python3 scripts/build-locale-metadata.py            # write and validate
    python3 scripts/asc-upload-localizations.py --all-locales
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane" / "metadata"
COPY = Path(__file__).resolve().parent / "locale_copy"
EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
PRIVACY = "https://jackwallner.github.io/baby/privacy-policy.html"
URLS = {
    "marketing_url": "https://jackwallner.github.io/baby/",
    "support_url": "https://jackwallner.github.io/baby/support.html",
    "privacy_url": PRIVACY,
}
PARAGRAPHS = ("intro", "buttons", "outside", "together", "weeks", "free", "plus", "sub", "disc")
DENSE = {"ja", "ko", "zh-Hans", "zh-Hant"}
SEPARATOR = {"ja": "、", "zh-Hans": "，", "zh-Hant": "，"}


def load() -> dict[str, dict]:
    copy: dict[str, dict] = {}
    for path in sorted(COPY.glob("*.py")):
        spec = importlib.util.spec_from_file_location(path.stem, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        copy.update(module.COPY)
    return copy


def words(text: str) -> set[str]:
    return {w for w in re.split(r"[\s,:&·\-/،、，]+", text.lower()) if w}


def keywords(entry: dict) -> str:
    taken = words(entry["name"]) | words(entry["subtitle"])
    kept: list[str] = []
    for term in entry["keywords"].split(","):
        term = term.strip()
        if not term or term.lower() in taken or term in kept:
            continue
        if len(",".join(kept + [term])) > 100:
            continue
        kept.append(term)
    return ",".join(kept)


def description(entry: dict) -> str:
    body = "\n\n".join(entry[key] for key in PARAGRAPHS)
    return f"{body}\n\n{entry['terms']}: {EULA}\n{entry['privacy']}: {PRIVACY}\n"


def main() -> int:
    bad = []
    copy = load()
    for locale, entry in sorted(copy.items()):
        folder = META / locale
        folder.mkdir(parents=True, exist_ok=True)
        fields = {
            "name": entry["name"],
            "subtitle": entry["subtitle"],
            "keywords": keywords(entry),
            "promotional_text": entry["promo"],
            "description": description(entry),
            **URLS,
        }
        for field, value in fields.items():
            (folder / f"{field}.txt").write_text(value.strip() + "\n")
        low = 10 if locale in DENSE else 24
        problems = []
        if not low <= len(entry["name"]) <= 30:
            problems.append(f"name {len(entry['name'])}")
        if not low <= len(entry["subtitle"]) <= 30:
            problems.append(f"subtitle {len(entry['subtitle'])}")
        kw = len(fields["keywords"])
        if not (0 if locale in DENSE else 94) <= kw <= 100:
            problems.append(f"keywords {kw}")
        if len(entry["promo"]) > 170:
            problems.append(f"promo {len(entry['promo'])}")
        if len(fields["description"]) > 4000:
            problems.append(f"description {len(fields['description'])}")
        if problems:
            bad.append(locale)
            print(f"{locale}: {', '.join(problems)}")
    print(f"{len(copy) - len(bad)} of {len(copy)} locales within limits")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
