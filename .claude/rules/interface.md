---
paths:
  - "Baby/App.swift"
  - "Baby/Views/**"
  - "Shared/Utilities/AppTheme.swift"
  - "BabyUITests/**"
---

# Interface direction

Jack's 2026-09-11 direction: keep anything outside the core function tucked
away so it cannot interfere with tracking. The home screen has no feature
discovery or monetization. It answers the last-feed question and offers the
same logging controls in the same order.

History belongs one tap from home. Reports, first-weeks guidance, sharing,
stain help and Baby+ live in More. Do not restore a four-tab layout or an
onboarding paywall. Name and birth date are optional; never guess a birth date
for someone who did not choose one.

Animate only meaningful feedback, using the shared spring and respecting
Reduce Motion. Keep text readable in dark mode and at accessibility sizes.
Use vertical layouts when the side-by-side version no longer fits.

Verification: LoggingUITests covers direct logging, long-press cancellation,
Undo, sleep/wake, one-screen onboarding, and free access to the tucked-away
tools. SharingTests protects the owner's log and separates invitation failures
from an intentional stop-sharing action. Real cross-account iCloud sync still
requires two signed-in devices and a deployed production schema.
