# State machine audit, 2026-11-06

Audited commit `54f9833` (branch `fleet/20261106-114420-a212-claude`, clean tree, `git stash -u` found nothing to stash). Scope: the iOS app, `Shared/`, the widget, the Watch and the Watch widget. No backend function gates entitlements (RevenueCat is the only authority), so none was read. Android is out of scope. Nothing was fixed.

**Summary: 2 bugs proved by test, 3 bugs code path only, 6 product calls (not counted).** No bug was found in the entitlement, trial or purchase machine (read, and reasoned against, not run; see M8).

Evidence runs (`gh-sim test --scheme Baby --only BabyTests/StateMachineAuditRepro`, iOS 27.2 simulator, Xcode 27.1):

- Run 1, `baby@20261106-114420-a212-claude-mbpro355c1-1106-114947-17837`: Last 24 hours claim failed as asserted, control passed. The two first-draft reminder claims and the offer claim failed their own preconditions (the simulator has no notification permission to grant, and `ReminderOfferGate` is closed in unit tests), so they were rebuilt or demoted.
- Run 2, `baby@20261106-114420-a212-claude-mbpro355c1-1106-121618-16754`: 2 passed (both controls, `testControlSummaryChangeReachesPublish` and `testControlDayWindowClearsAtTheNextDay`), 2 failed as asserted, every precondition held. B1: `XCTAssertGreaterThan failed: ("1") is not greater than ("1") - reload() with an unchanged summary never reached publish()`. B2: `XCTAssertEqual failed: ("2") is not equal to ("1")`.

Repro suite: `state-machines-2026-11-06-repro.swift` (class `StateMachineAuditRepro`, goes in `BabyTests/`).

## Bugs, ranked by impact

Impact is users reached times cost. Both proved bugs are small. Nothing here loses data or money.

| id | bug | what the user sees | promise | user route | impact | evidence | file:line |
|---|---|---|---|---|---|---|---|
| B1 | Foreground reconcile of reminders is a no-op | After allowing notifications in iOS Settings (or after iOS dropped a request), the feed reminder for the last feed is never handed over; the phone stays silent until the next feed, diaper or sync changes the summary | `Reminders.swift:203-204`: "notifications can be allowed in Settings meanwhile, so the next pass hands the plan over again". `App.swift:112-113` calls `forgetLastSchedule()` then `reload()` for exactly this | Settings > Reminders > Feed reminder "Every 3 hours" > Don't Allow on the iOS prompt > footer "Notifications are off..." > tap "Allow notifications in Settings" > Allow > back to Baby Tracker (app returns to foreground) > no log taps > the 3 hour mark passes with no notification | Parents who first declined, then allowed, with a feed already logged. Loses one reminder (the one counting from the last feed); the next logged feed schedules normally. Low users, one reminder each | Test (run 2). The seam is `LiveActivityService.sync`, which sits in the same `publish()` block as `Reminders.reschedule`: it read the client once after the feed tap and once more after the control's diaper tap, but not after `forgetLastSchedule()` plus `reload()`. The simulator cannot grant or deny notifications, so the half where `center.add` failed under a denied permission is read from the code, not run | `EventStore.swift:223` (`if summaryChanged \|\| !hasPublished { publish() }`), `EventStore.swift:359-363`, `App.swift:112-113`, `Reminders.swift:212-229` |
| B2 | "Last 24 hours" totals on the Watch (Today page, complications) and widgets never roll an old entry off | Watch Today shows 8 feeds while the list under it shows 7 rows; the count stays one too high until the next phone push | Settings > Daily totals "Last 24 hours" and the Watch heading `TotalsWindow.title` "Last 24 hours" (`NowSummary.swift:646`, `title`); `NowSummary.swift:28` says the Watch resets "at the same hour the phone does" | Settings > Daily totals > Last 24 hours; log feeds over a day; leave the phone idle past the age-out of the oldest feed (about 3 to 4 hours between taps); open the Watch Today page: counts include a feed now over 24 hours old, rows (`recentInWindow`) do not | Parents on Last 24 hours with a Watch, an unusual setting, over-count by 1 until the next log, every few hours. Cosmetic number, no data loss | Test (runs 1 and 2, same failure `("2") is not equal to ("1")`; control passed; preconditions asserted that the made summary counts 2 and a fresh summary at +10 h counts 1) | `NowSummary.swift:458-473` (`current` / `resetTodayIfNeeded` only resets when `generatedAt` leaves the window), `NowView.swift:72` (the Now clock excludes `.last24Hours` from its rollover reload), `WatchTodayView.swift:10`, `ComplicationViews.swift:45`, `BabyWidget.swift:51` |
| B3 | The one-time reminder offer still opens after its feed was undone | "Remind you about the next feed?" appears 6 seconds after a feed that is no longer in the log; because `hasOfferedFeedReminder` is set on appear, a real first feed never gets the offer | `RemindersView.swift:72` "Offered once, a few seconds after the first feed is logged"; AGENTS.md "a sheet six seconds after a feed is logged" | Log tab > Feed (the first feed ever, so no earlier offer) > Undo on the toast inside 6 seconds > wait; sheet opens over Log | Brand new installs that mis-tap Feed on their first feed and Undo fast, once per install, but the lost offer is permanent. Few users; the offer is also reachable later from Settings > Reminders | Code path. Settle with a UI test: `-ShowReminderOffer`, tap Feed, tap Undo, wait 7 s, expect no `reminderOffer.accept` | `LogButtons.swift:256-259` (`close()` leaves `reminderOffer` running), `LogButtons.swift:273-280`, `Components.swift:185` (Undo never tells the prompt), `RemindersView.swift:107-108` |
| B4 | Settings' reminder footer and "Allow notifications in Settings" button go stale after permission changes in iOS Settings | Footer keeps saying "Notifications are off for Baby Tracker, so these can't arrive." after the parent allowed them | Same footer string, `RemindersView.swift:258` | Same route as B1 up to the return to the app, then look at Settings > Reminders (the Settings tab is retained in the `ZStack` of visited tabs, `.claude/rules/interface.md`, so `.task` at `RemindersView.swift:236` does not run again). Changing the picker refreshes it | Same small population as B1; the cost is a parent who believes reminders are broken. Rank just under B1 | Code path. Settle with a UI test or a device: deny, allow in iOS Settings, return, read the footer | `RemindersView.swift:236`, `242`, `271`, `Baby/App.swift` (retained tab `ZStack`) |
| B5 | A feed reminder can fire after the baby was fed by someone else, if this phone's app never ran the import | "2½ hours since Nora's last feed" notification arrives 20 minutes after the other parent fed her | `Reminders.swift:209-211` doc "Replaces this phone's pending reminders with the ones the summary and the stored choices call for"; AGENTS.md "The app reschedules on every summary change" | Two phones on Log together, both with a 2½ hour reminder; parent A logs a feed at 2:10 pm while parent B's phone has the app force-quit (silent pushes are not delivered to a force-quit app) or in Low Power Mode; B's pending note from the 12:00 feed fires at 2:30 pm | Log together users with reminders on and the receiving app not woken. Unknown share of two-parent households; cost is one false nudge. Only a device can measure it | Code path. Needs two real iCloud devices: `remote-notification` is in `UIBackgroundModes` (`Info.plist:39-42`), so a normal background import does reschedule; the claim is only the force-quit and low-power cases | `Reminders.swift:212-229`, `EventStore.swift:359-363`, `Info.plist:39-42` |

B3 to B5 are never claimed as proved.

## Product calls (not counted)

No promise was found that the code contradicts, so these are choices for Jack.

1. A running sleep or feed timer survives its button being turned off and returns after turning it on (`NowSummary.make` filters by `tracked`; `TrackedKinds.swift:4-6` says entries "come back"). A timer left open for two days returns as "Asleep 2d 1h" with no cap or prompt. Nothing auto-closes any running row.
2. A visit date the parent entered is dropped once it is not in the future (`Reminders.swift:168`: `nextCheckup > now`), after which `checkupReminders` falls through to the birth-date schedule (days 4, 14, 30). The past date also stays on in Settings' picker.
3. The feed reminder counts from the feed start, ignores sleep, and fires while the baby sleeps (documented: "counted from when the last feed started").
4. A Live Activity the parent swipes away returns on the next foreground (`App.swift:109-118`, `LiveActivityService.swift`), by design ("retries on every foreground").
5. Checkup notes are time-interval triggers computed in the zone at scheduling time (`Reminders.swift:238`). After travel the "7 pm" note arrives at 7 pm in the old zone until the next summary change reschedules it. Nothing observes a time zone change.
6. `reschedule` removes stale requests in a `getPendingNotificationRequests` completion, while the adds go out at once (`Reminders.swift:219-228`). A call that plans nothing followed quickly by one that plans a feed could let the first completion remove the second's request. Needs two publishes within milliseconds, which no single tap produces. Unproven.

## Related fixes, in order

Not applied.

1. B1 and B4 together: on `scenePhase == .active`, call `Reminders.reschedule` directly (not through `reload()`), and re-read `Reminders.isDenied()` into `RemindersSection` through `.onChange(of: scenePhase)`. One change fixes both.
2. B3: cancel `reminderOffer` in `FeedSidePrompt.close()` and when the event the prompt opened on is gone, and set `hasOfferedFeedReminder` only when the sheet shows.
3. B2: when the window is `.last24Hours`, have `current(now:)` recount from `recent` (the Watch already carries 24 entries) or have the phone push on the hour.
4. B5: no code fix without a measurement. Add a device test first.

## State machines

Invariants are named I1 and up inside each machine. A transition marked `breaks I#` is reachable and listed above.

### M1. Feed reminder (`Reminders`, `EventStore.publish`, `LogEventIntent`)

States, per phone: interval (off, 2h to 4h, in App Group defaults `reminder.feedMinutes`); `lastPlanned` (process memory only); pending request `baby.feed` (iOS); iOS authorization (not determined, allowed, denied, see M4).

- I1: a pending `baby.feed` exists iff interval is not off, a last feed exists, no feed timer runs, and the due time is more than 30 seconds away.
- I2: the pending body's side and time match the summary at the time of the last change.
- I3: `lastPlanned` equals what iOS actually holds.

| from | event | to | notes |
|---|---|---|---|
| none | feed logged (app, `EventStore.log`) | pending | `publish()` only when summary content changed |
| none | widget feed tap | pending | `LogEventIntent.rescheduleReminders` (`AppIntents.swift:105`), runs in the widget process with its own `lastPlanned` |
| pending | widget Undo of a feed | recomputed | `AppIntents.swift:441` |
| pending | app Undo, edit or delete of the feed | recomputed | summary changes, `publish()` |
| pending | feed button turned off | none | summary loses `lastFeedAt` |
| pending | other parent's feed, app woken | recomputed | CloudKit import then `reload` |
| pending | other parent's feed, app not woken | pending (stale) | breaks I2 (B5) |
| none (add failed: denied) | permission allowed in iOS Settings, app foregrounds | none | `forgetLastSchedule` then `reload()` never reaches `publish()`: breaks I3 and I1 (B1) |
| pending | time passes beyond due | delivered | iOS removes it; `lastPlanned` stays, so no rebuild until summary changes (harmless) |
| any | Settings picker change | recomputed | `RemindersSection.apply`, reads `isDenied` after |
| any | scenePhase active | `lastPlanned = nil`, `reload()` | the intended reconcile, but only effective when the summary moved |

Scheduler call sites (every one): `EventStore.swift:362` (`publish`), `AppIntents.swift:174` (`rescheduleReminders`, called at `:105` for a widget feed tap and `:441` for a widget feed Undo), `RemindersView.swift:152` (`FeedReminderOfferView.accept`), `RemindersView.swift:271` (`RemindersSection.apply`). The Watch and Live Activity Stop never reschedule (a Stop on a running feed goes through `EventStore.stopRunning` and `publish`).

### M2. Checkup reminders and routing (`Reminders.checkupReminders`, `AppRouter`)

States: `checkupRemindersOn`, `nextCheckup` (optional), birth date, pending `baby.checkup.*`, `AppRouter.showsCheckupPitch` and `checkupRequests`.

- I4: with notes on, one note at 19:00 the evening before the entered future visit, else one per typical day (4, 14, 30) that is still ahead.
- I5: `showsCheckupPitch` is true only while Reports is the selected tab after a tap.

| from | event | to |
|---|---|---|
| none | toggle on, date entered in future | one `baby.checkup.entered` |
| entered | visit date passes | `typical` schedule from birth date (product call 2) |
| any | zone change, no summary change | stale absolute time (product call 5) |
| any | note tapped | tab Reports, `showsCheckupPitch = true`; cleared when the tab changes (`App.swift:406-408`) |
| any | note tapped while onboarding shows | `checkupRequests` held; Home jumps to Reports when it mounts (`onReceive` replays the published value). Not harmful |

### M3. Reminder offer (`FeedSidePrompt`, `Reminders.hasOfferedFeedReminder`)

States: `hasOffered` (defaults), `showReminderOffer`, `reminderOffer` task, `target` (feed the chips edit).

- I6: the sheet opens only while a feed it follows is in the log.

| from | event | to |
|---|---|---|
| idle | feed or All tap | task queued 6 s, `target` set |
| queued | side tap | task re-queued |
| queued | Undo of the feed | queued (still fires): breaks I6 (B3) |
| queued | 90 s chip timeout | queued (fine) |
| queued | 6 s elapse | sheet shown; `hasOffered = true` on appear |
| shown | accept | interval and checkups saved even if denied, `reschedule` only when allowed |
| shown | swipe down | `hasOffered` already true, never offered again (documented: once) |

### M4. Notification permission (iOS) as the UI reads it

States: not determined, allowed (authorized, provisional, ephemeral), denied. `RemindersSection.isDenied` is a cache of `.denied`.

- I7: the footer and "Allow notifications in Settings" show iff the setting is denied and a reminder is on.

| from | event | to |
|---|---|---|
| not determined | picker or toggle on | system prompt, then `isDenied` re-read |
| denied | allowed in iOS Settings, return | `isDenied` stays true until a picker change or the offer: breaks I7 (B4) |
| allowed | denied in iOS Settings | footer appears only after the next picker change or reappearance of the section |

### M5. Timers and in-app Undo (`EventStore`)

States per baby: running feed rows, running sleep rows, `lastLogged` (8 s window, 32 s with VoiceOver), `WidgetUndo` (App Group).

- I8: at most one running row per kind after any in-app action (two can exist after two phones start the same sleep before syncing; one Wake ends all).
- I9: Undo takes back exactly the last action and what it closed.

| from | event | to |
|---|---|---|
| idle | Feed tap | feed row (ended = start), closes running feed rows that started earlier, `lastLogged` set |
| idle | All tap | feed plus wet plus dirty, one Undo (`alsoLogged`) |
| idle | Sleep tap | running sleep |
| running sleep | Wake tap | sleep ended; Undo reopens (`reopensTimer`) |
| any | delete | row removed, Undo restores with its id and values |
| any | 8 s | `lastLogged = nil` |
| any | new action in the window | `lastLogged` replaced; the earlier Undo is gone (by design, one level) |
| Wake just undone | partner already started another sleep | two running sleeps; one Wake ends both (tolerated by I8's note) |

Edits: `EventEditorView.applyEdits` writes only changed fields, keeps saved length to the second, and a new sleep cannot be logged at zero length. No invalid state found on the edit path.

### M6. Widget Undo (`WidgetUndo`, `UndoWidgetLogIntent`, `WidgetCloudSync`)

States: `WidgetUndo` stored in App Group, tile face (normal, Logged/Undo for 10 s), CloudKit record (direct, exported copy, tombstone).

- I10: Undo deletes only the stored `eventID`, and only within 60 s; a stale tile never clears a newer tap.

| from | event | to |
|---|---|---|
| none | one-button tap | event saved, `WidgetUndo` stored, reminders rescheduled for a feed |
| stored | tap again same kind inside 3 s | no-op (`isDoubleTap`) |
| stored | Undo inside 60 s | delete or reopen, `WidgetUndo` cleared, cloud delete queued, reminders rescheduled for a feed |
| stored | Undo after 60 s | cleared, nothing deleted |
| stored | app Undo of the same event | `undoLast` clears the widget copy |

No invalid transition found (the `closedIDs` reopen is bounded by the 60 s window).

### M7. Watch tap queue (`WatchStore`, `EventStore.apply`)

States: `phone` summary, `pending` payloads, `confirmation` (10 s), phone's `appliedWatchActions` (last 256 ids).

- I11: the wrist shows the phone summary with unacknowledged taps replayed.
- I12: an id applies once; an Undo of a not-yet-landed tap blocks it when it lands.

| from | event | to |
|---|---|---|
| any | tap | payload queued and replayed locally |
| queued | delivered | removed from `pending`; display refreshes on next summary |
| queued | Undo before landing | both sent; phone records the target as applied (`EventStore.swift` `case .undo`) |
| queued | baby gone on phone | acknowledged and dropped |
| any | `.last24Hours` window | counts do not age out: breaks I11 (B2) |

### M8. Entitlement, trial and purchase (`StoreService`)

States: `isConfigured`, `hasResolvedEntitlements`, `entitlementCheckFailed`, `isPro`, `isLifetime`, `packages`, `introEligibility` plus `introEligibilityResolved`, `isLoading`, `errorMessage`, `lastCustomerInfoDate`.

- I13: `isPro` is true iff the newest `CustomerInfo` (by `requestDate`) has any active entitlement.
- I14: trial copy shows only when eligibility is resolved and eligible.
- I15: every paywall state shows the billed amount, disclosure, Restore, Terms and Privacy (`PaywallView` ZStack and `plainDisclosure`).

| from | event | to |
|---|---|---|
| launch | `start()` | cached info applied, products loading, then `refreshStatus` and `loadOffering` |
| any | `customerInfo` older than the last | ignored (`update` guard) |
| any | delegate update | `isPro`, `isLifetime` recomputed, cached key written |
| eligible | `loadOffering` | `introEligibilityResolved = false` until recomputed (copy hides, never over-promises) |
| any | purchase | verifies status first; cancelled, pending (Ask to Buy message), purchased |
| any | restore | `isPro` or "No active Baby+ purchase" message |
| fetch failure | later success by delegate | `isPro` correct; `entitlementCheckFailed` stays true but only gates the loading spinner, which `isPro` and resolved flags already override |

Checked and not reproduced as defects: stale `requestDate` ordering, `.pending` purchases (message shown, later approval flips `isPro` through the delegate and closes the paywall), a failed status check then a purchase (retried first), loading and error states still carrying the disclosure. `AppGroup.Key.cachedPro` (`"isPro"`) is written but never read, so widgets and the Watch cannot gate on it; nothing depends on it. Trial eligibility is cached for the session and only refreshed on `loadOffering` and a failed purchase; a process alive for the whole 7 day trial would keep offering a spent trial (3.1.2), but iOS rarely keeps one process that long, so it is not counted. Not run against a fake `RevenueCatClient`; I did not construct `CustomerInfo` fixtures.

### M9. Live Activity (`LiveActivityService`)

States: `desired` from the summary, `revision`, one reconcile task. Invariant: at most one activity per baby, matching the running timer. Reconcile loops until the revision is stable. Foreground resync covers the iOS refusal to start in the background. No invalid transition found.

### M10. Persistence, join and share (`Persistence`, `EventStore`, `SharingService`)

States: stores open or stood in (`isStandingIn`, writes refused), `pendingSharedZone`, `lateSharedZone`, active baby, `arrivedSharedChild`. Invariants: never write while standing in, never delete a baby on join, only newest `refresh` writes `share`. Read only; no invalid transition found. `moveEvents` copies each entry with its id, deletes the source baby, and relies on `DuplicateEvents` for any widget copy.

### M11. Totals window and day change (`TotalsWindow`, `NowSummary`)

States: window (`day(startHour)` or `last24Hours`), `generatedAt`. Day windows roll over: Now (30 s clock reload), widgets (entries every 5 minutes, `current(now:)`), Watch (`TimelineView`, `current(now:)`). `last24Hours` rolls live only in Now's `WindowTotals`: B2.

### M12. Tabs and Settings retention (`HomeTab`, `ZStack` of visited screens)

Screens are mounted once visited and hidden by opacity, so view `@State` and `.task` survive tab changes. This is the cause of B4. The other retained screens (History, Reports) hold no `@State` copy of a setting that Settings edits.
