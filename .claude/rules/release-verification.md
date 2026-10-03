---
paths:
  - "project.yml"
  - "scripts/testflight.sh"
  - "scripts/asc-*.py"
  - "app-store/**"
  - "fastlane/screenshots/**"
  - "fastlane/metadata/**"
---

# Build 19 verification, 2026-09-18

Build 19 is attached to the draft App Store version 1.0 and
`scripts/asc-readiness.py` reports no gaps. Builds 17 to 19 added PDF feed
gaps and lb/oz units, weight wheels, the one-card Summary with PDFKit
preview, a paywall that leads with the baby's own page, trend legends, and
polish from `project-docs/audits/laudit913.md` and `~/uadit916.md`. The paywall review
screenshots were re-rendered and re-uploaded for all three products.
Store screenshots were captured from `5c1b697`; the summary thumbnail and the
sleep frame's "Asleep 0m" (now "Asleep just now") are the visible drift.

## App tests

Leased headless simulators from the pool, released afterwards. Performance
spot check (simulator, 10,000 entries): tap-to-log 94 ms, full reload 237 ms.

- `Baby` scheme: 75 tests, zero failures (build 19 source).
- `BabyUITests/PaywallScreenshotUITests`: three tests, zero failures.
- `BabyUITests/LoggingUITests`: seven tests, zero failures.
- `python3 scripts/design-audit.py`: zero drift, two existing plain-style
  advisories for the Watch and widget.

## Listing

- Description leads with "Ultra simple baby tracking", names the buttons Pee,
  Poop, Sleep with the Wet and Dirty setting, and credits the First Weeks
  diaper table to NHS Healthier Together as a reference, not a target.
- Categories: primary Health & Fitness, secondary Lifestyle. Keep
  `fastlane/metadata/primary_category.txt` at `HEALTH_AND_FITNESS`: fastlane
  `upload_metadata` pushes it, and it read `MEDICAL` until this pass, which
  flipped the live category once.
- Review notes (`scripts/asc-configure-listing.py --notes-only`) describe
  Start or Join onboarding, Pee and Poop, the NHS reference, logging together
  by QR code, and Baby+ as doctor reporting only.
- Regulated Medical Device: declared not a medical device in any region
  (checked in the ASC web UI).
- RevenueCat `default` offering is current with monthly, annual and lifetime
  packages, each mapped to its App Store product.

## Localization

The listing is localized into all 50 App Store locales (49 plus en-US), from
`scripts/locale_copy/` via `scripts/build-locale-metadata.py` and
`scripts/asc-upload-localizations.py --all-locales`. Every locale carries the
EULA and privacy links, the 24-hour renewal terms, the non-medical disclaimer
and a note that the app is in English. The app UI itself is English only.
Greek's first name was taken by another app; the upload script now skips a
taken name and carries on.

## Store screenshots

On 2026-09-18 frames 5 (summary) and 6 (sleep) were re-rendered from build
19's source and uploaded; frames 1 to 4 are still the `5c1b697` captures, so
`app-store/capture/capture-report.json` describes those and not frames 5-6.
A late-evening capture put a running sleep on frame 1, which is why the older
frames were kept.


Manifest `app-store/screenshots.json`, direction `simple-care`. The six
iPhone captures were retaken from `5c1b697` (Pee and Poop, outlined graphics,
top undo toast, History list/calendar) and `shotflow all --release` passed
with disposition release-ready. Uploaded in story order with
`scripts/asc-replace-iphone-screenshots.py`.

The Watch image was recaptured from the real Watch target after tapping L and
Pee (`app-store/capture/watch-capture-report.json`) and uploaded with
`scripts/asc-replace-iphone-screenshots.py --watch`. Its clock reads the
simulator time; watchOS does not support status bar overrides.

## Two-parent sharing

Verified on two real phones with different Apple IDs (Jack and Elsa).
Server-side proof, Production, read with `--watch-shares` from the owner's
account on 2026-09-18: the share is read/write, Elsa is `accepted`, and four
entries she logged on 2026-09-17 (feed, feed, dirty, sleep) sit in the
owner's zone as `created_by=someone-else`. The reverse direction (owner
entries on Elsa's phone) was reported by Jack, not observed from the Mac. Production schema and invite
routine were verified separately (`docs/two-parent-acceptance.md`).

No App Review submission was authorized or performed in this pass.

# Build 21 verification, 2026-09-26

Build 21 fixes the History delete animation, routes interactive logging through
the app process and `EventStore`, and merges overlapping sleep entries in daily
totals and the pediatrician report. The Baby+ paywall keeps the real or labelled
example PDF preview as its lead pitch. Onboarding remains purchase-free.

- `Baby` scheme: 78 tests, zero failures.
- `BabyUITests/LoggingUITests/testDeletingFromHistoryCanBeUndone`: passed.
- `BabyUITests/PaywallScreenshotUITests`: three StoreKit screenshots passed;
  the report preview and billed plans rendered.
- `python3 scripts/design-audit.py`: zero drift, two existing style advisories.
- `./scripts/testflight.sh`: build 21 archive succeeded and upload to App Store
  Connect succeeded. Apple reported the uploaded package is processing.
- A live two-account CloudKit run was not repeated. Partner delivery remains
  asynchronous; see `docs/two-parent-acceptance.md`.

## App intent runtime check, 2026-09-27

- On an iOS 26.5 simulator, the Feed App Shortcut logged a right-side feed and
  changed today's total from three to four. The Sleep App Shortcut started a
  timer. Wake in the expanded Dynamic Island stopped it, and Now returned to
  Sleep. This used `-NoCloudKit`, so it verifies intent dispatch and local
  `EventStore` updates, not CloudKit delivery.
- The standard ad hoc simulator signature caused App Intents to reject the
  shortcut provider. Re-signing the simulator app with the existing YXG4
  distribution identity enabled the runtime check. The TestFlight build is
  `VALID` in App Store Connect.
- Visual issues observed: Wake wraps onto two lines in the Lock Screen Live
  Activity, and the elapsed label truncates in the expanded Dynamic Island.
  The Now screen does not show whether an entry has reached the shared log.
- No physical iPhones were connected, so the two-account CloudKit round trip
  remains unverified in this pass.

## One-tap widget check, 2026-09-28

`BabyUITests/WidgetUITests` adds the Pee button widget from the Home Screen
gallery and taps it; the tile's value goes from "3 today" to "4 today". App
Intents only run for a signed build, so run it as `build-for-testing`, re-sign
`Baby.app` and `PlugIns/BabyWidget.appex` with the Apple Development identity
(`codesign --force --sign <id> --preserve-metadata=entitlements,identifier`),
then `TEST_RUNNER_BABY_WIDGET_TEST=1 xcodebuild test-without-building` (it skips
without that variable). The Lock Screen circles and iOS 18 controls
were compiled but not driven in the simulator.

# Build 37 navigation verification, 2026-10-02

Log, History, Upgrade / Reports and Settings share a compact bottom capsule.
The Log page gives the hour strip's space to the logging controls when needed;
the strip returns when more room is available.

- `Baby` scheme: 120 unit tests, zero failures.
- `LoggingUITests` and `PaywallScreenshotUITests`: 21 tests, zero failures on
  iPhone 17e. The earlier iPhone 17 Pro run also passed all 21 tests.
- Final iPhone 17 Pro captures verify idle, feed side chips and Sleep disabled:
  logging controls and Add an older entry stay above all four 68 x 44pt tabs.
- Checked the capsule in Light, Dark, Night light and accessibility text sizes.
- `python3 scripts/design-audit.py`: zero drift, seven style advisories.
- `./scripts/testflight.sh`: version 1.3, build 37 archived and uploaded
  successfully. Xcode reported the uploaded package is processing.
- Evidence: `build/navigation-resume/`, including the unit and UI result
  bundles, final phone captures and `testflight.log`.
