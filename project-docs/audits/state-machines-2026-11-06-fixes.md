# Fixes for the state machine audit, 2026-11-06

Fixes the claims `state-machines-2026-11-06-review.md` confirmed, in its ranked order, plus the product call it reclassified as a real defect. Branch `fleet/20261106-165442-0260-claude`, from `95553e6`.

**Summary: 5 in scope. 5 fixed, 0 held, 0 skipped.** (B2, B4, B1 and product call 5 fixed in the first pass; product call 6 reopened on 2026-11-06 and fixed after a callback-order test failed on `01d24ce`.)

## Claims

| id | verdict (review) | result | commit | regression test | what changed |
|---|---|---|---|---|---|
| B2 | CONFIRMED | fixed | `2b6621a` | `StateMachineRegressionTests.testLast24HoursDropsAFeedOnceItIsOlderThanADay` (the audit's repro, which the review called sound), `testLast24HoursDiapersAgeOutAndMatchTheWatchList`, `testAWristTapUnderLast24HoursAgesOutAndItsUndoIsNotSubtractedTwice`, `testASummaryFromAnOlderBuildStillDecodes` (upgrade), `testDayWindowStillClearsAtTheNextDay` (control) | Under Last 24 hours, `NowSummary` carries the feeds and diapers it counted (`counted`, optional, nil for day windows and for summaries from older builds). `current(now:)` drops each one, and its count, once it is 24 hours old, so widgets, complications and the Watch Today page agree with Now and with the Watch list. Wrist taps join the list; a wrist Undo takes its entry out. An older cached or pushed summary decodes unchanged and keeps the old behaviour until the phone republishes, which it does on its first refresh because the content differs |
| B4 | CONFIRMED-MINOR | fixed | `54f94ff` | `StateMachineRegressionTests.testReturningToTheAppAsksSettingsToReadPermissionAgain` | The foreground pass posts `Reminders.foregrounded`; Settings > Reminders reads notification permission again on it, so the "Notifications are off" footer and the Allow button go away after the parent allows notifications (and appear after they turn them off). The visible half needs a device: the simulator cannot change notification permission |
| B1 | CONFIRMED-MINOR | fixed | `54f94ff` | `StateMachineRegressionTests.testReturningToTheAppHandsTheReminderPlanOverWithAnUnchangedLog` | Shares B4's cause and fix. `App.swift`'s `scenePhase == .active` handler now calls `EventStore.returnToForeground()`, which forgets the last plan, reloads, then calls `Reminders.reschedule` directly, so an unchanged log still hands the plan over. `Reminders.lastPlanned` is now readable (`private(set)`) for the test. The audit's repro proved `reload()` alone never reached `publish()` |
| Product call 5 | real defect (review) | fixed | `8e829f2` | `RemindersTests.testACheckupNoteIsAWallClockTimeThatFollowsTheTimeZone` | Checkup notes are `UNCalendarNotificationTrigger`s with year, month, day, hour and minute and no zone, so the evening-before note arrives at 7 pm wherever the phone is. The feed reminder stays a time interval from the feed |
| Product call 6 | unproven code-path bug (review) | fixed | fix: keep a newer feed reminder when an older plan's pending list arrives late | `StateMachineRegressionTests.testALatePendingAnswerKeepsTheNewerFeedReminder`, `testEveryPlannedReminderIsOneANewPlanClears` | `Reminders.reschedule` removed stale requests inside a `getPendingNotificationRequests` callback using the `keep` set it captured. Answered after a newer plan added `baby.feed`, that callback deleted it, and later identical plans stopped at the `planned != lastPlanned` guard, so nothing restored it. It now removes this phone's known identifiers outside the plan (`Reminders.ownedIDs`: `baby.feed`, `baby.checkup.entered`, `.day4`, `.day14`, `.day30`) synchronously, before the adds, with no callback. These identifiers have not changed since reminders shipped, so nothing pending on an upgraded phone is left behind. A small `Reminders.Center` seam (`centerOverride`) lets the test record removes and adds |

Not in scope: B3 and B5 (NOT A BUG), product calls 1 to 4 (the review called them fair or documented), including call 2's note that the visit picker shows a stored past date.

No new user-facing text. No stored data is reset or dropped.

## Held for Jack

None.

## Skipped

None. Product call 6 was skipped in the first pass as unreachable; that was not a valid reason (the review left it unproven, and a rare or narrow route is still a route), so it was reopened, proved and fixed. See Reopened.

## Reopened: product call 6

Route: any two plans that differ inside one notification-center round trip in one process, for example starting and then stopping a feed timer, changing the interval, or a foreground pass right after a log change. The first plan's late pending-list answer still listed the second plan's new `baby.feed` and removed it.

Proof on the old logic: the new test ran against `01d24ce`'s `reschedule` routed through the same seam with one extra member, `pending`, whose callbacks the fake holds and answers after both plans (the only change, so it compiles). Run `baby@20261106-224548-d0e4-claude-imaca948-1106-232702-19071`, GitHub run `42351331828`: failed at the final assertion, `("[]") is not equal to ("["baby.feed"]")`, with both preconditions (each plan reached the center) holding. A first proof attempt (GitHub run `42348569901`) passed only because setUp's `createChild` had already planned `[]`, so the test's first pass stopped at the guard; the test now forgets the last plan first and asserts each pass reaches the center.

With the fix there is no callback to answer late: plan one removes `baby.feed` at once, plan two adds it, and it stays.

## Tests

Command: `gh-sim test --scheme Baby` (iOS simulator on GitHub's Macs).

- Baseline, before any change (`95553e6`): `baby@20261106-165442-0260-claude-imac7ee2-1106-165519-9348`, GitHub run `42321129016`. 286 passed, 0 failed, 1 skipped. Nothing already failed.
- Final, with every fix (`8e829f2`): `baby@20261106-165442-0260-claude-imac7ee2-1106-175903-22422`, GitHub run `42326906808`. 294 passed, 0 failed, 1 skipped: the same 286 plus the 8 new regression tests. Nothing newly failed.

The audit's repro suite was never added to the test target; its sound B2 test lives on as `testLast24HoursDropsAFeedOnceItIsOlderThanADay`. The new B1, B4 and call 5 tests call code the fixes add (`returnToForeground`, the calendar trigger), so their failing half before the fix is the audit's and review's repro runs (`reload()` never reached `publish()`), not a rerun.

Reopened pass (product call 6), on branch `fleet/20261106-224548-d0e4-claude` from `01d24ce`:

- Proof on the old logic: GitHub run `42351331828`, 1 run, 1 failed (see Reopened).
- Final full suite with the fix: `baby@20261106-224548-d0e4-claude-imaca948-1107-000654-6408`, GitHub run `42354081212`. **296 passed, 0 failed, 1 skipped**: the earlier 294 plus the 2 new tests. The skip is the pre-existing `WidgetCloudSyncTests.testSharedBabyWritesToTheSharedDatabase` ("needs a signed host app"). Nothing newly failed and nothing already failed on `01d24ce`. No repro suite was added to the test target.
