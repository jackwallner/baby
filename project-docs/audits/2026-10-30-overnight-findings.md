# Overnight findings, 2026-10-30

Bug hunt and release review of Baby Tracker 1.4.1 (build 70), source at
`07f6be4`. Report only: nothing in the app was changed. Findings are new
relative to `laudit913.md`, `build-28-widget-audit.md` and the decisions
recorded in `.claude/rules/`.

Evidence comes from reading the code paths end to end and from scratch tests
run on GitHub's Macs with `gh-sim` (never committed). Two runs:

- `baby@20261029-230902-5e97-claude-mbproe4ab-1030-015346-29312`: the unit
  test host crashed at launch (finding 7).
- `baby@20261029-230902-5e97-claude-mbprof796-1030-064148-17437`: the same
  five scratch unit tests with the test host kept off CloudKit by a local,
  uncommitted patch. RUN1_RESULT
- RUN2_LINE

## Summary

| ID | Sev | Area | Title | Established by |
| --- | --- | --- | --- | --- |
| 1 | P1 | Watch sync | A wrist tap for a baby the phone no longer has is never acknowledged, and a stuck Sleep/Wake blocks every later one | EST1 |
| 2 | P1 | Onboarding, data | Setup shown over an existing log erases the baby's name and birth date | EST2 |
| 3 | P1 | Settings, data | Settings writes a stale name and birth date back over a partner's newer ones | Source only |
| 4 | P1 | Sharing, data | "Bring your entries" stays armed after a join with nothing to move, then offers to fold another baby into the shared one | EST4 |
| 5 | P1 | Logging, dates | The log-time wheel, turned forward past midnight after crossing back, logs a day early | EST5 |
| 6 | P2 | Performance | Reports rebuilds the whole report about 35 times and the CSV once per render, and keeps rendering after the first visit | EST6 |
| 7 | P2 | Tests, CloudKit | Unit tests cannot run on GitHub's Macs: the test host traps in `CKContainer(identifier:)` at launch | Runtime (crash log) |
| 8 | P2 | Sharing, main thread | Create invite blocks the main thread on the CloudKit mirroring queue | Source only |
| 9 | P2 | App Review, privacy | The privacy policy and manifest do not disclose the setup answer and paywall counters sent to RevenueCat | Source and published page |
| 10 | P3 | Totals, DST | The hour strip has no square for the last hour of the 25-hour fall-back day | EST10 |
| 11 | P3 | Purchases | Baby+ subscribers see Upgrade and a locked chart for the first frames of every launch | Source only |
| 12 | P3 | Analytics | `setup_stage` records a skipped answer as "born" and never moves an expecting install to born | Source only |

Counts: 0 P0, 5 P1, 4 P2, 3 P3.

## 1. P1: a wrist tap for a missing baby is never acknowledged

Where:
- `Shared/Services/EventStore.swift:847` returns false when the payload's
  baby is not on the phone, without recording it as applied.
- `Shared/Services/WatchSyncService.swift:83` then replies `[:]` and
  `:219` sends no receipt.
- `Shared/Services/WatchStore.swift:123` (`markDelivered`) is the only thing
  that removes a pending tap.
- `Shared/Models/BabyModel.swift:385` (`WatchLogPayload.sendable`) holds every
  later Sleep/Wake behind the first pending one, whichever baby it names.
- `BabyWatch/Views/WatchNowView.swift:24` shows "N waiting for iPhone".

Reproduction: the Watch shows baby A. Tap Sleep on the wrist while the phone
is out of reach (the payload carries A's id). On the phone, A goes away: the
parent accepts "Bring your entries" on joining a shared log (which deletes the
separate baby), leaves a shared log, or the owner stops sharing. Bring the
Watch back. The phone logs "Watch payload ... ignored because its baby
profile is unavailable" and answers with no receipt, every time the Watch
retries. The wrist shows "1 waiting for iPhone" forever, and every later
Sleep or Wake on the wrist, now for the current baby, is held behind the
stuck one by `sendable(from:)` and never sent. The wrist draws those sleeps
as running (they are replayed over the summary); the phone and the partner
never get them. Feeds and diapers still go through.

User impact: wrist sleep logging silently stops reaching the log until the
Watch app is deleted. The trigger (a baby disappearing with a wrist tap in
flight, or before the Watch hears about the new baby) is most likely right
after joining a partner's log.

Why: refusing a tap is correct, but the refusal is indistinguishable from a
failed save, which the Watch is built to retry forever. The sleep-toggle
ordering guard is global rather than per baby.

Smallest fix: in `EventStore.apply(_:forChildID:)`, when `targetID` names no
baby and `persistence.isStandingIn` is false, append the payload id to
`appliedWatchActions` and return true, so the existing receipt path clears
it (still never writing it to another baby). Optionally scope the blocking in
`sendable(from:)` to payloads with the same `childID`.

Guard test: `EventStoreTests`: `apply` of a `.startSleep` naming an unknown
baby returns true and a second `apply` of the same id is a no-op; and
`WatchLogPayload.sendable` releases a toggle once the toggle ahead of it is
acknowledged. The scratch test `testScratchWatchTapForABabyThatIsGoneIsAcknowledged`
asserts both halves. RESULT1

## 2. P1: setup over an existing log erases the baby's name and birth date

Where: `Baby/App.swift:200` shows onboarding whenever `hasCompletedSetup` is
false and the active baby is not shared, even when a private baby with a log
is already on the phone. `Baby/Views/OnboardingView.swift:238` then calls
`events.update(child:name:birthDate:)` with the form's values, which are all
optional and default to blank.

Reproduction (scratch UI test): launch with `-NoCloudKit -hasCompletedSetup NO`,
set up "Nora" with a birth date, log a feed, relaunch with the same arguments
(setup not done, log still there), tap Start tracking without filling the
optional fields. RESULT2

In the field: delete and reinstall the app, or set up a new iPhone without a
backup restore, with the log in iCloud. `hasCompletedSetup` lives in the App
Group, so it is gone; CloudKit brings the baby back while setup is on screen;
Start tracking with the optional fields left blank writes a nil name and birth
date over the restored baby, and CloudKit exports that to every device,
including a partner's. No entries are lost; "Day N", First Weeks and the
checkup reminders lose their birth date.

Related (source only): if the import lands after Start tracking,
`createChild` makes a second, empty baby and stores it as the active one, so
the restored history is hidden under Settings > Babies.

Smallest fix: in `RootView`, treat setup as done when a baby with entries is
already present (set `hasCompletedSetup = true` and show the log); and in
`finish()`, never replace an existing value with a blank one
(`trimmed.isEmpty ? child.name : trimmed`, `hasBirthDate ? birthDate : child.birthDate`).

Guard test: the scratch `LoggingUITests.testScratchSetupAgainKeepsTheExistingBabysDetails`
(name and "Day 1" survive setup shown again).

## 3. P1: Settings writes a stale name and birth date back

Where: `Baby/Views/SettingsView.swift:71` loads the baby's name, Born and
birth date into local state only on appear and when `events.child?.objectID`
changes; `:73`-`:75` save on any change, and `saveChild()` (`:152`) always
writes all three. `Baby/App.swift:356` keeps every visited tab alive, so
switching back to the Settings tab does not run `onAppear` or reload them.

Reproduction: on phone B, open Settings once, then go back to Log. On phone A
(the partner in a shared log, or the same Apple ID on another device) set the
name to "Nora" and add the birth date. B's Now shows "Nora" and "Day 5" once
it syncs, but B's Settings still shows the old name and Born off. B turns
Born on, or edits the name: `saveChild()` writes B's old name, and with Born
turned on, today's date as the birth date, over A's values on every device.

User impact: the baby's name or birth date silently reverts, in a shared log,
after a perfectly normal edit. Settings also shows out-of-date details.

Why: the form keeps a copy of the model that nothing refreshes when the same
baby changes remotely, and every edit writes the whole copy back.

Smallest fix: reload the fields when the model changes
(`.onChange(of: events.child?.name)` and `.onChange(of: events.child?.birthDate)`,
skipping while the name field is focused), and save only the field the
parent touched. Debouncing the name would also stop each keystroke from
saving, reloading the log and pushing to the widgets, the Watch and the
reminders.

Guard test: move the three fields into a small editor model with
`load(from:)` and `save(changed:)`, and unit test that a remote change
reloads it and that a birth-date edit leaves the stored name alone; or a
`TwoPhoneTests` case over `SimPartnerRelay`.

## 4. P1: the arrival offer stays armed and can fold another baby in

Where: `Shared/Services/EventStore.swift:461` sets `arrivedSharedChild` when
an accepted invitation's baby arrives. Only the alert's buttons clear it
(`Baby/App.swift:215`, `:222`, `:224`), and the alert's `isPresented` is
recomputed on every render from `separateLogs(besides:)` (`Baby/App.swift:214`,
`:254`-`:260`).

Reproduction (scratch unit test): the phone has Twin B with no entries. Join
Twin A's shared log; on arrival there is nothing to move, so no alert, and
the offer stays armed for the rest of the session. Switch to Twin B and log a
pee. The alert now appears: "Bring your entries into the shared log? You
logged on this phone before joining Twin A's log." Move folds Twin B's entry
into Twin A and deletes Twin B. RESULT4

User impact: an out-of-context prompt whose default-looking action deletes a
baby profile and misfiles its entries. The same happens with a named
placeholder baby from onboarding the moment anything is logged for it.

Why: the one-time offer is never spent when there was nothing to offer.

Smallest fix: in `finishPendingShareImport`, set `arrivedSharedChild` only
when `separateLogs(besides: shared)` has exactly one log with entries at
arrival, or clear it in `RootView` as soon as it is set with nothing to show.

Guard test: the scratch `SharingTests.testScratchArrivalOfferIsSpentWhenThereIsNothingToMove`.

## 5. P1: the log-time wheel logs a day early after crossing midnight

Where: `Baby/Views/NowView.swift:399` (`LogClock.set`) and the wheel's
binding at `:274`. A time-only `DatePicker` keeps the calendar day of the
value it was given; `set` only corrects a time later than now.

Reproduction (scratch unit test): at 12:20 AM, open the log-time wheel and
set 11:45 PM. `set` moves it to yesterday 11:45 PM, which is right. Turn the
wheel on to 12:05 AM: the wheel still holds yesterday's date, so `set`
receives yesterday 12:05 AM, earlier than now, and keeps it. Feed logs 24
hours 15 minutes ago. Stepping back past midnight with minus and then using
the wheel does the same. RESULT5

User impact: a night feed lands on the day before. Today's totals, "Fed ...
ago", the feed reminder and History are all off by a day. The toast says
"12:05 AM yesterday", which reads as plausible at that hour.

Smallest fix: build the date from `now` and the wheel's hour and minute
(`calendar.date(bySettingHour:minute:second:of: now)`), then step back a day
only if that is more than a minute in the future.

Guard test: the scratch `ClockBoundaryTests.testScratchWheelTurnedForwardPastMidnightLandsOnTheLastOccurrence`.

## 6. P2: Reports does the whole report about 35 times per render

Where: `Baby/Views/SummaryView.swift:138` makes `report` a computed property
over `events.visitReport(since:)`, which runs `SummaryReport.make` across the
whole log (and reads the tracked kinds from the App Group) on every read; the
body reads it about 35 times (range line, tiles, note, three chart cards,
doctor card). `:369`-`:375` build the full CSV string inside the body.
`Baby/App.swift:356` keeps the Reports tab alive after the first visit, so a
Baby+ parent who has opened Reports once re-renders it on every tap on Log.

Measurement (scratch performance test, six months of logging, simulator on a
GitHub runner): RESULT6

User impact: tap latency on Log grows with the log for Baby+ users, the
kind of lag Jack reported in build 49.

Smallest fix: compute the report once per body (`let report = ...` at the top
of `body`, passed down) or cache it in `EventStore` per revision and range,
and build the CSV inside the `Transferable` representation instead of the
body.

Guard test: a `PerformanceBudgetTests` case over one Reports render with six
months of entries.

## 7. P2: the unit-test host traps in `CKContainer(identifier:)` at launch

Where: `Shared/Services/EventStore.swift:279` calls `WidgetCloudSync.flush()`
on every reload pass, and `Shared/Services/WidgetCloudSync.swift:236` builds
`CKContainer(identifier:)` as a default argument before looking at the queue.

Reproduction: `gh-sim test --only BabyTests/...` (unsigned build, CloudKit on
in the host app). Result: "Baby encountered an error (Early unexpected exit,
operation never finished bootstrapping ... The test runner crashed before
establishing connection)". The crash log: `EXC_BREAKPOINT` on a cooperative
thread in CloudKit, under `CKContainer.__allocating_init(identifier:)` <-
default argument 0 of `WidgetCloudSync.flush(container:)` <- closure in
`EventStore.reconcileWidgetCloudWrites()`, while the scene was still
connecting. With CloudKit kept off in the host, the same tests ran (run 2).

User impact: no shipped-build crash is shown here (signed builds have the
iCloud entitlement). The cost is that no unit test can run on GitHub's Macs,
where the xcodebuild shim also sends overflow test runs. The same pass also
creates a `CKContainer` and rewrites `WidgetCloudSync/state.json` three
times under its file lock (claim, renew, release) on every reload, with
nothing queued.

Smallest fix: return from `flush()` before building a container when
`pending()` is empty (take the container lazily), and keep CloudKit off in
the unit-test host (`Persistence.processWantsCloudKit` false when
`XCTestConfigurationFilePath` is set, or `-NoCloudKit` in the scheme's test
action).

Guard test: any `gh-sim test` run of `BabyTests`.

## 8. P2: Create invite blocks the main thread on the mirroring queue

Where: `Shared/Services/SharingService.swift:124` calls `fetchShares` on the
main actor, `:204`-`:212` poll `container.recordID(for:)` on the main actor
every 500 ms for up to 150 seconds, and `Shared/Services/ShareInvite.swift:36`
calls `fetchShares` on the main actor too. `.claude/rules/interface.md`
("Main thread") records that both calls wait on the mirroring queue, busy for
seconds while a phone syncs.

Reproduction: on a fresh install, open Settings > Invite someone > Create
invite while the first CloudKit setup runs (about two minutes, per the
comment at `:206`). Each poll waits on the mirroring queue on the main thread,
so "Making your invite…" and its Cancel button stall; the same happens on a
phone catching up after a long time offline.

Smallest fix: run the polling and both `fetchShares` calls in
`Task.detached`, as `lookUpShare` already does.

Guard test: a `SharingTests` case with a slow `recordID` stand-in that
asserts the main actor stays responsive (or a signpost budget).

## 9. P2: privacy disclosures miss what is sent to RevenueCat

Where: `Baby/Views/OnboardingView.swift:248` records the setup answer, and
`Shared/Services/StoreService.swift:557`-`:574` sends it to RevenueCat as
`setup_stage` ("expecting" or "born") with the customer, together with
`ConversionDiagnostics.subscriberAttributes` (paywall views per surface, first
pitch date, days since install, app opens before the first pitch, conversion
plan and timing). `docs/privacy-policy.html` (Purchases) says RevenueCat
receives "an anonymous app user identifier, product identifiers, entitlement
status, and purchase events". `Baby/PrivacyInfo.xcprivacy` declares no
collected data.

User impact: the published policy undersells what leaves the phone, and
"expecting" is pregnancy status, which some laws (Washington's My Health My
Data Act, for one) treat as consumer health data. App Review holds the
policy and the App Privacy label to what the app sends (5.1.1, 5.1.2). The
label itself is not recorded in the repo, so it needs a look in App Store
Connect.

Smallest fix: name the setup answer and the paywall counters in the policy,
the App Privacy label and the manifest's collected data types, or stop
sending "expecting".

## 10. P3: the hour strip loses the last hour of the fall-back day

Where: `Shared/Services/NowSummary.swift:647` fixes the strip at 24 columns
and `:671`-`:674` index by elapsed hours from the window start.

Reproduction (scratch unit test): Los Angeles, 2026-11-01, a feed at 11:30 PM.
The totals count it; its column index is 24, so no square is drawn. RESULT10

User impact: once a year, the last hour's entries are missing from the strip
and from its VoiceOver summary while the counts include them.

Smallest fix: size the grid by the window's real hour count, or place entries
by wall-clock hour.

Guard test: the scratch `ClockBoundaryTests.testScratchHourStripAgreesWithTheTotalsOnAFallBackDay`.

## 11. P3: subscribers see Upgrade on the first frames of every launch

Where: `Shared/Services/StoreService.swift:201` starts `isPro` false; the App
Group copy written at `:204`, `:579` and `:672` is never read; `store.start()`
runs from `RootView`'s `.task` (`Baby/App.swift:96`), after the first frame.

User impact: the capsule shows "Upgrade" with a lock, and History's chart is
blurred, until RevenueCat's cached customer info is applied. With no cached
info (a reinstall) it lasts until the network answers.

Smallest fix: seed `isPro` from the cached flag in `init`, still overwritten
by RevenueCat's answer.

## 12. P3: the setup-stage metric miscounts

Where: `Baby/Views/OnboardingView.swift:248` sends `expecting: feeding == .expecting`,
so a parent who skips the optional question is recorded as "born", and
nothing updates the attribute when an expecting install adds a birth date.

User impact: the "installs before the birth" number undercounts.

Smallest fix: send nothing when the question is skipped, and send "born"
the first time Settings gets a birth date for an expecting install.

## Checked and fine

- Free and paid boundary: the PDF share, CSV export, Reports charts and
  History's day chart all check `store.isPro`; the paywall previews blur the
  baby's numbers and give VoiceOver fixed labels, not the values; the locked
  chart is one labelled button.
- `StoreService`: DEBUG builds never configure the production key on a
  simulator; cached customer info is applied at start, so an offline
  subscriber keeps access; an older customer info cannot overwrite a newer
  one; Restore separates "none found" from a failure; lifetime owners get no
  Manage subscription.
- Paywall: loading, failure and plan states all render the billing
  disclosure, Restore, Terms of Use and Privacy Policy; trial copy waits for
  eligibility.
- Core Data model: no schema change since `6778cec` (`c37ddc9` only added a
  helper), so the September Production deploy still matches.
- `Persistence`: the stand-in store refuses writes before first unlock,
  corrupt files are moved aside only for SQLite 11 and 26, and a CloudKit
  failure falls back to the local store.
- Widget direct writes: queue folding, deletes kept until confirmed, the
  upload claim lapses on its own, and `DuplicateEvents` ranks copies by
  record name only, so every device keeps the same copy; edits on the losing
  copy are carried over.
- Widget, control and Siri intents: stale-baby refusal, the 3-second double
  tap, Undo accepted for 60 seconds, running timers found at any age.
- Watch: reply handlers are `@Sendable`; an older summary never wins; Undo is
  idempotent; applied ids are capped at 256.
- Reminders: one identifier per reminder replaced in place, stale ones
  removed, unchanged plans skipped; notification taps answered on the main
  thread.
- Crash sweep: the only force unwraps are constant URLs, the in-memory stand-in
  store and a Live Activity state built from a running start; no `try!`;
  index access is guarded.
- PDF: pagination always advances after page 1, the key and notes move to a
  new page, notes truncate with a count.
- `SummaryReport`: partial days, gaps across a whole unlogged day excluded,
  day stepping through `Calendar`, sleep split at midnight and capped at now.
- Health copy: the disclaimer is in onboarding, First Weeks, Reports,
  Settings and the paywall; First Weeks is a reference, never an assessment.
- `Info.plist` and manifests: camera purpose string, encryption flag,
  Live Activities, remote-notification background mode; the UserDefaults
  reasons (CA92.1, 1C8F.1) are declared.
- Accessibility: every icon-only control checked has a label (Close, Add an
  entry, the month arrows, 5 minutes earlier or later, Log earlier).

The scratch tests that established findings 1, 2, 4, 5, 6 and 10 are not
committed; their code is in this report's history only as descriptions. Re-create
them from the guard tests above.
