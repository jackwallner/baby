#!/usr/bin/env python3
"""Fail the build's conscience when a screen stops using the design system.

    python3 scripts/design-audit.py

Read-only. Reads the tokens out of `Shared/Utilities/AppTheme.swift` and checks
every other view file against them: spacing literals that are not tokens,
circular corners, colours defined outside the theme, custom fonts, and (as an
advisory) `.buttonStyle(.plain)` on things that should answer back.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
THEME = ROOT / "Shared/Utilities/AppTheme.swift"
SEARCH = ["Baby", "BabyWidget", "BabyWatch", "BabyWatchWidget", "Shared"]

SPACING = re.compile(
    r"""(?x)
    (?:\.padding\(\s*(?:\.\w+\s*,\s*)?
      |spacing:\s*
      |minLength:\s*
      |listRowInsets\(EdgeInsets\(.*?:\s*
    )(\d+(?:\.\d+)?)
    """
)
CIRCULAR = re.compile(r"RoundedRectangle\((?![^)]*continuous)[^)]*\)")
PLAIN = re.compile(r"\.buttonStyle\(\.plain\)")
RAW_COLOR = re.compile(r"Color\(\s*red:")
CUSTOM_FONT = re.compile(r"Font\.custom|\.font\(\.custom")

EXEMPT_SPACING = {
    "0",    # No gap is not a spacing decision.
    "44",   # Apple's minimum tap target. A token would hide whose rule it is.
}


def tokens() -> dict[str, str]:
    return dict(re.findall(r"static let (\w+): CGFloat = (\d+)", THEME.read_text()))


def swift_files() -> list[pathlib.Path]:
    out: list[pathlib.Path] = []
    for top in SEARCH:
        out += sorted((ROOT / top).rglob("*.swift"))
    return [p for p in out if p != THEME]


def main() -> int:
    scale = tokens()
    by_value = {v: k for k, v in scale.items()}
    failures: list[str] = []
    advisories: list[str] = []

    for path in swift_files():
        rel = path.relative_to(ROOT)
        for number, line in enumerate(path.read_text().splitlines(), start=1):
            code = line.split("//", 1)[0]
            where = f"{rel}:{number}"
            for value in SPACING.findall(code):
                if value in EXEMPT_SPACING:
                    continue
                name = by_value.get(value)
                hint = f"AppTheme.{name}" if name else "a token in AppTheme"
                failures.append(f"{where}: spacing literal {value}, use {hint}")
            if CIRCULAR.search(code):
                failures.append(f"{where}: RoundedRectangle without a continuous curve, use AppTheme.cardShape or AppTheme.buttonShape")
            if RAW_COLOR.search(code):
                failures.append(f"{where}: a colour defined outside AppTheme")
            if CUSTOM_FONT.search(code):
                failures.append(f"{where}: a custom font. The app is SF Pro.")
            if PLAIN.search(code):
                advisories.append(f"{where}: .buttonStyle(.plain). If this is a card or a row, .pressableCard() gives it a press state.")

    for line in failures:
        print(f"drift: {line}")
    if advisories:
        print()
        for line in advisories:
            print(f"look at: {line}")
    print()
    print("scale: " + ", ".join(f"{k} {v}" for k, v in sorted(scale.items(), key=lambda kv: int(kv[1]))))
    print(f"{len(failures)} drifted, {len(advisories)} worth a look, across {len(swift_files())} files")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
