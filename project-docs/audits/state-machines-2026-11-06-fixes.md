# Fixes for the state machine audit, 2026-11-06

Fixes the claims `state-machines-2026-11-06-review.md` confirmed, in its ranked order, plus the product call it reclassified as a real defect. Branch `fleet/20261106-165442-0260-claude`, from `95553e6`.

**Summary: 5 in scope. 4 fixed, 0 held, 1 skipped.** (B2, B4, B1 and product call 5 fixed; product call 6 settled as unreachable.)

## Claims

| id | verdict (review) | result | commit | regression test | what changed |
|---|---|---|---|---|---|
| B2 | CONFIRMED | fixed | `2b6621a` | `StateMachineRegressionTests.testLast24HoursDropsAFeedOnceItIsOlderThanADay` (the audit's repro, which the review called sound), `testLast24HoursDiapersAgeOutAndMatchTheWatchList`, `testAWristTapUnderLast24HoursAgesOutAndItsUndoIsNotSubtractedTwice`, `testASummaryFromAnOlderBuildStillDecodes` (upgrade), `testDayWindowStillClearsAtTheNextDay` (control) | Under Last 24 hours, `NowSummary` carries the feeds and diapers it counted (`counted`, optional, nil for day windows and for summaries from older builds). `current(now:)` drops each one, and its count, once it is 24 hours old, so widgets, complications and the Watch Today page agree with Now and with the Watch list. Wrist taps join the list; a wrist Undo takes its entry out. An older cached or pushed summary decodes unchanged and keeps the old behaviour until the phone republishes, which it does on its first refresh because the content differs |
| B4 | CONFIRMED-MINOR | fixed | `54f94ff` | `StateMachineRegressionTests.testReturningToTheAppAsksSettingsToReadPermissionAgain` | The foreground pass posts `Reminders.foregrounded`; Settings > Reminders reads notification permission again on it, so the "Notifications are off" footer and the Allow button go away after the parent allows notifications (and appear after they turn them off). The visible half needs a device: the simulator cannot change notification permission |
| B1 | CONFIRMED-MINOR | fixed | `54f94ff` | `StateMachineRegressionTests.testReturningToTheAppHandsTheReminderPlanOverWithAnUnchangedLog` | Shares B4's cause and fix. `App.swift`'s `scenePhase == .active` handler now calls `EventStore.returnToForeground()`, which forgets the last plan, reloads, then calls `Reminders.reschedule` directly, so an unchanged log still hands the plan over. `Reminders.lastPlanned` is now readable (`private(set)`) for the test. The audit's repro proved `reload()` alone never reached `publish()` |
| Product call 5 | real defect (review) | fixed | `8e829f2` | `RemindersTests.testACheckupNoteIsAWallClockTimeThatFollowsTheTimeZone` | Checkup notes are `UNCalendarNotificationTrigger`s with year, month, day, hour and minute and no zone, so the evening-before note arrives at 7 pm wherever the phone is. The feed reminder stays a time interval from the feed |
| Product call 6 | unproven code-path bug (review) | skipped | | | See Skipped |

Not in scope: B3 and B5 (NOT A BUG), product calls 1 to 4 (the review called them fair or documented), including call 2's note that the visit picker shows a stored past date.

No new user-facing text. No stored data is reset or dropped.

## Held for Jack

None.

## Skipped

- **Product call 6, the remove-in-completion race in `Reminders.reschedule`.** Not reachable from the shipping app as a lasting fault. In one process it needs two plans that differ (one with a feed reminder, one without) inside one notification-center round trip of a few milliseconds; the only inputs that flip the plan are human taps (start or stop a feed timer, change the interval, turn the feed button off), and the new foreground pass plans twice from the same summary, so its plans match and the second is a no-op. Across processes (widget and app, the review's likeliest trigger), the app can only plan from a summary that misses the widget's feed before the widget saves; the widget's save posts `NSPersistentStoreRemoteChange` (`Persistence.swift:105`), the app's `scheduleReload` refreshes, the summary changes, and `publish()` reschedules with a plan that differs from its last one, so the feed reminder is added back at once. A suspended app plans nothing, so it cannot race.

## Tests

Command: `gh-sim test --scheme Baby` (iOS simulator on GitHub's Macs).

- Baseline, before any change (`95553e6`): `baby@20261106-165442-0260-claude-imac7ee2-1106-165519-9348`, GitHub run `42321129016`. 286 passed, 0 failed, 1 skipped. Nothing already failed.
- Final, with every fix (`8e829f2`): `baby@20261106-165442-0260-claude-imac7ee2-1106-175903-22422`, GitHub run `42326906808`. 294 passed, 0 failed, 1 skipped: the same 286 plus the 8 new regression tests. Nothing newly failed.

The audit's repro suite was never added to the test target; its sound B2 test lives on as `testLast24HoursDropsAFeedOnceItIsOlderThanADay`. The new B1, B4 and call 5 tests call code the fixes add (`returnToForeground`, the calendar trigger), so their failing half before the fix is the audit's and review's repro runs (`reload()` never reached `publish()`), not a rerun.
