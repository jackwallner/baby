#!/usr/bin/env python3
"""Check App Store field lengths and keyword hygiene for chosen locales.

Usage: scripts/aso-check-locales.py [locale ...]
Defaults to the nine locales rewritten on 2026-11-20. Exits 1 on any problem.
"""
from __future__ import annotations

import re
import sys
import unicodedata
from pathlib import Path

META = Path(__file__).resolve().parent.parent / "fastlane/metadata"
DEFAULT = ["it", "pt-BR", "es-MX", "es-ES", "en-CA", "fr-CA", "de-DE", "fr-FR", "en-GB"]
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170, "description": 4000}


def read(loc: str, field: str) -> str:
    return (META / loc / f"{field}.txt").read_text(encoding="utf-8").rstrip("\n")


def words(text: str) -> set[str]:
    return {w.casefold() for w in re.findall(r"[\w'’-]+", text)}


def fold(w: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", w) if unicodedata.category(c) != "Mn")


def check(loc: str) -> list[str]:
    problems: list[str] = []
    print(f"== {loc}")
    for field, limit in LIMITS.items():
        text = read(loc, field)
        n = len(text)
        flag = "" if n <= limit else "  OVER"
        print(f"  {field:17} {n:5} / {limit}{flag}")
        if n > limit:
            problems.append(f"{loc} {field} over limit")
        if "—" in text or "–" in text:
            problems.append(f"{loc} {field} has a dash character")
    kws = read(loc, "keywords")
    if ", " in kws or " ," in kws:
        problems.append(f"{loc} keywords has spaces around commas")
    tokens = kws.split(",")
    used = words(read(loc, "name")) | words(read(loc, "subtitle"))
    used_folded = {fold(w) for w in used}
    seen: set[str] = set()
    for t in tokens:
        key = fold(t.casefold())
        if not t:
            problems.append(f"{loc} empty keyword token")
        if key in seen:
            problems.append(f"{loc} duplicate keyword {t}")
        seen.add(key)
        parts = {fold(p) for p in re.split(r"[\s-]+", t.casefold()) if p}
        if key in used_folded or parts & used_folded:
            problems.append(f"{loc} keyword '{t}' repeats a name/subtitle word")
        if t in ("app", "apps"):
            problems.append(f"{loc} keyword 'app'")
    for a in tokens:
        for b in tokens:
            if a != b and (a + "s" == b or a + "es" == b):
                problems.append(f"{loc} singular/plural pair {a}/{b}")
    return problems


def main() -> int:
    locs = sys.argv[1:] or DEFAULT
    problems: list[str] = []
    for loc in locs:
        problems += check(loc)
    print("\nPROBLEMS:" if problems else "\nclean")
    for p in problems:
        print(" ", p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
