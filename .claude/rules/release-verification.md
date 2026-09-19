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
polish from `laudit913.md` and `~/uadit916.md`. The paywall review
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
