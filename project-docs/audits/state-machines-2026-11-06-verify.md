VERDICT: PASS

# Verification of the state machine fixes, 2026-11-06

Independent check of `state-machines-2026-11-06-fixes.md` against `state-machines-2026-11-06-review.md` and the audit. Read the whole change `git diff 87e34cb7..HEAD` (branch `fleet/20261106-185452-4a9d-claude`, HEAD `bab7f5a5`): fix commits `bc1b1830` (B2), `a5a39a37` (B1 and B4), `d1a3ad59` (product call 5), doc commit `a1c7c8c0`; `bab7f5a5` is an empty fleet snapshot. No app code or tests were changed here.

## Fixes

| id | works | regression check | evidence |
|---|---|---|---|
| B2, Last 24 hours totals on widgets, complications and the Watch never age out | yes | clean | Route: Settings > Daily totals > Last 24 hours, then read a widget, complication or Watch Today between taps. `NowSummary.make` now records each counted feed and diaper (`NowSummary.swift:226`, `:260`); `current(now:)` routes through `resetTodayIfNeeded`, which now ages them out (`:477`, `agingOut` at `:489-503`). Every consumer reads through `current(now:)`: Home widget and one-button tiles per 5 minute entry (`BabyWidget.swift:51`, the tiles share `BabyProvider`, `QuickLogWidgets.swift:176`), complications per entry (`ComplicationViews.swift:45`), Watch Today per `TimelineView` tick (`WatchTodayView.swift:10`). Wrist taps append (`:331`, `:340`) and wrist Undo removes (`:410`), so pending replay stays consistent. Test `testLast24HoursDropsAFeedOnceItIsOlderThanADay` asserts its preconditions (2 counted when made, 1 from a fresh summary 10 h later) and fails without the fix (revert run below: `("2") is not equal to ("1")`, the audit's original failure) |
| B4, Settings reminder footer stays "Notifications are off" after the parent allowed them | yes (code path; the visible half needs a device) | clean | Route: Settings > Reminders > interval > Don't Allow > "Allow notifications in Settings" > allow > back. `scenePhase == .active` calls `events.returnToForeground()` (`App.swift:112`), which posts `Reminders.foregrounded` (`EventStore.swift:184`, name at `Reminders.swift:81`); the mounted `RemindersSection` rereads `isDenied` on it (`RemindersView.swift:246-248`), and both the footer and the Allow button key off `isDenied`. Settings stays mounted across tabs (review, `App.swift` retained tabs), so this is the only refresh on the route. Test `testReturningToTheAppAsksSettingsToReadPermissionAgain` asserts only the post, not the view's reread; it fails without the fix (unfulfilled expectation). The simulator cannot change notification permission, so the footer itself is unproven on screen, as the fixes doc says |
| B1, foreground pass does not hand the reminder plan over with an unchanged log | yes | clean | Same route. `returnToForeground` forgets the plan, reloads, then calls `Reminders.reschedule` directly when not standing in (`EventStore.swift:180-185`), so the plan is handed to the notification center even when `refresh` skips `publish()` (`EventStore.swift:233`). When `publish()` did run, the second call computes the same plan and stops at `Reminders.swift:221`. Test `testReturningToTheAppHandsTheReminderPlanOverWithAnUnchangedLog` asserts its precondition (the tap planned `baby.feed`) and fails without the fix (`("nil") is not equal to ("Optional(["baby.feed"])")`) |
| Product call 5, checkup note keeps the old zone's 7 pm after travel | yes | clean | Checkup items now get a `UNCalendarNotificationTrigger` from year, month, day, hour and minute with no zone (`Reminders.swift:240-246`), so the note fires at 7 pm local on that date; the feed reminder stays a time interval (`:248`). Planned dates and ids are unchanged, so `lastPlanned` comparisons and the `baby.checkup.*` replace-in-place still hold, and an upgraded install replaces its pending interval triggers on its first reschedule (new process, `lastPlanned` nil). Test `testACheckupNoteIsAWallClockTimeThatFollowsTheTimeZone` fails without the fix (`XCTUnwrap failed: expected non-nil value of type "UNCalendarNotificationTrigger"`) |
| Product call 6, remove-in-completion race in `reschedule` | skipped, accepted | n/a | See Disputed and skipped |

## Revert proof

Throwaway branch `scratch-revert` (deleted afterwards; this branch ends with only the verify doc commit on top of `bab7f5a5`). `Shared/Services/NowSummary.swift`, `EventStore.swift`, `Reminders.swift`, `Baby/App.swift` and `Baby/Views/RemindersView.swift` were restored from `87e34cb7`, tests kept, plus only the seams the tests need to compile: an unpopulated `counted` property and `CountedEntry`, the `foregrounded` name, `lastPlanned` as `private(set)`, `request(for:now:calendar:)` made internal with its old interval trigger, and `returnToForeground()` doing exactly the old `App.swift` pass (`forgetLastSchedule()` then `reload()`).

Run `baby@20261106-185452-4a9d-claude-mbpro35a47-1106-195047-29018`, GitHub run `42335820812`, `--only BabyTests/StateMachineRegressionTests --only BabyTests/RemindersTests/testACheckupNoteIsAWallClockTimeThatFollowsTheTimeZone`: 8 run, 7 failed, 1 passed.

- B2 `testLast24HoursDropsAFeedOnceItIsOlderThanADay`: failed at line 68, `("2") is not equal to ("1")`, preconditions at 64 and 67 held.
- B4 `testReturningToTheAppAsksSettingsToReadPermissionAgain`: failed, notification `baby.reminders.foregrounded` never posted.
- B1 `testReturningToTheAppHandsTheReminderPlanOverWithAnUnchangedLog`: failed at line 131, precondition at 126 held.
- Call 5 `testACheckupNoteIsAWallClockTimeThatFollowsTheTimeZone`: failed at line 125.
- Also failed as expected: `testLast24HoursDiapersAgeOutAndMatchTheWatchList`, `testAWristTapUnderLast24HoursAgesOut...`, `testASummaryFromAnOlderBuildStillDecodes` (its last assertion needs `make` to fill `counted`).
- Control `testDayWindowStillClearsAtTheNextDay` passed, as it should.

## Regression read

- **Stored data after upgrade.** `counted` is an optional, additive Codable field (`NowSummary.swift:50`); synthesized decoding uses `decodeIfPresent`, so cached `nowSummary`, the Watch's `phoneSummary` and pushed contexts from older builds decode unchanged and keep the old behaviour (`agingOut` guards on `counted` nil). An older Watch ignores the unknown key (default `JSONDecoder`). Test `testASummaryFromAnOlderBuildStillDecodes` covers it. No Core Data model change, no CloudKit schema change, nothing cleared.
- **Day windows and time zones.** `counted` stays nil for day windows (`:226`), so the day rollover path is byte for byte the old one, and the control test passes. Last 24 hours is an absolute interval, unaffected by zone. The `generatedAt`-out-of-window reset still zeroes counts and now empties `counted` (`:482`).
- **Watch.** `WatchStore.refresh` and `init` use `applyingPending`, which runs `resetTodayIfNeeded` before and inside each replay; aging is idempotent (filters `counted`). `knownEventIDs` still blocks double replay before anything is appended. Wrist Undo only subtracts entries still in the window, which now matches `counted`. The Watch target builds in the `Baby` scheme (`project.yml` scheme `Baby` builds `BabyWatch: all`), and the full suite built.
- **Widgets.** The widget makes its own summary (`BabyWidget.swift:64`) so `counted` is filled there too; `Timeline(.atEnd)` after 12 five-minute entries is unchanged. Widget Undo and `LogEventIntent.rescheduleReminders` (`AppIntents.swift:172-174`) go through the same `reschedule`, now with calendar triggers for checkup notes.
- **Publish churn.** `counted` is part of `Equatable`, so `sameContent` (`EventStore.swift:214`, `:228`) sees it. Under Last 24 hours it only changes when an entry is added, removed, edited or ages out, all of which already changed the counts or `recent`, so no extra widget or Watch reloads.
- **Notifications.** `returnToForeground` never asks for permission (`reschedule` only adds), so no new prompt appears on launch or onboarding. A foreground now re-adds the same pending requests even when nothing moved; same identifiers replace in place, and past due feed reminders and past checkup evenings are not planned (`Reminders.swift:151`, `:172`, `:184`), so nothing delivered is re-sent. Standing in before first unlock is still guarded (`EventStore.swift:183`). Checkup notes still carry `userInfo[route] = checkup`, so the tap routing to Upgrade or Reports is unchanged.
- **Entitlements and trials, undo and edit, onboarding, localized text, iPhone Duo.** No diff touches `StoreService`, the paywall, onboarding, `PlusFeature`, the editor or undo flows. No new user-facing string (the Settings change adds only an `.onReceive`). Duo panes host the same `RemindersSection`; each mounted copy rereads on the post.
- **Android.** `scripts/android-golden` compiles `NowSummary.swift` and `Reminders.swift` but exports only counts and lines from `make` (`main.swift:94-103`), which did not change; no golden file needs a rerun.

## Scope

- All five in-scope review items are in the fixes table (B2, B4, B1, calls 5 and 6). B3 and B5 were NOT A BUG and calls 1 to 4 fair or documented; none was touched.
- No change to prices, offers, how membership is judged, a trial or onboarding flow, or when or to whom a paywall appears. Call 5 changes when a checkup note arrives after travel, back to the documented 7 pm the evening before; the paywall still opens only on tapping that note, for the same people.
- No backend, App Store Connect or RevenueCat change. Nothing is cleared on an inferred state. No stored format reset. Nothing held.
- Call 5 was not an UNVERIFIED claim (the review reclassified it as a real defect from the code), and its test now has a failing run on the reverted code above.

## Disputed and skipped

The fixes doc has no Disputed section, so there is nothing to rule on there. Its one skip:

- **Product call 6, skipped as not reachable as a lasting fault: upheld.** It needs two differing plans inside one `getPendingNotificationRequests` round trip. In the app, the only plan-flipping inputs are human taps, and the new foreground pass plans twice from one summary, so the second call stops at `Reminders.swift:221`. Across processes a widget feed's save posts `NSPersistentStoreRemoteChange`, the running app refreshes, its summary changes and `publish()` hands over a plan that differs from its last one, so a removed `baby.feed` is added straight back; a suspended app plans nothing. The review itself called it unproven and needing two plans inside one callback's latency, and a fix would have been a change for an unproven claim with no failing test. A residual window (the app suspended between its completion and the remote change) is narrower than anything a test can reach.

## Must change

Nothing.

## Tests

`gh-sim test --scheme Baby`, iOS 27.2 simulator, Xcode 27.1, on GitHub's Macs.

- Full suite on HEAD: `baby@20261106-185452-4a9d-claude-mbpro35a47-1106-185530-1545`, GitHub run `42331572794`. **294 passed, 0 failed, 1 skipped.** Matches the fixes doc's final run (`42326906808`: 294 passed, 0 failed, 1 skipped) and its baseline of 286 plus the 8 new tests. The skip is the pre-existing `WidgetCloudSyncTests.testSharedBabyWritesToTheSharedDatabase` ("needs a signed host app"). No new failure, so no rerun was needed.
- Revert proof: GitHub run `42335820812`, above.
- Screens: GitHub run `42339759286`, see Notes.

## Notes

- Screens: `gh-sim launch`, run `baby@20261106-185452-4a9d-claude-mbpro35a47-1106-204436-20801`, GitHub run `42339759286`, on HEAD with `-SeedScreenshotData -NoCloudKit`. The Log screen (`shots/launch.png`) renders normally: last feed, Start on Right, the four buttons and Today's totals (2 feeds, 2 pee, 1 poop). The Settings stack (`-ScreenshotTab 1`, `shots/screen1-...png`) opens on First Weeks and renders normally. The changed view, Settings > Reminders, cannot be reached by a launch argument (no route scrolls to it), and its visible change only appears after a notification permission change the simulator cannot make. The diff adds no layout to it (only `.onReceive`, `RemindersView.swift:244-248`). Widgets, complications and the Watch Today page, where B2 shows, are not reachable from `gh-sim launch`.
- The fixes doc cites commits `2b6621a`, `54f94ff`, `8e829f2` and base `95553e6` from another branch; none exists here. The same changes are `bc1b1830`, `a5a39a37`, `d1a3ad59` on `87e34cb7`. Stale hashes only.
- B4's test proves the post, not the reread in `RemindersSection`; a device check (deny, allow in iOS Settings, return) is still the only proof of the footer. Not a failure: the reread is two lines and reads directly off the post.
- `testAWristTapUnderLast24HoursAgesOutAndItsUndoIsNotSubtractedTwice` undoes the tap before it ages, so the "not subtracted twice" half of its name is not exercised (aging then Undo). The code handles it (`NowSummary.swift:400-410` only subtracts entries still in the window), but the test does not prove it.
- B4 and B1 tests call `Reminders.forgetLastSchedule()` before `returnToForeground()`, which already forgets; harmless.
- The Watch Today list is capped at 24 `recent` entries while `counted` is not, so on a heavy day the count can exceed the rows under it. That was true before and is outside B2.
- Checkup calendar triggers use the current calendar for their components (`Reminders.swift:245`); `UNCalendarNotificationTrigger` reads unspecified-calendar components in the current calendar too, so non-Gregorian calendars (Buddhist, Japanese) stay consistent. After an eastward trip that puts local time past 7 pm on the evening before, the note no longer fires (it used to fire late); that is the wall-clock behaviour the review asked for.
- The project rules ask for a `project-docs/README.md` index line for every doc; this task allowed only this file in the commit, so the index line for this verify doc is left to add.
