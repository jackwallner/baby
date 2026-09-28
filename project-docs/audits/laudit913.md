# Baby Tracker UX audit, laudit913

Date: 2026-09-13

Audit target: a parent in the first days or weeks with a newborn, often
sleep-deprived, interrupted, holding the baby, working one-handed, and opening
the app at 3am to answer one question quickly: when was the last feed, which
side, and what happened since?

Scope: visual consistency, first launch, onboarding, first log, repeated rapid
logs, timers, undo, edit, delete, history, First Weeks, pediatrician summary,
sharing, background and foreground return, widgets, Watch, App Intents, Live
Activity, Dynamic Type, themes, and performance risks as the log grows.

This is a documentation-only audit. No product or source code was changed.

## Executive verdict

The core product direction is strong. Setup is direct, neither a name nor a
birth date is required, the Now screen answers the central question, the four
home actions stay stable, and the everyday surface is free of ads, AI,
predictions, and purchase interruption.

The most important problems are trust and recovery, not decoration:

1. A newer one-tap feed can coexist with an older running timed feed, allowing
   Now, History, and outside-app surfaces to disagree about the current feed.
2. Delete is immediately destructive even though the rest of the logging flow
   teaches the parent to expect Undo.
3. Store startup and first CloudKit sharing have no complete, recoverable
   loading and failure experience.
4. The checked-in App Store and Watch screenshots are from an older visual
   system than the current checkout.
5. Accessibility support proves eventual reachability, but not the one-glance
   answer the product promises on a compact phone.

The current build is not ready to be described as operating perfectly across
all supported states. The normal local logging path is healthy, but the
degraded, cross-process, large-history, and accessibility states below need
explicit acceptance or follow-up validation.

## Priority and evidence rules

Severity:

- P1: undermines recorded truth, can lose a useful record, can block first use,
  or creates a release-facing expectation mismatch.
- P2: material user experience, accessibility, synchronization, or performance
  risk that should be validated in the next focused pass.
- P3: polish, conditional overflow, or verification debt that is still worth
  addressing before the surface is presented as finished.

Evidence labels:

- Confirmed: follows directly from current source or was reproduced on the
  current simulator build.
- Observed mismatch: visible in checked-in captures or a current runtime
  inspection, with the cause or production frequency not yet proven.
- Structural risk: the expensive or incomplete path is present in source, but
  visible impact needs a trace or device scenario.
- Validation risk: the source leaves a plausible failure path and the current
  test suite does not cover it. It is not reported as a present defect.

## Audit baseline

### Repository and release evidence

- Current checkout: `77459d5`.
- Current project build setting: `CURRENT_PROJECT_VERSION: 12` in
  `project.yml`.
- The checked-in iPhone capture report says source commit `66bf714`, iPhone 17
  Pro, iOS 26.5, and six capture flows in
  `app-store/capture/capture-report.json:1-127`.
- The checked-in Watch capture report also says source commit `66bf714` and
  Apple Watch Series 11 46mm in `app-store/capture/watch-capture-report.json`.
- The current source uses bold outlined care graphics and physical card edges
  in `Baby/Views/LogButtons.swift:36-80` and
  `Baby/Views/Components.swift:18-32`. The checked-in captures use the older,
  softer controls. The capture set should therefore be treated as stale visual
  evidence, not current-checkout proof.

### Runtime and test evidence collected

- Full `xcodebuild test` on iPhone 17 Pro, iOS 26.5: 65 passed, 0 failed.
- Full `xcodebuild test` on iPhone 17e, iOS 26.5: 65 passed, 0 failed.
- Current runtime inspection on iPhone 17 Pro and iPhone 17e covered the Now
  screen in Light, Dark, Night light, System, normal text, seeded data, and
  Accessibility XXXL.
- On iPhone 17e at normal text, all feed zones, Wet, Dirty, Sleep, and Today
  were visible in the first viewport.
- On iPhone 17e at Accessibility XXXL, the status card consumed almost the
  entire first viewport. The first logging card was only partly visible, and
  two upward swipes were needed to reach Dirty, Sleep, and Today. The existing
  test passed because it deliberately scrolls until each control is hittable.
- Current Watch Series 11 46mm runtime inspection found six button targets and
  one scroll view. The Watch launched with the fallback name `Baby` while the
  paired phone showed `Nora`; this was reproduced in the simulator configuration
  and still needs physical WatchConnectivity validation before calling it a
  production sync defect.
- A current iPhone 17 Pro Max screenshot launched successfully, but its
  semantic snapshot hit an XcodeBuildMCP translation error. No semantic pass is
  claimed for that device.
- `python3 scripts/design-audit.py` reported 0 drifted files and 2 advisories,
  both `.buttonStyle(.plain)` uses in the widget and Watch.
- All four app and extension property lists passed `plutil -lint`.
- Existing simulator and Xcode warnings about build-number compatibility,
  duplicated WebKit accessibility classes, and snapshot settling were not
  treated as application failures.

The passing tests establish a good happy path. They do not establish cold
launch recovery, iCloud failure recovery, physical Watch delivery, VoiceOver
reading order, pseudo-localization, 40mm or 41mm Watch layout, large-history
performance, or cross-surface consistency after stale state.

## P1 findings

### P1-01. A one-tap feed can leave an older timed feed active

Status: Confirmed source behavior.

Scenario: One parent starts a timed Left feed. During a handoff, the other
parent taps Right or Bottle to record a completed feed. The newer event is
saved, but the older timed feed remains open.

Evidence:

- The one-tap path in `Baby/Views/LogButtons.swift:40-65` calls
  `events.log(.feed, side: side)`.
- `Shared/Services/EventStore.swift:197-215` inserts the completed event and
  does not close a running feed.
- `Shared/Services/EventStore.swift:218-241` closes an existing running event
  only in the `startTimed` path.
- `Shared/Services/NowSummary.swift:81-89` records the running feed while
  scanning events, and `:111-115` only lets it replace the completed feed when
  its start is later.

User impact: History can contain the newer feed while the large Now card still
says `Feeding` for the older one. The parent can choose the next breast or
decide whether feeding is ongoing from the wrong event. The same disagreement
can propagate to the widget, Watch, and Live Activity.

Required validation: start a timed feed at `T0`, log a one-tap Right and then a
Bottle at `T1`, and compare Now, History, widget, Watch, and Live Activity
state. Define the intended behavior for closing the old timer, showing the new
instant event, and Undoing the combined operation. Repeat with two parents.

### P1-02. Delete is immediately destructive and bypasses Undo

Status: Confirmed.

Scenario: A parent swipes while trying to scroll, or opens an event to correct
the time and taps Delete while interrupted.

Evidence:

- `Baby/Views/HistoryView.swift:57-70` calls `events.delete(event)` directly
  from a destructive swipe action.
- `Baby/Views/EventEditorView.swift:84-95` calls the same delete operation and
  dismisses after success.
- `Shared/Services/EventStore.swift:267-277` deletes and reloads without
  `rememberForUndo`. It clears `lastLogged` if the deleted event was the last
  in-app action, so the existing toast cannot restore it.

User impact: A useful feed, diaper, or sleep record can disappear permanently.
This conflicts with the interaction lesson established by every primary tap,
where an accidental action is expected to be reversible for a short period.

Required validation: delete a recent feed, wet diaper, dirty diaper, completed
sleep, and running sleep from both History and the editor. Require either a
time-bounded Undo that restores the same object and running state, or an
unmistakable confirmation that makes accidental deletion difficult. Repeat for
a shared baby and for a delete made by the other parent.

### P1-03. Store startup has no recoverable loading or failure experience

Status: Missing recovery state confirmed. Failure frequency and visible launch
impact are unmeasured.

Scenario: First launch, app update, local migration, damaged SQLite data, slow
CloudKit-backed store setup, or temporary infrastructure failure.

Evidence:

- `Baby/App.swift:9-12` constructs the persistence and event services before
  the root view is rendered.
- `Shared/Services/Persistence.swift:40-80` configures both stores and calls
  `loadPersistentStores`. It logs a load error and can call `fatalError` if the
  coordinator cannot return both stores.
- `Baby/App.swift:80-87` starts the store service in a task, but there is no
  persistence phase exposed to the UI.
- `Baby/App.swift:158-175` branches between paywall, joining, onboarding, and
  home, with no store-loading or retry branch.

User impact: A parent has no way to tell whether the log is still loading, is
safe but offline, or has failed. A first-use crash or unusable launch is
especially damaging when the app's value is immediate recording.

Required validation: cold launch on the shortest supported phone with network
disabled, iCloud unavailable, a delayed store load, and an unreadable store.
Measure time to first hittable logging control, confirm that local entries are
preserved, keep the process alive, and provide a retry path that does not hide
the last usable local state.

### P1-04. Release screenshots promise an older product than the current build

Status: Observed mismatch.

Evidence:

- `app-store/capture/capture-report.json:119-127` identifies commit `66bf714`,
  while the current checkout is `77459d5`.
- The current Now controls use `CareGraphic`, strong outlines, and the shared
  physical card edge in `Baby/Views/LogButtons.swift:36-80` and
  `Baby/Views/Components.swift:18-32`.
- The checked-in `01_now.png`, `05_history.png`, and `06_sleep.png` show the
  older visual treatment. The Watch report has the same old source commit.

User impact: A reviewer or customer may see a materially different hierarchy,
graphic vocabulary, and card weight in the store than after installation. This
is a trust and release-readiness issue even if the current runtime is better.

Required validation: recapture all six iPhone flows and the Watch flow from the
current checkout. Record source commit, build, device, OS, appearance, text
size, and state in the capture report. Review the actual upload set, not only
the raw simulator files.

## P2 findings, trust and recovery

### P2-01. Outside-app timer actions can miss a running event after 50 newer rows

Status: Confirmed source behavior.

Evidence:

- Feed and sleep App Intents query `persistence.events(..., limit: 50)` in
  `Shared/Utilities/AppIntents.swift:40-78`.
- The Live Activity Stop intent also searches the newest 50 events in
  `Shared/Utilities/AppIntents.swift:143-161`.
- The app's main `EventStore` path reads the full event list in
  `Shared/Services/EventStore.swift:66-80`.

User impact: With enough newer entries from either parent, an older running
feed or sleep event can fall outside the bounded query. A widget, Siri action,
Shortcuts action, or Live Activity stop can appear to succeed while changing
nothing, or can start a new timer instead of ending the old one.

Required validation: leave a feed and a sleep timer running, create at least 75
newer events, then invoke each supported outside-app action. Compare the
resulting event list, Now, widget, Watch, and Live Activity state.

### P2-02. The widget can display one feed side and save another

Status: Confirmed source risk, with a specific stale-timeline scenario.

Evidence:

- The widget label is built from the timeline summary's
  `s.suggestedSide` in `BabyWidget/BabyWidget.swift:181-190`.
- The intent recalculates the suggested side from current storage in
  `Shared/Utilities/AppIntents.swift:40-48`.
- The widget's feed button exposes only the generic `.feed` choice, not
  explicit Left, Right, or Bottle choices, in
  `BabyWidget/BabyWidget.swift:194-210`.

User impact: A partner's intervening feed can make the widget say `Feed L`
while the tap records Right. A bottle is also forced through a breast-side
suggestion, and entering bottle amount or other details requires opening the
app. This is precisely the kind of correction work the parent is trying to
avoid in a dark room.

Required validation: generate a widget timeline, change the last feed on a
second device, then tap the stale widget. Test systemSmall, systemMedium,
accessory rectangular, and the available lock-screen families with last-side
states Left, Right, and Bottle.

### P2-03. Widget identity is cached while the intent resolves the active baby

Status: Validation risk.

Evidence:

- Widget entries cache a `NowSummary` in `BabyWidget/BabyWidget.swift:35-52`.
- The App Intent resolves `activeChild` again at execution time in
  `Shared/Utilities/AppIntents.swift:31-48`.
- A Watch payload carries a child ID, but the Watch UI only has the cached
  summary and no baby selector in `Shared/Services/WatchStore.swift:35-43`
  and `BabyWatch/Views/WatchNowView.swift:13-59`.

User impact: After a profile switch, a stale widget or Watch can look like it
belongs to Baby A while the tap is written to Baby B. For a Baby+ household
with more than one baby, the Watch has no local confirmation or selector to
resolve that ambiguity.

Required validation: create two profiles with different names and sharing
states, switch rapidly on the phone, let widget and Watch summaries go stale,
then log before and after reconnecting. Require the displayed name, payload
child ID, and final History destination to agree.

### P2-04. Watch conflicts can be acknowledged as successful no-ops

Status: Confirmed source behavior.

Evidence:

- `Shared/Services/EventStore.swift:362-387` ignores a Watch start-sleep action
  when sleep is already running and ignores a stop-sleep action when no
  matching sleep exists, but still records the payload as applied.
- `Shared/Services/WatchStore.swift:64-89` removes pending actions after the
  phone acknowledges them and presents a short `lastAction` message.

User impact: The Watch can say `Sleep started` or `Sleep ended` when the phone's
History did not change. The parent loses the pending retry opportunity and may
assume the sleep state is trustworthy.

Required validation: create conflicting phone and Watch states for Start and
Wake, including simultaneous parent actions and stale summaries. Require the
acknowledgement to describe a no-op or preserve a retry route.

### P2-05. Undo is a single-slot, eight-second recovery mechanism

Status: Confirmed.

Evidence:

- `Shared/Services/EventStore.swift:45-46` sets an eight-second undo window.
- `Shared/Services/EventStore.swift:291-299` stores only one `lastLogged` value
  and cancels the previous expiry task for each new action.
- `Baby/Views/NowView.swift:59-67` presents one toast.
- Stopping a timed feed or sleep sets `reopensTimer: true`, but starting a new
  timed event can also close an old running event in
  `Shared/Services/EventStore.swift:218-241`. Undo only removes the new event
  in `:307-313`; it does not restore the old event's running state.

User impact: Feed, Wet, then another Feed can replace the correction target
before the parent notices. Undoing an accidental new timed feed can leave the
previous timer stopped, even though the parent expected the prior state back.

Required validation: log two to four actions inside eight seconds, wait through
expiry, background and return, and test Undo after starting a replacement
timed feed. Confirm the toast's target and the restored timer state.

### P2-06. Return from background can briefly show a stale elapsed time

Status: Missing activation update confirmed. Visible delay is unmeasured.

Evidence:

- `Baby/Views/NowView.swift:14` defines a 30-second timer.
- `Baby/Views/NowView.swift:79-85` updates `now` from the timer and event-count
  changes, not from scene activation.
- `Baby/App.swift:89-93` reloads events on activation but does not update
  `NowView`'s local clock.

User impact: A parent who returns after a long nap can read a stale `2h 13m
ago` value until the next timer delivery or another event. The central answer
should be trustworthy immediately on return.

Required validation: log a feed, background for 1, 10, and 60 minutes, then
foreground and inspect the card immediately by screenshot and accessibility.
Repeat with a running sleep and a remote event arriving while suspended.

### P2-07. Sharing can look absent or remain indeterminate during normal failure

Status: Structural and validation risk.

Evidence:

- `SharingService.waitForFirstExport` waits only 20 seconds in
  `Shared/Services/SharingService.swift:54-80`.
- The project CloudKit documentation describes first-store setup taking about
  two minutes in `scripts/cloudkit-schema/README.md:59-69`.
- `SharingService.refresh` sets `share = nil` after a failed share fetch and
  performs no retry in `Shared/Services/SharingService.swift:39-51`.
- App foreground and child changes launch async refreshes without cancellation
  or identity checking in `Baby/App.swift:89-100`.
- After an invitation is accepted, `Baby/Views/JoinViews.swift:208-254` shows a
  progress state and eventually offers only `Start my own log instead`.

User impact: The first invite can fail during a normal first-store setup delay.
A transient outage can make an existing shared log look like an unshared log,
and rapid profile switching can temporarily show the wrong participant or
invite state. The joining parent has no clear retry or last-known state.

Required validation: fresh install, create a baby, invite immediately, throttle
the first export beyond 20 seconds, interrupt connectivity during foreground
return, and switch profiles while responses are delayed. Require a preserved
last-known share state, clear stale labeling, and retry without duplicating a
baby or log.

### P2-08. Shared History does not tell parents who logged an entry

Status: Confirmed UI and model gap.

Evidence:

- `Shared/Models/BabyModel.swift:194-207` has event kind, time, side, amount,
  stool, note, and child, but no caregiver field.
- `Baby/Views/HistoryView.swift:98-121` renders kind, detail, note, and time,
  with no author or source label.
- Persistent-history code can detect a `someone-else` transaction, but that
  is not surfaced as event-level attribution.

User impact: When two parents disagree about whether a feed happened, the
history cannot answer who recorded it. That creates duplicate logging and
uncertainty during handoffs.

Required validation: log simultaneous events from two devices, edit one event
from each device, and review the shared History. Evaluate whether a subtle
`You` or partner label reduces confusion enough to justify the identity and
CloudKit complexity. Do not assume a new model field is the only solution.

## P2 findings, layout and accessibility

### P2-09. Accessibility preserves reachability but not one-glance behavior

Status: Confirmed current runtime observation.

Evidence:

- `Baby/Views/NowView.swift:20-42` uses a vertical compact layout with an
  88-point minimum logging height and reserves 360 points for the home summary
  through `AppTheme.homeSummaryAllowance`.
- `BabyUITests/LayoutUITests.swift:21-40` reveals each control with repeated
  swipes before asserting `isHittable`.
- Current iPhone 17e Accessibility XXXL inspection showed the status card
  filling the first viewport; two upward swipes were required to reach the
  lower actions and Today totals.

User impact: A parent using very large text can reach the controls, but cannot
see the answer and the logging surface at a glance. Sleep and Undo are the
actions most likely to require an extra swipe at the worst moment.

Required validation: use the shortest supported phone in portrait with normal,
XXL, and AX XXXL text, a running timer, and the Undo toast. Record first
viewport content and a scroll budget separately from eventual reachability.

### P2-10. The adaptive wide layout is outside the declared device contract

Status: Confirmed configuration mismatch, layout impact unmeasured.

Evidence:

- `Baby/Views/NowView.swift:20-26` has a 700-point wide layout branch.
- `Baby/Info.plist:37-40` declares portrait-only support.
- `project.yml:121-128` declares `TARGETED_DEVICE_FAMILY: "1"`, iPhone only.

User impact: Large phones never receive the wide arrangement, and the only
wide branch is not part of the declared device matrix. A future iPad or split
view decision could ship an untested layout accidentally.

Required validation: explicitly decide whether iPad and landscape are out of
scope. If they remain out of scope, remove the branch from release expectations
and keep it covered as dead code. If they become supported, test iPad,
landscape, split view, sheet presentation, and large text before enabling it.

### P2-11. History hides notes the editor allows the parent to enter

Status: Confirmed information loss.

Evidence:

- `Baby/Views/EventEditorView.swift:80-83` accepts a one-to-three-line note.
- `Baby/Views/HistoryView.swift:104-114` renders the note with `lineLimit(1)`.

User impact: A parent can record feeding context or timing details, then lose
that context in the primary review surface. The pediatrician summary and
history are the places where details are most useful later.

Required validation: save a long note, then inspect History at default, XXL,
and AX XXXL text. Check both visible truncation and the complete VoiceOver
announcement.

### P2-12. First Weeks urgent guidance is below a long reference table

Status: Confirmed layout, not a medical-content judgment.

Evidence:

- `Baby/Views/FirstWeeksView.swift:11-40` renders intro, table, and call card
  in one vertical scroll.
- The table spans 14 days in `Baby/Views/FirstWeeksView.swift:75-94`.
- `Call your pediatrician if` begins only at
  `Baby/Views/FirstWeeksView.swift:168-190`.

User impact: A tired parent looking for when to call must scroll past the full
reference table and may not realize that the decision guidance exists below
it. The current checked-in first-weeks capture also does not show the call
card in its first viewport.

Required validation: capture the first viewport and first-scroll position on a
compact phone, large phone, and AX XXXL. Verify VoiceOver reaches the call
card predictably. Preserve the existing calm, age-qualified, sourced,
non-diagnostic framing.

### P2-13. Summary construction can block before PDF work leaves the main actor

Status: Structural risk; runtime delay is unmeasured.

Evidence:

- `Baby/Views/SummaryView.swift:76-99` computes `report` synchronously before
  starting detached PDF rendering.
- `Shared/Services/SummaryReport.swift:96-125` repeatedly filters the event
  list for each report day.

User impact: Opening Summary or changing its date range can delay the first
interaction. This is particularly visible after months of logging, when a
parent is preparing for a visit and expects the report preview to appear.

Required validation: seed 90-day and 365-day histories, open Summary, change
the range repeatedly, and record main-thread duration, first interaction, and
preview latency.

### P2-14. Full-history reloads can hitch during a tap or partner sync

Status: Structural risk; frame impact is unmeasured.

Evidence:

- `Shared/Services/EventStore.swift:15-23` places the event store on the main
  actor and publishes the full event array.
- `Shared/Services/EventStore.swift:66-87` fetches all events, rebuilds the
  summary, reloads all widget timelines, pushes Watch state, and syncs the
  Live Activity on each reload.
- `Shared/Services/Persistence.swift:129-135` has no fetch limit for the main
  history.
- `Shared/Services/NowSummary.swift:71-80` sorts the list again, and
  `EventStore.swift:96-104` rebuilds day groups from the full list.

User impact: A delayed tap can make a parent tap twice or wonder whether the
entry saved. A newborn log may be about 25 rows per day, but that is not a
lifetime bound. Months of use, multiple babies, and remote-change bursts
change the cost profile.

Required validation: seed 500, 2,000, and 10,000 events. Measure cold launch,
tap-to-confirmation, History scrolling, Summary opening, memory, frame pacing,
and a burst of 10 to 50 remote changes while the parent is scrolling.

## P2 findings, Watch and cross-process consistency

### P2-15. The Watch can fall back to `Baby` and has no local identity proof

Status: Observed current simulator mismatch; production sync cause is a
validation risk.

Evidence:

- `Shared/Services/NowSummary.swift:7-10` defaults the name to `Baby`.
- `Shared/Services/WatchStore.swift:23-30` initializes from the cached summary.
- `BabyWatch/Views/WatchNowView.swift:58` uses the cached name as the title.
- `BabyWatchWidget/WatchComplication.swift:21-23` also reads the cached
  summary directly.
- The checked-in Watch capture visibly says `Baby` while the phone capture
  says `Nora`, and a current paired-simulator inspection showed the same
  startup fallback after the phone was named.

User impact: A parent can distrust the Watch state or log without knowing
which baby is selected. This is more serious for the Baby+ multiple-baby case.

Required validation: name the baby on the phone, launch both targets online,
then test offline Watch launch, shared baby, relaunch, profile changes, and
physical WatchConnectivity delivery. Do not call this a production sync bug
until that test is complete.

### P2-16. Watch offline queue has no age or size bound

Status: Confirmed source behavior; practical failure threshold unmeasured.

Evidence:

- `Shared/Services/WatchStore.swift:64-89` appends every pending payload,
  persists the full array, replays it, and retries it on activation.
- There is no expiry or maximum queue size in the payload handling in
  `Shared/Models/BabyModel.swift:319-329` and `WatchStore.swift:64-89`.

User impact: Prolonged disconnection or a force-quit phone can leave old taps
waiting indefinitely. Reconnection may apply a large burst, and the parent
cannot tell a recent pending tap from an old one.

Required validation: disconnect the Watch, log 100 events across several
hours, restart both devices, reconnect, and verify order, deduplication,
memory, and an understandable pending state.

### P2-17. Widget and Watch timelines can be up to five minutes behind the app

Status: Confirmed cadence difference; user impact is a validation risk.

Evidence:

- iOS widgets create 12 entries five minutes apart in
  `BabyWidget/BabyWidget.swift:35-43`.
- The Watch complication does the same in
  `BabyWatchWidget/WatchComplication.swift:25-29`.
- The Watch app and Now screen refresh their local clocks every 30 seconds in
  `BabyWatch/Views/WatchNowView.swift:8-10` and `Baby/Views/NowView.swift:14`.

User impact: The same feed can show different elapsed times on the phone,
Watch, and complication. Five minutes is usually tolerable for a history
glance, but not if the parent is deciding whether a timer is still active.

Required validation: inspect all surfaces 1, 2, 4, and 5 minutes after a feed
and while a sleep timer runs. Decide the acceptable staleness for each surface
and make the copy honest where exact freshness is impossible.

### P2-18. Live Activity cannot represent every active state consistently

Status: Confirmed source conditions; frequency is a validation risk.

Evidence:

- `Shared/Services/LiveActivityService.swift:30-35` gives a running sleep
  precedence over a running feed, while `NowSummary` tracks both.
- Existing activities are matched only by kind and start time in
  `Shared/Services/LiveActivityService.swift:45-60`, so a changed baby name or
  running-feed side may not update the displayed attributes.
- The Stop button is guarded by iOS 17.2 in
  `BabyWidget/BabyLiveActivity.swift:70-80`, while `project.yml:15-16` supports
  iOS 17.0.

User impact: Lock Screen state can omit an active feed, retain old identity
copy, or lack a stop action on iOS 17.0 and 17.1. A parent may have to open the
app to correct a timer that the surface implied was controllable.

Required validation: test simultaneous feed and sleep timers, edit the baby
name and running side while active, and run Lock Screen and Dynamic Island on
iOS 17.0, 17.1, and current iOS. Verify the displayed action and identity.

## P3 visual consistency and accessibility debt

### P3-01. History and Event Editor use a system-list visual language

Status: Confirmed source drift and current visual difference.

Evidence:

- Shared home cards use `graphicBorder`, theme-aware edge treatment, and the
  light-theme offset shadow in `Baby/Views/Components.swift:18-32`.
- `Baby/Views/HistoryView.swift:57-80` uses native `.insetGrouped` rows with
  list backgrounds.
- `Baby/Views/EventEditorView.swift:39-102` uses a system `Form`.
- Current History runtime shows a softer grouped list than the bold outlined
  Now cards.

User impact: The primary logbook and its edit surface feel like separate
products. The difference is not inherently wrong, but it weakens recognition
when the parent moves between the most important screens, particularly in
Dark and Night light.

Required validation: compare Now, History, and Editor in Light, Dark, Night
light, default text, and AX XXXL. Check edge contrast, hit targets, scrolling,
and whether a consistent treatment can be achieved without decorating Now.

### P3-02. Summary has bespoke controls that do not use shared button treatment

Status: Confirmed source drift.

Evidence:

- `Baby/Views/SummaryView.swift:103-122` uses `.buttonStyle(.bordered)` for
  `Today was the visit`.
- `Baby/Views/SummaryView.swift:124-155` uses a one-pixel custom preview
  overlay rather than the shared `graphicBorder` treatment.
- The shared styles live in `Baby/Views/Components.swift:61-95`.

User impact: The date-setting action and report preview are important in a
doctor visit workflow, but they have weaker hierarchy and feedback than the
primary actions elsewhere.

Required validation: capture Summary with example data and real data in all
three appearances, at default and AX XXXL text, and compare the action state,
preview edge, and full-preview sheet.

### P3-03. Visual theme coverage can silently be System only

Status: Confirmed test-harness inconsistency.

Evidence:

- `BabyUITests/VisualTourUITests.swift:3-9` documents
  `TEST_RUNNER_BABY_APPEARANCE` but reads `BABY_APPEARANCE`.
- The test passes that value to `-Appearance` in
  `BabyUITests/VisualTourUITests.swift:18-22`.
- No repository script sets either environment variable, so an ordinary test
  run defaults to System.

User impact: A green visual tour can provide no evidence for Light, Dark, or
Night light. A Night light regression can reach release without an attached
failure.

Required validation: run explicit Light, Dark, and Night light tours, inspect
the actual pixel palette, and include appearance in every attachment name and
capture record. The current source-level theme audit passing is not enough.

### P3-04. Paywall legal links are forced into one horizontal row

Status: Confirmed layout choice; overflow is a validation risk.

Evidence: `Baby/Views/PaywallView.swift:314-340` puts Terms of Use, a dot, and
  Privacy Policy in one `HStack`.

User impact: Longer translations, larger accessibility text, or a compact
phone can cause the purchase disclosure links to compress or wrap poorly at a
high-stakes decision point.

Required validation: test pseudo-localized strings, AX XXXL, compact and large
phones, and each loading, failure, and loaded paywall state. Confirm both links
remain separately focusable and tappable.

### P3-05. Sharing instructions lose their numbered structure in VoiceOver

Status: Confirmed accessibility source behavior.

Evidence:

- `Baby/Views/SharingView.swift:374-381` explicitly hides each step number.
- `Baby/Views/SharingView.swift:382-393` combines each step into one element.

User impact: A VoiceOver user hears the instruction text in order but not the
explicit Step 1, Step 2, and Step 3 structure. Joining a shared log is already
a multi-device flow, so the sequence matters.

Required validation: navigate the sharing explanation with VoiceOver and
confirm that each item communicates its step number, title, and detail without
duplicating the text.

### P3-06. Summary charts have no tested aggregate accessibility answer

Status: Validation risk.

Evidence:

- `Baby/Views/SummaryView.swift:249-262` gives charts visual titles and a
  fixed 120-point frame.
- There is no explicit chart summary or dedicated chart accessibility test in
  the current UI test set.

User impact: A VoiceOver user may receive chart marks without a concise answer
to the useful question, “What changed this week?”

Required validation: use VoiceOver, Dynamic Type, and Reduce Motion on every
chart. Confirm that a user can understand the trend without visual axes or
individual mark navigation.

### P3-07. Compact widget and Watch buttons lose the shared press state

Status: Confirmed source-level design audit advisories.

Evidence:

- `BabyWidget/BabyWidget.swift:194-210` uses `.buttonStyle(.plain)`.
- `BabyWatch/Views/WatchNowView.swift:72-89` uses `.buttonStyle(.plain)`.
- `scripts/design-audit.py` reports both as advisories because the shared
  `pressableCard()` feedback is not used.

User impact: The parent receives weaker immediate visual confirmation on the
surfaces where taps are most likely to happen while distracted. `lastAction`
helps on Watch, but the cross-surface feedback vocabulary is not identical.

Required validation: inspect press, release, haptic, pending, and failure
feedback on every supported widget family and Watch size. Treat native widget
constraints as valid only after they are visibly verified.

### P3-08. Long names and high counts need compact-surface fitting tests

Status: Validation risk.

Evidence:

- Live Activity title and child text have no explicit line limit or scale
  protection in `BabyWidget/BabyLiveActivity.swift:45-68`.
- Medium widget counters have no explicit fitting protection in
  `BabyWidget/BabyWidget.swift:87-95`.

User impact: A long baby name, localized label, or high daily count can crowd
out the elapsed time or control in a Lock Screen or widget presentation.

Required validation: use a 20-character name, high counts, pseudo-localized
strings, feed and sleep activities, compact and expanded Dynamic Island, and
every available widget family.

## What already works well and must be preserved

- Onboarding has two understandable paths, Start a new log and Join a shared
  log, and neither name nor birth date is required. See
  `Baby/Views/OnboardingView.swift:21-60` and `:155-189`.
- The first successful setup goes straight to logging with no paywall or tour,
  as covered by `BabyUITests/LoggingUITests.swift:83-92`.
- The Now hierarchy keeps last feed, side, last diaper, stable action zones,
  and quiet totals together in `Baby/Views/NowView.swift:16-45`.
- A feed tap is direct, while a long press opens details. This is an excellent
  compromise for speed and completeness in `Baby/Views/LogButtons.swift:36-80`.
- Haptics, pressed feedback, Undo, and Reduce Motion support already exist in
  `Baby/Views/Components.swift:44-76` and `Baby/Views/LogButtons.swift:82-88`.
- Sleep uses one stable action that changes to Wake and exposes elapsed time in
  `Baby/Views/LogButtons.swift:22-27` and `:90-135`.
- EventStore centralizes local taps, edits, stop actions, and rollback, with
  meaningful failed-save and failed-Undo tests in
  `Shared/Services/EventStore.swift:195-321` and
  `BabyTests/EventStoreTests.swift:114-236`.
- Watch payloads carry a child ID and are idempotent by event ID in
  `Shared/Services/EventStore.swift:343-360`. This foundation should be used
  for any cross-surface recovery feature.
- First Weeks already distinguishes a breastfeeding reference from a target,
  includes sources and a disclaimer, and avoids assessing logged counts against
  a medical target.
- Baby+ is limited to reporting, trends, CSV export, and more than one baby.
  Logging, History, Watch, widgets, sharing, stain helper, appearance, and
  onboarding remain free as intended.

## Fleet-derived QoL opportunities

These are recommendations for product decisions, not implemented fixes.

### 1. Make every write recoverable without adding a warning-heavy home screen

The fleet has useful patterns that fit Baby's principles:

- Caffeine exposes local-save and downstream-write state with automatic retry
  and a `Retry now` action in `../caffeine/Caffeine/Views/CaffeineViews.swift:213-248`
  and `../caffeine/Shared/Services/CaffeineLogService.swift:123-154`.
- Headaches pairs a snackbar with retry or support escalation in
  `../headaches/HeadacheLogger/Views/HomeView.swift:101-114` and `:502-529`.
- Sober keeps Undo only when the complete previous state can be restored in
  `../sober/Shared/Services/SlipRecorder.swift:95-124`.

For Baby, the smallest useful contract is: local success is explicit, failed
or pending cross-process writes are honest, delete can be recovered, and every
source has an event ID that can be corrected without undoing another parent's
action. Keep failure and sync copy in More, a toast, or a focused state card,
not as a persistent banner over the four logging actions.

### 2. Add optional Add details beside Undo

Headaches offers `Add Details` beside its fast capture feedback. Baby already
supports long press and an accessibility action in
`Baby/Views/LogButtons.swift:59-66`, but the visual `UndoToast` in
`Baby/Views/Components.swift:126-149` offers only Undo.

An optional Add details action could let a parent immediately add a note,
correct a time, or enter bottle information without forcing a form after every
tap. It must remain secondary to Undo and must not add a fifth home action.

### 3. Preserve stale-but-useful state, then retry precisely

Baseball loads cached data, distinguishes offline and decode failures, and
offers retry in `../baseball/StatScout/ViewModels/DashboardViewModel.swift:953-1018`
and `../baseball/StatScout/Views/DashboardView.swift:429-440`. Baby Docs keeps
an unreadable store available for recovery and explains the state in
`../babydocs/Shared/Services/BabyModelStore.swift:31-68` and
`../babydocs/BabyDocs/Views/SettingsView.swift:41-49`.

The transferable pattern is not a dashboard. It is retaining the last known
local log and last known share state, labeling uncertainty only when it
matters, and giving the parent one clear Retry or Support route. This fits
Baby's local-first model and keeps network status out of the primary tap flow.

### 4. Give compact surfaces enough context to prevent wrong logs

Caffeine's Watch flow shows useful preview and correction behavior in
`../caffeine/CaffeineWatch/Views/WatchCaffeineView.swift:31-60`. Daylight's
Watch flow makes state-specific copy and the headline explicit in
`../daylight/DaylightWatch/Views/WatchDaylightView.swift:34-92`.

For Baby, the high-value additions are explicit widget feed side or an
unambiguous next-side label, a clear Baby identity on Watch and widgets, and a
decision about whether the smallest accessory widget should expose Sleep.
Do not turn the glance surfaces into a second full app.

### 5. Consider a subtle caregiver source label in shared History

Attribution is the most defensible shared-log QoL gap. Start by measuring
whether a derived `You` or partner label from available transaction metadata is
enough. Only introduce a persistent model field if concurrent-parent testing
shows that a stable author identity is necessary. The label should be subtle,
optional in the display, and never imply medical interpretation.

### 6. Make release evidence state-complete

The fleet consistently benefits from explicit loading, empty, error, retry, and
accessibility evidence. For Baby, the capture manifest should cover:

- current source commit and build;
- iPhone device and OS;
- Light, Dark, Night light, and System appearance;
- default and Accessibility XXXL text;
- empty, seeded, running feed, running sleep, Undo, offline, and failure states;
- iPhone and Watch assets separately;
- each widget family that is marketed.

This is a quality improvement, not a product feature. It prevents another
visual system from becoming stale while the current app continues to evolve.

## Intentional non-recommendations

Do not transfer the parts of the fleet that conflict with Baby's product:

- no tab bar, dashboard sprawl, ads, AI panel, predictions, or promotional
  cards on Now;
- no HealthKit permission flow, since infant data types are not available and
  the app is intentionally local-first Core Data plus CloudKit;
- no automatic review prompt, purchase screen, or promotional step during
  onboarding;
- no new paywall around logging, History, Watch, widgets, sharing, appearance,
  or the stain helper;
- no moving or renaming of the four home action zones.

The fixed `ReviewPromptSheet` in `Baby/Views/SettingsView.swift:258-345` is
currently not wired into an automatic prompt path, which matches the product
rule. If it is ever exposed, its fixed 360-point detent should be tested at
AX XXXL, VoiceOver, Reduce Motion, and localized copy before being considered
complete.

## Recommended verification order

1. Timed feed plus one-tap feed, including Right, Bottle, widget, Watch, Siri,
   and two-parent handoff.
2. Delete and recovery from History swipe and Event Editor.
3. Outside-app timer lookup after 75 newer events.
4. Cold launch, slow store load, first invite, failed invite, and retry.
5. Background return while feed or sleep is running, including exact elapsed
   time and remote changes.
6. Compact phone and AX XXXL first-viewport measurements, then VoiceOver,
   Reduce Motion, and pseudo-localization.
7. Large-history and remote-change performance at 500, 2,000, and 10,000 rows.
8. Watch 40mm or 41mm, 46mm, offline queue, identity, conflicts, and physical
   WatchConnectivity delivery.
9. Current App Store and Watch recapture in every marketed appearance and
   state.

## Completion standard for this audit

The audit document is complete when each P1 has an explicit owner decision or
passing validation evidence, each P2 has a measured risk or a scheduled test,
and each P3 is either verified across the declared device matrix or deliberately
accepted as out of scope.

No source or product code was changed in this audit. The two 65-test runs and
the current simulator inspections support the normal local path, not a claim
that every degraded, synchronized, accessibility, or release surface is
perfect.
