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
toast is pinned to the top (swipe up to dismiss), so it never lands mid-screen
over the log controls. First-weeks guidance, sharing and stain help live in
Settings. No onboarding paywall.

2026-10-02 (Jack): all navigation belongs in one small translucent bottom
capsule, like Total Calories, not a full-width bar. Tabs are Log, History,
Upgrade and Settings; Upgrade becomes Reports for Baby+ subscribers, including
immediately after a purchase or restore. Remove the top navigation buttons.
Reserve the capsule's space so it never covers log controls, list rows or the
paywall's billed amount, disclosure and links. Keep Log's one-screen fit and
48pt tab touch targets. Hide inactive screens from accessibility and never
record a paywall impression merely because a hidden tab exists.
Reserve the capsule in a bottom safe-area inset, and exclude its full height
from Now's fit so controls and Add an older entry stay above it. Clip the tabs
so scrolling content stays below the status bar, and hide the system tab bar
on each tab.

The paywall pitches with `ReportPreviews`, three cards (summary page, first
trend chart, export rows) with one rule: the example is sharp, labelled Example
beside its title (the page has its own stamp in the corner), and the baby's own
data is blurred under one Baby+ lock (the page keeps its name and range sharp).

Buttons can be turned off (Settings > Buttons, `TrackedKinds` in the App
Group, carried to the Watch in `NowSummary.hiddenKinds`). `EventStore`
filters its log by them, so History, totals, reports and CSV follow without
their own checks; `NowSummary.make` and `SummaryReport.make` filter too, for
the widget process and tests. The status card leads with the first tracked of
feed, diaper, sleep (`NowSummary.leadKind` for widgets and Watch). A placed
one-button widget for an off kind shows "Off in Settings" and does not log;
a control, the Action button or Siri answers that the button is off.
`-EmptyLog` (DEBUG) opens an in-memory log, for the reviewer's no-data path
(`testReportsShowTheExampleBeforeAnythingIsLogged`).

Motion (2026-09-29): every tap, Undo, side chip and log-time change runs in
one `withAnimation` transaction. Subview `.animation(_:value:)` modifiers
animated one subtree while its siblings jumped, which drew the hint and the
totals over each other. The side chips fade into space the Feed card grows
(clipped, so they never slide over Feed); the hero time crossfades rather
than using the numeric roll, which smeared "just now". Totals are a card: one
figure per button with a kind dot, and the hour strip uses the same dots. Name and birth date are optional; never guess a birth date
for someone who did not choose one.

One screen (2026-09-30, Jack: "dynamically fit on one screen without having
to scroll"). On a phone, Now measures itself (`NowFit`): everything but the
log buttons is a fixed height, and the buttons split what the screen leaves,
between `minLogButtonHeight` and `maxLogButtonHeight`; slack past the cap sits
above the totals. Opening the side chips shrinks the buttons instead of pushing
the page. Sections sit 12 apart; the time row and the buttons, one control,
8. There is no idle "Tap to log now" hint (Jack: not needed); only the
wound-back countdown shows under the buttons. Under `hourStripMinHeight` (an
SE), or when the side chips and minimum button heights need its space, the
hour strip drops. Accessibility sizes and iPad keep
the scrolling layouts.

Reports (2026-09-30, Jack: the old page "doesn't display things in an easy
to see or understand way"; modelled on VO2's Trends). Top to bottom: a 7 / 14
/ 30 days / Custom range (Custom is the saved visit date), a 2-column grid of
daily averages per button with one supporting figure, one card per chart
(title, a one-sentence takeaway, bars per day with a dashed average line;
diapers grouped, not stacked), then For the doctor (summary thumbnail row,
Share PDF, CSV row). Ranges never start before the first entry. Averages skip
today. The paywall preview reuses `ReportChart`.

Backfilling lives at the very bottom of Now as a quiet "Add an older entry"
menu (Feed, Pee, Poop, Sleep, Weight) that opens the same editor as History's
plus button; the editor's date picker does the rest. Added 2026-09-26 for
version 1.1, because parents install on day three and want the first days in.

2026-09-28 (Jack): Feed is one button. A tap logs a feed with no side;
then a "Side" row of Left / Right / Bottle chips opens
under it for 90 seconds and edits that feed (multi-select, stored in tap
order in the existing `side` string as `right,left`, so no schema change and
older builds still read single sides). The widget's Feed and the plain Siri
Feed log no side either; the Watch keeps its L / R / Bottle taps. A "Logging
at" row above the buttons winds the log time back (minus and plus step the
five-minute grid, the time opens a wheel); taps log at that time and it
returns to now 60 seconds after the last touch, with a countdown under the
buttons. The editor's time is an inline wheel (a compact picker's popover
covered Save); existing entries autosave with Done only, new entries still
need Log. Totals count from a day-start hour or the last 24 hours (Settings >
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
widget logs, that tile shows "Logged / Undo" (the Lock Screen circle a checkmark with Undo) for 10 seconds, then its normal face. `LogEventIntent` records the
entry in `WidgetUndo` (App Group); `UndoWidgetLogIntent` deletes exactly that
id and reopens any feed timer the log ended, accepting a tap up to 60 seconds
in case WidgetKit redraws late. Controls, the Action button and Siri have no
surface for it; History's swipe-to-delete covers them. A second tap of the same kind within 3 seconds (before the tile
could redraw) logs nothing, and a stale Undo never clears a newer tap's Undo.

Tap confirmation (2026-09-29, Jack: "see confirmed click so I know it
worked"). The confirmed face has a
checkmark: the one-button tile reads "Logged" with Undo, the Lock Screen
circle a checkmark over "Undo", and the four-button widget swaps the tapped
button for checkmark / Undo (same `WidgetUndo`, same 10 seconds, including Sleep and Wake). Controls
show "Logged feed" (or "is off in Settings") in the system overlay through
`ControlConfirmation`. Locked-phone logging: the Home Screen is never reachable
locked, so the answer is the Lock Screen circles, the four-button Lock Screen
row, and the corner controls; `LogEventIntent`, `UndoWidgetLogIntent` and the
Live Activity's `StopRunningIntent` are all `.alwaysAllowed`.

Widget audit (2026-09-29): Sleep and Wake also suppress duplicate taps and
support Undo. Undo is consumed after a successful save, so a failed save can
retry; app Undo clears the matching widget confirmation too. Widget intents
carry the displayed baby's id and refuse a stale tap after a baby switch.
Control confirmation uses a value provider and a persisted save result;
`isActive == false` alone cannot mean a save succeeded. A Live Activity Stop
carries its timer start so an old activity cannot end a newer timer. Apple
already defaults intents to `.alwaysAllowed`; adding the explicit declaration
does not prove locked-device behavior. Test that on a physical iPhone. The
rectangular Lock Screen log row shows Feed, Pee and Poop, or Sleep when it is
the only tracked kind; the Home Screen grid shows all tracked kinds.

Widget taps run in the widget extension (2026-09-30, Jack chose this over
instant partner sync: "like the headache app"). As `LiveActivityIntent`s they
ran in the app, and on a phone the app's background launch was slow enough that
WidgetKit redrew the tile before the save, then throttled the app's own reload,
so taps logged but Logged / Undo never showed. The simulator only reproduced it
with a 4 second delay in the app and the app's reloads removed.
`WidgetUITests.testPeeButtonConfirmsWhenAppIsNotRunning` checks the tile
confirms with the app never launched. Controls and Siri stay in the app.

Never put `.invalidatableContent()` (or a `contentShape`) on or inside a
widget `Button(intent:)` (2026-09-29, builds 28 and 29 shipped with it). On
the simulator the renderer then treats the tap as a plain widget tap: it opens
the app and the intent never runs. (Jack's phone still logged those taps, so the
device difference is unproven; the modifier stays out.) That applies to the
Home Screen tiles, the Lock Screen circles and row, and the Live Activity
Stop. `WidgetUITests` catches it on a re-signed simulator build.

Animate only meaningful feedback, using the shared spring and respecting
Reduce Motion. Keep text readable in dark mode and at accessibility sizes.
Use vertical layouts when the side-by-side version no longer fits.

Verification: LoggingUITests covers direct logging, optional feed sides, the
wound-back log time, editor autosave, the totals window, long-press cancellation,
backfilling yesterday without touching today's totals, Undo, sleep/wake, turning a button off, one-screen onboarding, and free access to the guides and report previews.
SharingTests protects the owner's log and separates invitation failures
from an intentional stop-sharing action. Real cross-account iCloud sync still
requires two signed-in devices and a deployed production schema.
