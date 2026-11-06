---
paths:
  - "Baby/**"
  - "BabyWidget/**"
  - "BabyWatch/**"
  - "BabyWatchWidget/**"
  - "Shared/**"
  - "project.yml"
  - "Tools/Localization/**"
---

# Localization

All user-facing copy for the app, widgets, Watch, Live Activity, intents,
notifications, accessibility, guidance and PDF belongs in
`Shared/Localizable.xcstrings`. XcodeGen compiles that catalog into each target.
It holds `en`, de, es, it and pt-BR. A new language goes in `CFBundleLocalizations`
in each Info.plist, `LANGS` in `check.py` and `languages` in `LocalizationTests`.
Each target keeps its own `InfoPlist.xcstrings` for its display name and any
purpose strings. Store listings in a language the app does not ship say the app
is in English; drop that line from a language when it ships
(`scripts/locale_copy/`).

Use whole sentences and complete labels as catalog keys. Computed `String`
values must use `String(localized:)`; SwiftUI literals can stay in their local
view APIs. Do not build sentences from translated fragments. Use catalog plural
variations for count phrases, and `Format.unitLabel(_:count:)` when a count is
drawn apart from its word. A variation holds only what the host string does not:
either the host is just `%#@n@` and the variation is the whole phrase, or the
host keeps the surrounding text and the variation is the count and its noun. A
fractional average stays a `Double` argument (`%lf` in the key, `lg` in the
substitution), so the catalog can choose its plural form. Keep the format
arguments and plural forms in sync with the source key.

A side, a trial length or a lowercase word is never interpolated into a sentence:
each case gets its own key, so a language can inflect it. `measurement` keeps the
unit it is given (`.providedUnit`, medium style).

A word that is both noun and verb gets two keys: `Log` is the tab (German
"Protokoll"), `Log entry` is the editor's save button ("Eintragen"). Editor titles
sit between two bar buttons, so translations of `Log a feed` and its siblings are
the bare noun; the button already says what happens.

Use Foundation formatters for dates, numbers, units and durations. Prices come
from StoreKit. Translate stored defaults only when displaying them. Never
translate or rewrite event values, CloudKit fields, share titles, analytics
keys, intent identifiers or CSV headers. User-entered notes remain verbatim.

Run `python3 Tools/Localization/check.py` after changing user-facing copy. It
checks source keys, English catalog entries, plural format arguments, variations
that repeat their host text, spliced fragments, unit options, and raw returned or
ternary strings. `BabyTests/LocalizationTests.swift` pins the expanded English for
plurals, units, durations and casing against the app bundle.

Check the tight surfaces by eye in German and Portuguese, the longest languages:
the PDF table (`PDFReport.table` widens columns, then scales all its text
together, and never truncates), the Watch's three-across side row and Today
tiles, and onboarding's feeding chips. The Watch glance shows only the side
beside the feed icon (`Fed · %@` is just `%@` in translations), because "which
side" is what must survive the width.

## Language row

Settings has a Language row that names the running localization in itself
(`Bundle.main.preferredLocalizations`) and opens `openSettingsURLString`, Apple's
route for a per-app language change. iOS hides the app's Language option on a
device with one preferred language unless `UIPrefersShowingLanguageSettings` is
YES in `Info.plist`, so keep that key. The simulator's Settings opens at its root
for this link; check the landing on a real iPhone.
