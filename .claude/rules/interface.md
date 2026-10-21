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
LazyVGrid inside a List cell crashed UICollectionView self-sizing. Both
layouts open with free Today and Yesterday tiles (tap scrolls to that day) and
a 14-day bar chart (`HistoryDays.swift`) that works like Total Calories': drag
and the header reads the day under the finger, release jumps to it. The chart
is Baby+; free users see their own bars blurred under a lock that opens the
paywall on Trends. Jumps scroll to an anchor just below the top (y 0.06), not
`.top`, which tucked the day header under the collapsing large title. The Undo
toast is pinned to the top (swipe up to dismiss), so it never lands mid-screen
over the log controls. First-weeks guidance, sharing and stain help live in
Settings. No onboarding paywall. Two exceptions to "nothing but logging on
Log" (2026-10-18, Jack approved): the one-time reminder offer sheet after a
feed, and a checkup note that opens the paywall focused on the pediatrician
summary. The offer stays out of UI tests (`ReminderOfferGate`: off with
`-NoCloudKit`, back with `-ShowReminderOffer`).

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

2026-10-04: the capsule floats in an overlay and each tab's root view,
inside its NavigationStack, reserves it with `reservesNavigationCapsule()`
(bottom safe-area padding). A safe-area inset on the TabView, or padding outside
the NavigationStack, does not reach the hosted List, so the last rows ended
under the capsule; clipping the whole TabView then hid everything behind it.
Clip only the top edge (`TopEdgeClip`), so lists end above the capsule yet
scroll on beneath it, and Now fits its own safe-area height. Any new pushed
screen must call `reservesNavigationCapsule()` too.

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
totals over each other. The hero time crossfades rather than using the
numeric roll, which smeared "just now".

Nothing moves (2026-10-20, Jack: a Feed tap should not move the other
buttons or parts of the flow). A tap changes what Now says, never a height.
After Feed, the side chips (with Done) crossfade into the "Logging at" row's
slot above the buttons, and the time row keeps the slot's height under them
(`FeedSidePrompt`, `FeedSideRow`); they used to grow the Feed card, which
shrank every button and could drop the hour strip on an iPhone 18 Pro. The
wound-back countdown sits beside "Now" in the time row instead of a line under
the buttons. On the fitted layout the status card's lines never wrap
(`oneLine`). `testLoggingMovesNothingElseOnTheScreen` pins every other
control's frame across a Feed tap, a side, Done and a wind-back.

Totals are a card: one figure per button with a kind dot, and the hour strip
uses the same dots. Name and birth date are optional; never guess a birth date
for someone who did not choose one.

One screen (2026-09-30, Jack: "dynamically fit on one screen without having
to scroll"). On a phone, Now measures itself (`NowFit`): everything but the
log buttons is a fixed height, and the buttons split what the screen leaves,
between `minLogButtonHeight` and `maxLogButtonHeight`; slack past the cap sits
above the totals. Sections sit 12 apart; the time row and the buttons, one
control, 8. There is no idle "Tap to log now" hint (Jack: not needed). When minimum
button heights need its space, the hour strip first sheds its hour labels
(`StripStyle.compact`; an 18 Pro at XL and XXL text) and only then drops; under
`hourStripMinHeight` (an SE) it drops. "Add an older entry" sits right under
the totals with no section gap, since its 44pt touch area holds its own. Accessibility sizes and iPad keep
the scrolling layouts.

Reports (2026-09-30, Jack: the old page "doesn't display things in an easy
to see or understand way"; modelled on VO2's Trends). Top to bottom: a 7 / 14
/ 30 days / Custom range (Custom is the saved visit date), a 2-column grid of
daily averages per button with one supporting figure, one card per chart
(title, a one-sentence takeaway, bars per day with a dashed average line;
diapers grouped, not stacked), then For the doctor (summary thumbnail row,
preview and share PDF, CSV row). Ranges never start before the first entry.
The paywall preview reuses `ReportChart`.

Partial days (2026-10-08, Jack: reports should show what doctors ask for and
leave partial days out). `SummaryReport.Day.partial` marks today, the day the
log began (first entry of any kind, so an afternoon install is not a day) and
a day with nothing logged; `completeDays` drives every average, falling back
to the logged days until the log has a complete one. `averagesNote` says what
was left out and is printed under the tiles and under the PDF stats; partial
rows carry an asterisk and lighter ink on the page, lighter bars on the
charts. Tiles and PDF stats carry the second number a doctor asks: longest
feed gap, bottle a day with the typical bottle, the lowest wet and dirty day,
longest sleep stretch, and the weight change in grams and percent since the
first weigh-in. Never grade any of them against a target (1.4.1).

2026-10-03: The Reports PDF action opens the complete preview first. Its toolbar
shares the PDF, matching the generate, review, then share flow in Vitals and VO2.

Backfilling lives at the very bottom of Now as a quiet "Add an older entry"
menu (Feed, Pee, Poop, Sleep, Weight) that opens the same editor as History's
plus button; the editor's date picker does the rest. Added 2026-09-26 for
version 1.1, because parents install on day three and want the first days in.

2026-09-28 (Jack): Feed is one button. A tap logs a feed with no side;
then a "Side" row of Left / Right / Bottle chips opens
above the buttons for 90 seconds (or until Done) and edits that feed (multi-select, stored in tap
order in the existing `side` string as `right,left`, so no schema change and
older builds still read single sides). The widget's Feed and the plain Siri
Feed log no side either; the Watch keeps its L / R / Bottle taps. A "Logging
at" row above the buttons winds the log time back (minus and plus step the
five-minute grid, the time opens a wheel); taps log at that time and it
returns to now 60 seconds after the last touch, with a countdown beside
"Now". The editor's time is an inline wheel (a compact picker's popover
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

Widget taps also upload straight to CloudKit (2026-10-17, Jack: Elsa's widget
taps never reached his phone until she opened the app). After the local save
the widget writes the same change with `CloudEventWriter` in the mirrored
`CD_LogEvent` layout, which every device's container imports like any other
export (Apple DTS's suggested route; extensions must not run their own
`NSPersistentCloudKitContainer`, TN3164). `WidgetCloudSync` queues and sends
it (short timeouts, so the confirmation waits at most a few seconds); the app
publishes each baby's zone and record and the running timers' record names to
the App Group, since the widget cannot ask a container. The app still exports
the local save later, so every device runs `DuplicateEvents` on reload: the
copy named after the entry's id wins, then the lowest record name. Undo deletes
the widget's record and leaves a three-day tombstone. `scripts/cloudkit-schema
--verify-direct-write` proves the layout, import, change, duplicate fold and
delete against Development.

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

Main thread (2026-10-19, Jack: build 49 was "super laggy and a pain to
load"). `NSPersistentCloudKitContainer.recordID(for:)` and `fetchShares`
wait on the mirroring queue, which is busy for seconds while a phone syncs:
never call them from `reload()` or a view body. `EventStore` looks record
names up on a background task, throttles remote-change reloads to one per
300 ms, and caches day tallies and day groups per reload, because History
renders on every change and each walk covers the whole log.

Freshness (2026-10-20, Jack: "the data gets stale on the device and doesn't
sync over"). `--audit-events` (read-only, Production) showed CloudKit healthy:
601 entries, no duplicate ids, both phones' taps uploaded within seconds. The
lag was on the receiving side. Three fixes: `SharingService.refresh` ran
`fetchShares` on the main thread on every foreground, the moment the mirror
imports, so the app froze on old data; it now runs detached and the newest
refresh wins. The widget saves from its own process and nothing merged those
saves into the app's view context, so rows on screen kept old values (a sleep
the widget ended kept running) until relaunch; `Persistence.mergeExternalChanges`
merges other authors' history on every reload (`SyncFreshnessTests`). Every
finished CloudKit import now also reloads, and Settings > Log together says
when the phone last synced, or names a fixable cause (iCloud full, signed
out). Core Data schedules imports as discretionary work, so a partner's entry
can still take a moment; there is no public way to force one.

Audit follow-ups (2026-10-20). Sync status lives in `CloudSyncState`, its own
object watched only by Settings' line, because a catching-up phone posts
dozens of CloudKit events and each `@Published` write on `EventStore` redrew
Now. Only an export clears "iCloud full" (downloads go on while uploads
cannot), and a phone with no account shows "signed out" from Core Data's
setup error 134400. A reload that lands while duplicate cleanup runs queues
one more pass. "Start on" says nothing when the newest breastfeed has no side
yet, rather than guess from an older one. After Feed with the time wound back,
the side row shows that time in the wound-back outline, since it covers the
time row and the next tap still logs then.
`Reminders.reschedule` skips the notification center when the plan is
unchanged.

Two-partner pass (2026-10-20, Jack: "a little laggy and glitchy"). Each tap
was followed by two to four more full reloads, one per remote-change notice
for its own save and export, and each redrew every screen and reloaded the
widgets and the Watch. Remote-change reloads are now `refresh(force: false)`:
they refetch, and redraw only when the log, the babies, the summary or an
entry in the view context changed (`NSManagedObjectContextObjectsDidChange`);
widgets and the Watch reload only when the summary's content changed. A
widget tap's two CloudKit copies show as one (`EventStore.shown`) until the
cleanup deletes one, so the partner's totals never count it twice, and
deleting the shown copy deletes its twin. The history token moves past
CloudKit's imports, which the filter skips, so each reload no longer rescans
them. The widgets no longer say "Start on"; Home and the feed reminder do.

Two phones on simulators (2026-10-21, Jack: "can you sim test two phones?").
Pool simulators have no Apple ID and agents may not sign one in, so
`SimPartnerRelay` (DEBUG, `-SimRelay <folder> <name>`) stands in for iCloud:
each phone writes its saves from persistent history to a folder on the Mac,
and imports the partner's as a background save under the mirroring author,
so the receiving path is the app's own. `scripts/two-phone-sim.sh` builds and
launches both; each phone logs what it sent, received and redrew.
`TwoPhoneTests` runs the same relay in-process. First run: every change
crossed in the 2 s delay plus about 0.35 s (the remote-change throttle), each
change redrew each phone once, both phones always agreed, the side row stayed
open while a partner's entry landed, and a phone reopened after four partner
taps showed them in one redraw. Apple's own delivery (push and discretionary
import) is the part this cannot measure.

Never put a `graphicBorder` card in an inset-grouped List row: the row clips
to the section's larger corner radius and shaves the outline off the card's
outer corners. History's Today/Yesterday tiles and day chart live in a
section header for that reason (2026-10-19). `GraphicBorder` draws outline
and shadow as one path (`CardEdge`) over the card; a stroke over a
continuous-corner fill is not concentric and left light seams.

Persona pass (2026-10-21, four reviews: bottle and mixed feeding, night
shift, second parent, first-time parent). The editor keeps a saved length to
the second unless Length itself changes (it used to round every edited
feed's end to whole minutes), clears the amount when Bottle is deselected,
and starts a new bottle at the last bottle's amount. A Wake with the time
wound back past the sleep's start ends the sleep now instead of at zero
length. A participant's invite screen leaves out the joined list (their copy
of the share does not list the others), and a joined person with no name
shows as "Someone". Settings says "Join a shared log", the words the invite
code uses. First Weeks shows a dash, not zeros, for days before the first
entry. Night light `ink3` was lifted to 4.5:1 on cards. Left for Jack:
the totals default, the side row, wind-back and Undo timings, and units.

Second persona pass (2026-10-21: grandparent helper, twins, doctor visit
with Baby+, VoiceOver at 3am). Joining: onboarding's `JoinLogModel` lives in
`RootView`, because accepting swaps onboarding out, and a failed paste used
to come back to a blank start screen; it now returns to Join with its
message. "Start my own log instead" keeps the zone as `lateSharedZone`, so
the baby still opens when it arrives, with the offer to bring in what was
logged meanwhile; that offer moves a log only when exactly one other log
exists (twins are never folded together). The waiting screen and the
reminder offer scroll at large text. The scanner says when the camera is off
or the code is not an invite. `SharingService` clears the last baby's share
on a switch, so Log together never shows (or reopens) another baby's invite.
A new sleep from the editor cannot be logged at zero length. Reports: a
day's weight is its last weigh-in, two equal weigh-ins read "No change
since", the PDF moves the key and notes to a new page instead of the footer,
and a day with nothing logged prints dots, not zeros. The paywall's loading
and failure states carry the billing disclosure (3.1.2), loading shows from
the first moment, and a purchase clears the last error. VoiceOver: each log,
Undo and wind-back is announced, Undo stays four times longer while
VoiceOver runs, Sleep reads how long the baby has slept, the hour strip
reads spans ("9 PM to 1 AM") or "Nothing logged yet", and the Dynamic
Island icons are labelled. Left alone: the 10pt tab capsule labels (fixed
for the one-screen fit), the Watch's 38pt Sleep row, a baby name on widget
faces, per-baby reminders, and deleting a baby.

Third persona pass (2026-10-21: Watch and widget dad, formula family in
Night light, preemie backfill, App Reviewer on a fresh install). CSV dates
and the PDF file name are local days (they were UTC, so evening entries
moved to the next day). Sleep tallies stop at now, so a sleep entered to end
later never counts ahead. New History entries from a past calendar day open
on that day, and the calendar follows midnight; the sleep stepper moves 15
minutes; a whole sleep added from the editor toasts "Logged sleep". First
Weeks past day 14 says the table is for looking back, and its column reads
REFERENCE. Birth dates are stored at noon so a time zone never moves them.
The stain helper's first setup stays open until Save (each tap used to end
it). The paywall opens without a stale error, its spinner uses `buttonInk`,
and lifetime owners see "Lifetime, never renews" instead of Manage
subscription. Checkup notes no longer say a summary is ready, because a free
parent's tap lands on the paywall. A declined notification prompt still
saves the reminder choice, so Settings shows the way to allow them, and
Settings refreshes after the offer. Widget entries clear today's counts at
the day start (`summary.current(now:)`, as the Watch does). The Watch no
longer offers a double-tap side when the last feed had none, and a
backdated Wake before the sleep began ends it now. The phone retries the
Live Activity on every foreground (iOS refuses a background start), and
never pushes the empty pre-unlock stand-in to the Watch. Night light dims
the full PDF preview. Settings' By day keeps the chosen day start after
trying Last 24 hours. Left for Jack: partial bottle amounts in reports,
per-kind widget Undo, a Watch "updated" line, and the widget's reach to this
phone's own Watch.

Feed row (Jack, 2026-10-21). The side chips open inside the Feed button's
own frame (a hidden Feed keeps the size), so the log time row never hides
and nothing else moves (`testLoggingMovesNothingElseOnTheScreen` pins the
side row to Feed's frame). A narrow All (`allButtonWidth`) beside Feed logs
a feed, a pee and a poop at the log time in one save (`EventStore.logAll`);
one Undo takes all three back (`LoggedEvent.alsoLogged`). All shows only
while Feed, Pee and Poop are all on. Settings > Feed types (`FeedTypes`,
App Group `hiddenFeedTypes`, at least one stays on) limits the chips, the
editor and the Watch to breast, bottle or both; bottle alone makes every
bare Feed (app, widget, Siri) a bottle with no chips, and drops "Start on".
The Undo toast uses the margins on Log, which has no bar buttons, and
insets past them on every other tab.

Fit drift (build 61, Jack's phone with Sleep off): a fitted line that may
shrink to fit (`minimumScaleFactor`) re-measured shorter after a tap's
number animation, so the totals row lost 7pt and the whole screen refit.
Every fitted line now sits inside a hidden full-size "0" that holds its
height (`oneLine(_:font:)`, the totals' counts), and the diaper glyph has no
height of its own. `testTapsMoveNothingWithSleepOff` pins it.
