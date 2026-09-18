---
paths:
  - "project.yml"
  - "scripts/testflight.sh"
  - "scripts/asc-*.py"
  - "app-store/**"
  - "fastlane/screenshots/**"
  - "fastlane/metadata/**"
---

# Build 16 verification, 2026-09-18

App source: `5c1b697`. Build 16 is VALID and attached to the draft App Store
version 1.0 (it replaced build 8). `scripts/asc-readiness.py` reports no gaps.

## App tests

Leased headless simulator `3BA38835-1CCB-4BBA-8045-4F0DD14AED56` (slot 4),
released afterwards.

- `Baby` scheme: 73 tests, zero failures.
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
- Regulated Medical Device: declared not a medical device in any region
  (checked in the ASC web UI).
- RevenueCat `default` offering is current with monthly, annual and lifetime
  packages, each mapped to its App Store product.

## Store screenshots

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

Verified on two real phones with different Apple IDs (Jack and Elsa),
2026-09-18: joining and cross-logging worked. Production schema and invite
routine were verified separately (`docs/two-parent-acceptance.md`).

No App Review submission was authorized or performed in this pass.
