VERDICT: PASS

# Verification of the state machine fixes, 2026-11-06 (reopened pass)

Independent check of `state-machines-2026-11-06-fixes.md` against `state-machines-2026-11-06-review.md` and the audit. The change under review is `git diff 01d24cee..HEAD` on branch `fleet/20261107-020629-c2f0-claude`, HEAD `861c57c1`. It contains the product call 6 fix commit `814b13f8` (`Shared/Services/Reminders.swift`, two tests in `BabyTests/StateMachineRegressionTests.swift`), doc commit `e32c3de3` (fixes doc and the `project-docs/README.md` line) and `861c57c1`, which is an empty fleet snapshot. B2, B1, B4 and product call 5 shipped before `01d24cee`. The earlier verify pass (`3709ba49`) checked them, and nothing in this diff touches their code. This doc replaces that one. No app code or tests were changed here.

## Fixes

| id | works | regression check | evidence |
|---|---|---|---|
| Product call 6, a late pending-list answer in `Reminders.reschedule` deletes a newer `baby.feed` | yes | clean | Old code (`01d24cee` `Reminders.swift:225-228`) asked for the pending list and removed `baby.feed` or `baby.checkup.*` entries outside the plan inside the callback, by identifier. The callback runs after this pass's adds and after any later pass's adds. If an earlier `baby.feed` was in its snapshot and the plan that asked dropped it, it removed the newer one. A later identical plan then stops at the guard (`Reminders.swift:223`), so nothing restores it. New code (`Reminders.swift:225-232`) removes `ownedIDs` minus the plan synchronously, before the adds, with no callback. Removed and added IDs are disjoint, so the order inside one pass cannot matter, and each pass's calls are issued in order on the main thread. `ownedIDs` (`:91`) is exactly the set `feedReminder` (`:161`) and `checkupReminders` (`:176`, `:188`) can produce. `typicalCheckupDays` has been `[4, 14, 30]` and the prefix `baby.checkup.` since reminders shipped (`ae173643`, checked with `git log -G`), so on an upgraded phone every pending request the old prefix filter could clear is still cleared. Proof that the fault is real on the old logic: my scratch test (below) failed at the behaviour assertion on the reverted code |

## Disputed

The fixes doc has no Disputed section, so there is nothing to rule on. It has no Held or Skipped items either. Product call 6, skipped in the earlier pass, is now fixed. That is within the rules: the review left it unproven (`review.md`, product call 6), and the reopen comes with a failing test on the `01d24cee` logic, both the fixer's (GitHub run `42351331828`, `("[]") is not equal to ("["baby.feed"]")`) and mine (run `42365876331`, below).

## Fail-without-fix proof

On a throwaway branch `scratch-revert` I put back the `01d24cee` remove-in-callback logic exactly as it was. The `Center` seam, `centerOverride` and `ownedIDs` stayed so the kept tests compile. `Center` gained a defaulted `pending` member backed by the real `getPendingNotificationRequests`, so with no override, production behaves exactly as `01d24cee`. Both committed tests stayed unchanged. I added one scratch test, `ScratchLateAnswerTests.testOldLogicLateAnswerDeletesTheNewerFeedReminder`. Its fake center snapshots its pending list when asked, the way the daemon does, and answers late. It starts with an older `baby.feed` pending, then runs the feed-running plan, then the stopped-feed plan, then answers both, then runs an identical plan. The branch was then deleted. One run, `gh-sim test --scheme Baby --only` for all three:

- Run `baby@20261107-020629-c2f0-claude-imacae52-1107-025356-19961`, GitHub run `42365876331`: 1 passed, 2 failed.
- `ScratchLateAnswerTests.testOldLogicLateAnswerDeletesTheNewerFeedReminder`: **failed at the behaviour assertion**, `("[]") is not equal to ("["baby.feed"]")`, with its precondition (the second plan added the reminder) holding. This is the user-visible fault: the feed reminder is gone and stays gone.
- `testALatePendingAnswerKeepsTheNewerFeedReminder` (committed): failed, but only at its preconditions, `StateMachineRegressionTests.swift:181` (`("0") is not equal to ("1") - precondition: the first plan reached the center`) and `:184`. Its behaviour assertion at `:186` held on the old code, because the real center's callback answered after the assertion ran. So this test fails without the fix only because it counts `remove` calls made in line, which is the fix's own hook. It does not model a late answer. See Notes.
- `testEveryPlannedReminderIsOneANewPlanClears` (committed): passed on the revert, as expected. It is a consistency guard (every plannable ID is in `ownedIDs`, `:201`), not a test of the race, and the revert kept `ownedIDs`.

Only one fix is in this diff, so the "top three" are its two tests plus the scratch behaviour test.

## Regression check

Read every caller of `Reminders.reschedule` and everything that reads its state:

- `EventStore.publish()` (`EventStore.swift:372`) and `returnToForeground()` (`:180-185`): same arguments as before. `lastPlanned` is still set before any center call (`Reminders.swift:224`), so the B1 foreground handover and its test are unchanged (both pass in the full run).
- Settings > Reminders (`RemindersView.swift:152` offer accept, `:277` `apply`): unchanged call sites. The denied path still records `lastPlanned`, as before.
- Widget extension (`AppIntents.swift:174`, `rescheduleReminders`): `Reminders.swift` is in `SharedCore`, compiled into the app and the widget (`project.yml:92`, `:102`, `:167`). The widget uses the live `Center` (`Reminders.swift:243-250`). Cross-process behaviour is the same as before: a stale plan in either process removes `baby.feed` by identifier, synchronously now and late before, and the app's remote-change reload puts it back.
- Watch: `Reminders.swift` is not in any watch target. Not affected.
- Stored data and upgrade: no defaults key or model change. Pending requests from older builds use only the five IDs in `ownedIDs`, so none are orphaned.
- Notifications: triggers and content (`request(for:)`, `:252-270`) unchanged, so the call 5 calendar trigger stands. Delivered notifications were never touched, before or after.
- Entitlements, trials, paywall, onboarding, prices: not touched.
- Undo and edit paths, day and time zone changes: they reach `reschedule` only through `publish()`. The plan inputs are unchanged.
- Localized text, iPhone Duo layouts, views: no strings and no views changed.
- Tests: `centerOverride` is reset in a `defer` (`StateMachineRegressionTests.swift:169`), and setUp/tearDown reset `defaultsOverride` and `lastPlanned`, so no state leaks into other tests.

## Scope

One fix, for one review claim, in `Reminders.reschedule` plus a test seam. It needs no backend, App Store Connect or RevenueCat change. Nothing stored is cleared. It changes no data format and touches no held item. Every in-scope review claim is in the fixes table: B2, B1, B4, product calls 5 and 6. B3 and B5 are NOT A BUG, and product calls 1 to 4 were ruled fair or documented by the review.

## Must change

Nothing blocks this.

## Tests

Command: `gh-sim test --scheme Baby` (iOS 27.2 simulator, Xcode 27.1, GitHub's Macs).

- Full suite on HEAD `861c57c1`: `baby@20261107-020629-c2f0-claude-imacae52-1107-021005-10360`, GitHub run `42362793607`. **296 passed, 0 failed, 1 skipped.** This matches the fixes doc's final run (`42354081212`, 296/0/1). The skip is the long-standing `WidgetCloudSyncTests.testSharedBabyWritesToTheSharedDatabase` ("needs a signed host app"). Both tests this change added pass on HEAD: `testALatePendingAnswerKeepsTheNewerFeedReminder` (0.015 s) and `testEveryPlannedReminderIsOneANewPlanClears` (0.012 s). Nothing newly failed and nothing failed from infrastructure, so no reruns were needed.
- Revert proof: GitHub run `42365876331`, above.

## Screens

No view changed in this diff, so there was no `gh-sim launch`.

## Notes

- The committed `testALatePendingAnswerKeepsTheNewerFeedReminder` checks that removal now happens in line, by counting `remove` calls (`:181`, `:184`). On the old code it fails only at those preconditions, never at `:186`. It would catch someone moving removal back into a callback, but it does not itself reproduce a late answer. The behaviour proof is the fixer's ad hoc run `42351331828` and my scratch run `42365876331`. A stronger committed test would give `Center` a pending query and let the fake hold it, as the scratch test does. Recommended, not required.
- Device check left open: on a real phone, two plans that differ inside one notification-center round trip leave `baby.feed` pending. This is hard to trigger by hand. The likeliest routes are the Settings checkup date wheel or two quick reminder control changes, each of which starts an `apply` Task (`RemindersView.swift:273-279`), and a reload at launch racing a CloudKit import. On a device it would mean reading `getPendingNotificationRequests` after such a burst. The simulator run used a fake center, so the daemon's in-order handling of remove then add is assumed, not observed. The fix keeps removed and added IDs disjoint, so order does not matter for correctness.
- If `typicalCheckupDays` ever changes, requests pending under old day IDs on upgraded phones would no longer be cleared, because the old prefix filter is gone. `testEveryPlannedReminderIsOneANewPlanClears` keeps `ownedIDs` in step with what is planned, but not with what earlier builds planned. Any such change should keep the old IDs in `ownedIDs`.
- `centerOverride` is a test seam in shipping code, `nonisolated(unsafe)` like the existing `defaultsOverride` (`Reminders.swift:102`). It matches the file's idiom.
- The fixes table's commit cell for call 6 holds the commit subject, not the hash. The hash is `814b13f8`.
