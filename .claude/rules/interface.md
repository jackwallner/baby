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

Backfilling lives at the very bottom of Now as a quiet "Add an older entry"
menu (Feed, Pee, Poop, Sleep, Weight) that opens the same editor as History's
plus button; the editor's date picker does the rest. Added 2026-09-26 for
version 1.1, because parents install on day three and want the first days in.

2026-09-28 (Jack): Feed is one button. A tap logs a feed with no side;
then an "Add a side (optional)" row of Left / Right / Bottle chips opens
under it for 90 seconds and edits that feed (multi-select, stored in tap
order in the existing `side` string as `right,left`, so no schema change and
older builds still read single sides). The widget's Feed and the plain Siri
Feed log no side either; the Watch keeps its L / R / Bottle taps. A "Logging
at" row above the buttons winds the log time back (minus and plus step the
five-minute grid, the time opens a wheel); taps log at that time and it
returns to now 60 seconds after the last touch, with a countdown under the
buttons. The editor's time is an inline wheel (a compact picker's popover
covered Save); existing entries autosave with Done only, new entries still
need Log. Totals count from a day-start hour or the last 24 hours (More >
Daily totals, `TotalsWindow`), with a four-row hourly strip beneath
(`WindowTotals`); History and reports keep calendar days.

One-tap logging outside the app (2026-09-28): three single-button widgets,
Feed, Pee and Poop (`BabyWidget/QuickLogWidgets.swift`), each a Lock Screen
circle or a Home Screen small tile; separate widgets rather than one
configurable one so each is ready to place from the gallery. iOS 18+ also
gets Log feed / Log pee / Log poop controls for the Lock Screen corners,
Control Center and the Action button. `LogEventIntent` is
`.alwaysAllowed`, so a locked phone logs like the flashlight. The existing
four-button "One-tap log" widget and its rectangular Lock Screen row stay.

Widget Undo (2026-09-28, Jack: no confirm before logging). After a one-button
widget logs, that tile shows "Logged / Undo" (the Lock Screen circle an undo
arrow) for 10 seconds, then its normal face. `LogEventIntent` records the
entry in `WidgetUndo` (App Group); `UndoWidgetLogIntent` deletes exactly that
id and reopens any feed timer the log ended, accepting a tap up to 60 seconds
in case WidgetKit redraws late. Controls, the Action button and Siri have no
surface for it; History's swipe-to-delete covers them. The four-button widget
has no Undo. A second tap of the same kind within 3 seconds (before the tile
could redraw) logs nothing, and a stale Undo never clears a newer tap's Undo.

Animate only meaningful feedback, using the shared spring and respecting
Reduce Motion. Keep text readable in dark mode and at accessibility sizes.
Use vertical layouts when the side-by-side version no longer fits.

Verification: LoggingUITests covers direct logging, optional feed sides, the
wound-back log time, editor autosave, the totals window, long-press cancellation,
backfilling yesterday without touching today's totals, Undo, sleep/wake, one-screen onboarding, and free access to the tucked-away
tools. SharingInterfaceUITests covers the invite explanation, the invite code
and link, joining from onboarding and More, and the four appearance options.
SharingTests protects the owner's log and separates invitation failures
from an intentional stop-sharing action. Real cross-account iCloud sync still
requires two signed-in devices and a deployed production schema.
