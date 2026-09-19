---
paths:
  - "project.yml"
  - "scripts/testflight.sh"
  - "scripts/asc-*.py"
  - "app-store/**"
  - "fastlane/screenshots/**"
  - "fastlane/metadata/**"
---

# Build 17 verification, 2026-09-18

Build 17 (app source `ae99b20`: pediatrician PDF feed gaps, lb/oz units,
weight wheels) is attached to the draft App Store version 1.0.
`scripts/asc-readiness.py` reports no gaps. Screenshots below were captured
from `5c1b697`; in build 17 only the small PDF thumbnail on the summary
screenshot differs (name as title, a gap column).

## App tests

Leased headless simulator `3BA38835-1CCB-4BBA-8045-4F0DD14AED56` (slot 4),
released afterwards.

- `Baby` scheme: 76 tests, zero failures (build 17 source).
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

Verified on two real phones with different Apple IDs (Jack and Elsa).
Server-side proof, Production, read with `--watch-shares` from the owner's
account on 2026-09-18: the share is read/write, Elsa is `accepted`, and four
entries she logged on 2026-09-17 (feed, feed, dirty, sleep) sit in the
owner's zone as `created_by=someone-else`. The reverse direction (owner
entries on Elsa's phone) was reported by Jack, not observed from the Mac. Production schema and invite
routine were verified separately (`docs/two-parent-acceptance.md`).

No App Review submission was authorized or performed in this pass.
