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
Each target keeps its own `InfoPlist.xcstrings` for its display name and any
purpose strings. English is the only shipped language until a translation run
is approved. Do not add `CFBundleLocalizations` early.

Use whole sentences and complete labels as catalog keys. Computed `String`
values must use `String(localized:)`; SwiftUI literals can stay in their local
view APIs. Do not build sentences from translated fragments. Use catalog plural
variations for count phrases, and `Format.pluralForm(_:)` when code needs to
choose a separate localized noun label. Keep the format arguments and plural
forms in sync with the source key.

Use Foundation formatters for dates, numbers, units and durations. Prices come
from StoreKit. Translate stored defaults only when displaying them. Never
translate or rewrite event values, CloudKit fields, share titles, analytics
keys, intent identifiers or CSV headers. User-entered notes remain verbatim.

Run `python3 Tools/Localization/check.py` after changing user-facing copy. It
checks source keys, English catalog entries, plural format arguments, and raw
returned or ternary strings. `BabyTests/LocalizationTests.swift` checks that
English plural forms are present in the app bundle.
