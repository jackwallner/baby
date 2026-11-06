---
paths:
  - "artifacts/asc-screenshots/**"
  - "fastlane/screenshots/**"
  - "BabyUITests/LocalizedStoreScreenshotUITests.swift"
  - "BabyUITests/StoreScreenshotLocales.json"
---

# Localized store sets

Recapture with `artifacts/asc-screenshots/l10n-20261105/tools/capture.sh`.
Pass comma-separated store locales to limit a run; the English baseline is
always included. One XCUITest job reads `BabyUITests/StoreScreenshotLocales.json`
and captures Log, History, First Weeks and Summary on iPhone 17 Pro Max after a
14-second wait. It writes ignored files under `raw/`. Reskin into `out/`, gate
with `Shared/Localizable.xcstrings`, and copy only root PNGs into the target
`fastlane/screenshots/<locale>/` folders.

The current app screens have changed since the English store frames. Pixel
matching cannot locate them, so `frames.json` uses the consistent bezel bounds
measured from all four English frames. The app's DEBUG screenshot routes and
seeded fixtures provide real localized screens, with CloudKit and RevenueCat
disabled. The First Weeks table scales translated column names onto one line.
`Baby+` is a fixed brand, so the gate keeps its plus sign when checking for
English leaks.
