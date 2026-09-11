#!/usr/bin/env python3
"""Fail the build's conscience when a screen stops using the design system.

    python3 scripts/design-audit.py

Read-only. It reads `Shared/Utilities/AppTheme.swift` for the tokens and then
checks every other view file against them.

This exists because a design system that has to be remembered is a design system
that lasts about three screens. Every rule here was already written down in
`AppTheme` and in this repo's own comments, and every one of them had drifted
anyway: eight different values for "a small gap", a thumbnail with its own
corner radius, and a paywall whose plan cards used `.buttonStyle(.plain)` and so
did not react to being pressed at all. None of that is visible as a mistake in a
diff. It is only visible as a screen that looks almost right, which is exactly
the reading that does not get a credit card typed into it.

Three things it checks that a linter would not:

  * **Continuous corners, not circular.** `RoundedRectangle(cornerRadius:)`
    defaults to a quarter circle spliced onto a straight edge. Every corner
    Apple draws on this phone is a continuous curve, and the mismatch is the
    single most reliable tell that a screen was assembled rather than designed.
  * **Numbers that are not tokens.** Not "is this number ugly" but "is this
    number a decision somebody can find again". A 14 typed into a view is
    invisible to the next person changing the 12 next to it.
  * **Buttons that do not answer back.** `.buttonStyle(.plain)` on a card is how
    a card stops looking like a system button and also how it stops reacting to
    touch. Advisory rather than fatal, because plain is right for a button that
    is really a label.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
THEME = ROOT / "Shared/Utilities/AppTheme.swift"
SEARCH = ["BabyDocs", "Shared"]

# Spacing literals are only allowed to be zero. Everything else is a token, so
# that changing the app's rhythm is one edit rather than a search-and-replace
# somebody stops halfway through.
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

# The exemptions, each with a reason, because an exemption list without reasons
# grows until the check means nothing.
EXEMPT_SPACING = {
    "0",    # No gap is not a spacing decision.
    "44",   # Apple's minimum tap target. A token would hide whose rule it is.
}


def tokens() -> dict[str, str]:
    text = THEME.read_text()
    found = dict(re.findall(r"static let (\w+): CGFloat = (\d+)", text))
    return found


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
                name = by_value.get(value.rstrip(".0") or value)
                hint = f"AppTheme.{name}" if name else "a token in AppTheme"
                failures.append(f"{where}: spacing literal {value}, use {hint}")

            if CIRCULAR.search(code):
                failures.append(
                    f"{where}: RoundedRectangle without a continuous curve, "
                    "use AppTheme.cardShape or AppTheme.innerShape"
                )

            if RAW_COLOR.search(code):
                failures.append(f"{where}: a colour defined outside AppTheme")

            if CUSTOM_FONT.search(code):
                failures.append(
                    f"{where}: a custom font. The app is SF Pro, which is the "
                    "one typeface that belongs on this phone."
                )

            if PLAIN.search(code):
                advisories.append(
                    f"{where}: .buttonStyle(.plain). If this is a card or a row "
                    "rather than a label, .pressableCard() gives it a press state."
                )

    for line in failures:
        print(f"drift: {line}")
    if advisories:
        print()
        for line in advisories:
            print(f"look at: {line}")

    print()
    print(f"scale: " + ", ".join(f"{k} {v}" for k, v in sorted(scale.items(), key=lambda kv: int(kv[1]))))
    print(f"{len(failures)} drifted, {len(advisories)} worth a look, across {len(swift_files())} files")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
