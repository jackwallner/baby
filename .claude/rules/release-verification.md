---
paths:
  - "project.yml"
  - "scripts/testflight.sh"
  - "scripts/asc-*.py"
  - "app-store/**"
  - "fastlane/screenshots/**"
---

# Build 5 verification, 2026-09-11

App source: `66bf714`. Build bump: `0b7b3c7`. Release archive and TestFlight
upload succeeded through `./scripts/testflight.sh`.
Build 5 is VALID and attached to the draft App Store version 1.0.
The privacy label is published. Review notes match the simplified navigation.
The final ASC readiness check reports no API-visible gaps. All six iPhone
images and the dedicated Watch image have delivery state `COMPLETE`.

## App tests

All tests used leased headless simulator
`2C7A80C1-1228-411A-B9AD-A7DEED683F79`, iOS 26.5. The lease was released.

- `Baby` scheme: 36 tests, zero failures.
- `BabyUITests/LoggingUITests`: five tests, zero failures.
- `BabyUITests/PaywallScreenshotUITests`: three tests, zero failures.
- `python3 scripts/design-audit.py`: zero drift errors, two existing
  plain-style advisories for the Watch and widget.
- All four target Info.plists passed `plutil -lint`.

Local proof: `build/PolishDerived/Logs/Test/` and
`build/design-review/simple-home.png`, `simple-home-dark.png`, and
`simple-setup.png`. Unit log: `/tmp/baby-polish-final-tests.log`.
UI log: `/tmp/baby-polish-all-ui.log`. Upload log: `/tmp/baby-testflight.log`.

## Store screenshots

Manifest: `app-store/screenshots.json`, direction `simple-care`.
Six canonical captures map to `app-store/capture/capture-report.json`.
The Debug capture binary has the same app source as release build 5.
Raw captures and full render artifacts are local-only; the six upload PNGs
are versioned in `fastlane/screenshots/en-US/`.

Target: 1320 x 2868 opaque RGB. Every image has one period-free benefit
header, no more than two lines, and 64.48% literal UI coverage.
`shotflow all --release` and the separate audit passed with zero errors or
warnings. All 20 renderer tests passed. Source and output hashes, foreground
hashes, masks, and geometry were checked independently of rendering.
Luna 5.6 Max independently reviewed the set. Its sleep-frame caveat was
resolved by describing the one-tap start shown by the just-started timer.

Local review pack: `app-store/rendered/`, including the full contact sheet,
first-three search grid, provenance sidecars, and audit reports.
Build 4's seven iPhone posters were moved to
`build/screenshot-backup-build4/` and remain recoverable from git.
The six new iPhone screenshots were uploaded in story order. A missing
dedicated Watch set was added with the real Watch app at 416 x 496, after
logging a feed and wet diaper through its actual controls. The Watch capture
also passed independent Luna visual review. Its provenance is recorded in
`app-store/capture/watch-capture-report.json`.

## Remaining device verification

Cross-account iCloud sync and sharing are not verified. At the setup audit,
Development and Production had no application record types. A Debug run on
an iCloud-signed-in device must initialize the Core Data schema before it is
deployed to Production. Do not call sharing production-ready without the
schema and a two-account acceptance test. Local logging is unaffected.

No App Review submission was authorized or performed in this pass.
