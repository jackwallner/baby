#!/usr/bin/env python3
"""Check that user-facing Swift copy is routed through the English catalogs."""
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIRS = ["Baby", "BabyWidget", "BabyWatch", "BabyWatchWidget", "Shared"]
LANGS = ['de', 'es', 'it', 'pt-BR']
UI_FUNCS = {
    "Text", "Button", "Label", "Section", "Toggle", "TextField", "navigationTitle",
    "accessibilityLabel", "accessibilityValue", "accessibilityHint", "alert", "DatePicker",
    "Stepper", "Link", "configurationDisplayName", "displayName", "description", "eyebrow",
    "confirmationDialog", "Picker", "LocalizedStringKey", "SecureField", "widgetLabel",
    "Summary", "IntentDescription", "LocalizedStringResource", "SharePreview", "LabeledContent",
    "accessibilityAction",
}
# A Double reaches the catalog as %lf; %lg prints 5.5 and 6 rather than 6.000000.
SPEC_ALIASES = {"lg": "lf"}
# Translated fragments and case changes interpolated into a localized sentence.
SPLICE_RE = re.compile(r"\bsides?(?:\[\d+\])?\.label\b|\blowercaseLabel\b|\btrialLabel\b|\.lowercased\(\)|\.uppercased\(\)")
PLIST_TARGETS = ["Baby", "BabyWidget", "BabyWatch", "BabyWatchWidget"]
RAW_RETURN_EXCEPTIONS = {
    # Stable fallback used in the persistent CloudKit share title.
    ("Shared/Models/BabyModel.swift", "Baby"),
    # CSV quoting helper, URL builder, and event de-duplication markers.
    ("Shared/Services/SummaryReport.swift", r'\"\('),
    # Internal StoreService diagnostic field serialization.
    ("Shared/Services/StoreService.swift", r"\(key)"),
    ("Shared/Utilities/AppStoreReviewLinks.swift", "https://"),
    ("Shared/Services/DuplicateEvents.swift", "0"),
    ("Shared/Services/DuplicateEvents.swift", "1"),
}
# Debug logs and probes are intentionally not user-facing copy.
RAW_RETURN_PATH_EXCEPTIONS = {
    "Shared/Services/SimPartnerRelay.swift",
}
RAW_TERNARY_EXCEPTIONS = {
    ("Baby/App.swift", '"chart.bar.doc.horizontal"'),
}
# Direct switch results that are SF Symbols or internal purchase states.
RAW_CASE_EXCEPTIONS = {
    ("Baby/App.swift", "heart"),
    ("Baby/App.swift", "clock.arrow.circlepath"),
    ("Baby/App.swift", "gearshape"),
    ("Baby/Views/PaywallView.swift", "doc.text.fill"),
    ("Baby/Views/PaywallView.swift", "chart.bar.fill"),
    ("Baby/Views/PaywallView.swift", "square.and.arrow.up.fill"),
    ("Shared/Utilities/StainGuide.swift", "drop.circle.fill"),
    ("Shared/Utilities/StainGuide.swift", "washer.fill"),
    ("Shared/Utilities/StainGuide.swift", "sparkles"),
    ("Shared/Utilities/StainGuide.swift", "flask.fill"),
    ("Shared/Utilities/StainGuide.swift", "waterbottle.fill"),
    ("Shared/Utilities/StainGuide.swift", "cube.fill"),
    ("Shared/Utilities/StainGuide.swift", "exclamationmark.triangle.fill"),
    ("Shared/Utilities/StainGuide.swift", "drop.triangle.fill"),
    ("Shared/Utilities/StainGuide.swift", "arrow.up.circle.fill"),
    ("Shared/Utilities/StainGuide.swift", "drop.fill"),
    ("Shared/Models/BabyModel.swift", "fork.knife"),
    ("Shared/Models/BabyModel.swift", "drop.fill"),
    ("Shared/Models/BabyModel.swift", "drop.triangle.fill"),
    ("Shared/Models/BabyModel.swift", "moon.fill"),
    ("Shared/Models/BabyModel.swift", "scalemass.fill"),
    ("Shared/Services/StoreService.swift", "purchased"),
    ("Shared/Services/StoreService.swift", "cancelled"),
    ("Shared/Services/StoreService.swift", "pending"),
}


def parse_literal(src: str, i: int):
    """Return the end offset and literal/interpolation segments for a Swift string."""
    if src.startswith('"""', i):
        end = src.find('"""', i + 3)
        return end + 3, None
    i += 1
    parts = []
    buf = ""
    while i < len(src):
        char = src[i]
        if char == '"':
            if buf:
                parts.append(("lit", buf))
            return i + 1, parts
        if char == "\\":
            if i + 1 >= len(src):
                break
            nxt = src[i + 1]
            if nxt == "(":
                if buf:
                    parts.append(("lit", buf))
                    buf = ""
                depth = 1
                j = i + 2
                expr = ""
                while j < len(src) and depth:
                    ch = src[j]
                    if ch == '"':
                        end, _ = parse_literal(src, j)
                        expr += src[j:end]
                        j = end
                        continue
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    expr += ch
                    j += 1
                parts.append(("interp", expr.strip()))
                i = j + 1
                continue
            if nxt == "u" and i + 2 < len(src) and src[i + 2] == "{":
                end = src.find("}", i + 3)
                buf += chr(int(src[i + 3:end], 16))
                i = end + 1
                continue
            buf += {"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}.get(nxt, nxt)
            i += 2
            continue
        buf += char
        i += 1
    return i, parts


def scan(path: Path):
    src = path.read_text()
    rows = []
    stack = []
    square_depth = 0
    brace_depth = 0
    i = 0
    line = 1
    while i < len(src):
        char = src[i]
        if char == "\n":
            line += 1
        if src.startswith("//", i):
            end = src.find("\n", i)
            i = len(src) if end < 0 else end
            continue
        if src.startswith("/*", i):
            end = src.find("*/", i + 2)
            if end < 0:
                break
            line += src[i:end].count("\n")
            i = end + 2
            continue
        if char == '"':
            end, parts = parse_literal(src, i)
            if parts is not None and stack:
                frame = stack[-1]
                arg = frame[1].strip()
                index = frame[2]
                context = None
                if frame[0] == "String" and arg.startswith("localized:"):
                    context = "String"
                elif frame[0] in UI_FUNCS and index == 0 and not re.match(r"[A-Za-z_]\w*\s*:", arg):
                    context = frame[0]
                elif frame[0] in UI_FUNCS and index == 0 and re.match(r"titleKey\s*:", arg):
                    context = frame[0]
                elif frame[0] == "accessibilityAction" and arg.startswith("named:"):
                    context = frame[0]
                elif frame[0] == "AppShortcut" and (arg.startswith("phrases:") or arg.startswith("shortTitle:")):
                    context = "AppShortcut"
                if context:
                    rows.append((line, context, parts))
            line += src[i:end].count("\n")
            if stack:
                stack[-1][1] += src[i:end]
            i = end
            continue
        if char == "[":
            square_depth += 1
        elif char == "]":
            square_depth = max(0, square_depth - 1)
        elif char == "{":
            brace_depth += 1
        elif char == "}":
            brace_depth = max(0, brace_depth - 1)
        if char == "(":
            match = re.search(r"([A-Za-z_][A-Za-z_0-9]*)\s*$", src[max(0, i - 80):i])
            stack.append([match.group(1) if match else "", "", 0, square_depth, brace_depth])
        elif char == ")":
            if stack:
                stack.pop()
        elif char == "," and stack and square_depth == stack[-1][3] and brace_depth == stack[-1][4]:
            stack[-1][1] = ""
            stack[-1][2] += 1
        elif stack:
            stack[-1][1] += char
        i += 1
    return rows


def loose(key: str) -> str:
    return re.sub(r"%(?:\d+\$)?(?:lld|lf|@)", "%*", key)


def specs(value: str, substitutions=None):
    found = []
    automatic = 0
    substitutions = substitutions or {}
    pattern = r"%(?:(\d+)\$)?(lld|lf|@|%)|%#@(\w+)@|(%arg)"
    for match in re.finditer(pattern, value):
        if match.group(2) == "%":
            continue
        if match.group(3):
            sub = substitutions.get(match.group(3), {})
            found.append((sub.get("argNum"), SPEC_ALIASES.get(sub.get("formatSpecifier"), sub.get("formatSpecifier"))))
        elif match.group(4):
            sub = next(iter(substitutions.values()), {})
            found.append((sub.get("argNum"), sub.get("formatSpecifier")))
        else:
            automatic += 1
            found.append((int(match.group(1)) if match.group(1) else automatic, match.group(2)))
    return sorted(set(found))


def raw_source_key(parts):
    has_interp = any(kind == "interp" for kind, _ in parts)
    out = []
    for kind, value in parts:
        if kind == "lit":
            out.append(value.replace("%", "%%") if has_interp else value)
        else:
            if is_double_expression(value):
                out.append("%lf")
            else:
                out.append("%lld" if is_integer_expression(value) else "%@")
    return "".join(out)


def is_double_expression(expression: str) -> bool:
    return bool(re.search(r"\b(?:wet|dirty)Average\b", expression))


def is_integer_expression(expression: str) -> bool:
    expr = expression.strip()
    if any(token in expr for token in (".formatted(", "Format.", ".label", ".title", ".summary", ".joined(", ".localized", "String(", "formattedDate", "hourLabel(")):
        return False
    if re.search(r"\b(?:count|day|number|feeds|n|page|hour|hours|minutes|unlogged|lifeDay|skipped|durationMinutes|separateLogCount|savingsPercent)\b", expr):
        return True
    if re.search(r"\bperiod\.value\b|\btally\.(?:wet|dirty|feeds)\b|\bs\.today(?:Feeds|Wet|Dirty)\b|\bcompleteDays\.count\b|\bpartial\.count\b|\b(?:wet|dirty|feeds)(?:Min|Max)\b|Guidance\.tallyDays|store\.waitingCount", expr):
        return True
    return False


def source_keys():
    rows = []
    for directory in DIRS:
        root = ROOT / directory
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            for line, context, parts in scan(path):
                key = raw_source_key(parts)
                if key.strip():
                    rows.append((path.relative_to(ROOT).as_posix(), line, context, key))
    return rows


def raw_copy_problems():
    problems = []
    raw_return = re.compile(r'\breturn\s+("(?:\\.|[^"\\])*")')
    ternary = re.compile(r'\?\s*("(?:\\.|[^"\\])*")\s*:\s*("(?:\\.|[^"\\])*")')
    case_value = re.compile(r'(?m)^\s*case\b[^:\n]*:\s*(?:"((?:\\.|[^"\\])*)"|\n\s*"((?:\\.|[^"\\])*)")')
    for directory in DIRS:
        root = ROOT / directory
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            src = path.read_text()
            for match in case_value.finditer(src):
                literal = match.group(1) if match.group(1) is not None else match.group(2)
                if not literal or (rel, literal) in RAW_CASE_EXCEPTIONS:
                    continue
                if not re.search(r"[A-Za-z]{2,}", literal):
                    continue
                line_number = src.count("\n", 0, match.start()) + 1
                problems.append(f"{rel}:{line_number}: raw switch string {literal!r}")
            if rel not in RAW_RETURN_PATH_EXCEPTIONS:
                for match in raw_return.finditer(src):
                    literal = match.group(1)[1:-1]
                    if not literal or literal.isdigit():
                        continue
                    if any(rel == name and token in literal for name, token in RAW_RETURN_EXCEPTIONS):
                        continue
                    if not re.search(r"[A-Za-z]{2,}", literal) and literal not in {"–", "\u2014", "..."}:
                        continue
                    line_number = src.count("\n", 0, match.start()) + 1
                    problems.append(f"{rel}:{line_number}: raw returned string {match.group(1)}")
            for match in ternary.finditer(src):
                start = match.start()
                line_number = src.count("\n", 0, start) + 1
                context = src[max(0, start - 120):min(len(src), match.end() + 100)]
                if any(marker in context for marker in ("systemName:", "systemImage:", "paywallImpressionID:", "defaults.set(", "attributes[")):
                    continue
                if any(rel == filename and marker in context for filename, marker in RAW_TERNARY_EXCEPTIONS):
                    continue
                if rel in {"Shared/Services/SimPartnerRelay.swift", "Shared/Services/StoreService.swift", "Shared/Services/ConversionDiagnostics.swift"}:
                    continue
                branches = [part[1:-1] for part in match.groups()]
                if any(re.search(r"[A-Za-z]{2,}", branch) for branch in branches):
                    problems.append(f"{rel}:{line_number}: raw string ternary {match.group(0)}")
    return problems


def substitution_problems(key: str, loc: dict):
    """A plural variation must not repeat text its host string already has."""
    problems = []
    substitutions = loc.get("substitutions")
    if not substitutions:
        return problems
    host = loc.get("stringUnit", {}).get("value", "")
    host_words = set(re.findall(r"[^\W\d_]{2,}", re.sub(r"%(?:\d+\$)?(?:#@\w+@|lld|lf|lg|@)", " ", host)))
    for name, sub in substitutions.items():
        plural = sub.get("variations", {}).get("plural", {})
        if not {"one", "other"} <= set(plural):
            problems.append(f'"{key}" substitution {name} needs one and other')
        for category, form in plural.items():
            value = form["stringUnit"]["value"]
            if re.search(r"%(?:\d+\$)?(?:@|lld|lf|lg)", value):
                problems.append(f'"{key}" {category} form "{value}" repeats an argument; use only %arg')
            repeated = host_words & set(re.findall(r"[^\W\d_]{2,}", value.replace("%arg", " ")))
            if repeated:
                problems.append(f'"{key}" {category} form "{value}" repeats {sorted(repeated)} from "{host}"')
    return problems


def splice_problems():
    problems = []
    for directory in DIRS:
        root = ROOT / directory
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            for line, context, parts in scan(path):
                for kind, value in parts:
                    if kind == "interp" and SPLICE_RE.search(value):
                        problems.append(f"{rel}:{line}: {value} is spliced into a localized sentence ({context})")
    return problems


def unit_problems():
    problems = []
    for directory in DIRS:
        root = ROOT / directory
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            src = path.read_text()
            if "MeasurementFormatter()" in src and ".providedUnit" not in src:
                problems.append(f"{rel}: MeasurementFormatter must keep the unit it is given (.providedUnit)")
            if "UnitMass(symbol" in src:
                problems.append(f"{rel}: use UnitMass.pounds and friends, not a custom UnitMass")
    return problems


def validate_catalog(path: Path, problems):
    if not path.exists():
        problems.append(f"missing catalog: {path.relative_to(ROOT)}")
        return {}
    data = json.loads(path.read_text())
    if data.get("sourceLanguage") != "en":
        problems.append(f"{path.relative_to(ROOT)}: sourceLanguage must be en")
    strings = data.get("strings", {})
    for key, entry in strings.items():
        if entry.get("extractionState") != "manual":
            problems.append(f'{path.relative_to(ROOT)}: "{key}" is not marked manual')
        localizations = entry.get("localizations", {})
        for lang in LANGS:
            loc = localizations.get(lang)
            if loc is None:
                problems.append(f'{path.relative_to(ROOT)}: "{key}" missing {lang}')
                continue
        if extra := set(localizations) - {"en", *LANGS}:
            problems.append(f'{path.relative_to(ROOT)}: "{key}" has unlisted languages {sorted(extra)}')
        loc = localizations.get("en")
        if loc is None:
            problems.append(f'{path.relative_to(ROOT)}: "{key}" missing en')
            continue
        problems.extend(f"{path.relative_to(ROOT)}: {problem}" for problem in substitution_problems(key, loc))
        want = specs(key)
        if "variations" in loc:
            values = [unit["stringUnit"]["value"] for unit in loc["variations"].get("plural", {}).values()]
            bad = [value for value in values if specs(value, loc.get("substitutions")) != want]
        else:
            value = loc.get("stringUnit", {}).get("value", "")
            bad = [] if specs(value, loc.get("substitutions")) == want else [value]
        for value in bad:
            problems.append(f'{path.relative_to(ROOT)}: "{key}" has mismatched format specifiers in "{value}"')
    return strings


def main():
    problems = []
    catalog_path = ROOT / "Shared/Localizable.xcstrings"
    shared_catalog = validate_catalog(catalog_path, problems)
    by_loose = {loose(key): key for key in shared_catalog}
    rows = source_keys()
    for path, line, context, key in rows:
        if loose(key) not in by_loose:
            problems.append(f'{path}:{line}: no catalog key for "{key}" ({context})')
    for target in PLIST_TARGETS:
        info_catalog = validate_catalog(ROOT / target / "InfoPlist.xcstrings", problems)
        info = plistlib.loads((ROOT / target / "Info.plist").read_bytes())
        if missing := {"en", *LANGS} - set(info.get("CFBundleLocalizations", [])):
            problems.append(f"{target}/Info.plist: CFBundleLocalizations is missing {sorted(missing)}")
        for key, value in info.items():
            if key not in {"CFBundleDisplayName", "CFBundleName"} and not key.endswith("UsageDescription"):
                continue
            if not isinstance(value, str) or value.startswith("$("):
                continue
            entry = info_catalog.get(key)
            english = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value") if entry else None
            if english != value:
                problems.append(f'{target}/Info.plist: "{key}" is missing or differs from its English catalog value')
    problems.extend(raw_copy_problems())
    problems.extend(splice_problems())
    problems.extend(unit_problems())
    for problem in problems:
        print(problem)
    print(f"{len(shared_catalog)} keys, {len(LANGS)} translated languages, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
