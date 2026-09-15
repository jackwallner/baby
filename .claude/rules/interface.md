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

History belongs one tap from home, as a List or a month Calendar (dots
per kind, tap a day for its entries). The calendar grid is plain stacks: a
LazyVGrid inside a List cell crashed UICollectionView self-sizing. The Undo
toast is pinned to the top over the navigation bar (swipe up to dismiss), so
it never lands mid-screen over the log controls. Reports, first-weeks guidance, sharing,
stain help and Baby+ live in More. Do not restore a four-tab layout or an
onboarding paywall. Name and birth date are optional; never guess a birth date
for someone who did not choose one.

Animate only meaningful feedback, using the shared spring and respecting
Reduce Motion. Keep text readable in dark mode and at accessibility sizes.
Use vertical layouts when the side-by-side version no longer fits.

Verification: LoggingUITests covers direct logging, long-press cancellation,
Undo, sleep/wake, one-screen onboarding, and free access to the tucked-away
tools. SharingInterfaceUITests covers the invite explanation, the invite code
and link, joining from onboarding and More, and the four appearance options.
SharingTests protects the owner's log and separates invitation failures
from an intentional stop-sharing action. Real cross-account iCloud sync still
requires two signed-in devices and a deployed production schema.
