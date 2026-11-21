# Low bug fixes, 2026-11-20

Status of B3 to B8 from `2026-11-20-bug-ux.html` (B1 and B2 were fixed earlier the same day).
Branch `fleet/20261120-211106-0f99-claude`, base `5aea6d45`.

| Id | Title | Outcome | Commit | Proof | What changed |
|---|---|---|---|---|---|
| B3 | Partner on an older build sees Pump and custom entries as feeds | skipped | none | none | Known and accepted in `.claude/rules/interface.md` (both phones need the update). A warning means a new dialog with copy in five languages, or a minimum-version marker that needs a schema change: a product decision for Jack. |
| B4 | CSV time column uses the phone's display format | fixed | 9928c423 | `ClockBoundaryTests.testCSVTimeIsFixedTwentyFourHourInTheExportZone`: fails on base code (run `...-221621-12180`: got "5:05 AM"), passes now | Time column is fixed `HH:mm` (POSIX locale, Gregorian) in the same zone as the date column. |
| B5 | Birth date moves a day beyond 12 hours from where it was entered, and Settings rewrites it | fixed | 84c7eaaa, b0c63d8d | `ClockBoundaryTests.testBirthDateKeepsItsCalendarDayInEveryZone`, `testBirthDatesStoredAsLocalNoonStillReadAsTheirDay`, `testBirthStampRoundTripsInAnyZone`, `testBirthDateKeepsItsCalendarDayAtTheDayEdges` (new API, so no base run; the catalog's Tokyo and Los Angeles repro tests were never in the repo); full suite `...-231119-11410` | Birth date is stored as noon UTC of its calendar day and read back through `DateHelpers.birthDay` (UTC day of stored + 1 hour, which also reads earlier noon-in-entry-zone values). Settings compares days, not instants, so opening it writes nothing. No schema change. b0c63d8d does the same for the example report's birth date. |
| B6 | 2 AM day start drops yesterday's 2:00 to 3:00 entries on spring-forward morning | fixed | 4a05683b | `ClockBoundaryTests.testTwoAMWindowKeepsYesterdaysTwoAMOnSpringForwardMorning`, `testSpringForwardEntryAtTwoThirtyYesterdayIsCountedInTotals`: both fail on base code (run `...-221621-12180`), pass now | `TotalsWindow.interval` steps back a day before setting the start hour. |
| B7 | Undoing the first Feed still raises and uses up the reminder offer | fixed | 82fe6d66, b87343d6 | `StateMachineRegressionTests.testUndoingTheFeedBeforeTheOfferCancelsTheOneTimeOffer` plus control `testTheOfferStillAppearsForAFeedThatStays`; full suite `...-212828-24146` | The offer task re-checks at fire time that the feed it came from is still in the log. `FeedSidePrompt` takes an injectable delay and gate for tests. |
| B8 | Day N does not roll over at midnight (Watch Today, widgets, Now with non-midnight start) | fixed (the trigger was plausible; the tests show it) | e778adae | `StateMachineRegressionTests.testDayOfLifeStepsForwardAtMidnightWithoutANewPush`, `testDayOfLifeStepsAtMidnightEvenWithASixAMTotalsDay`, `testASummaryFromAnOlderBuildStepsFromWhenItWasMade`; full suite | `NowSummary` records the day `dayOfLife` was counted on (optional field, older summaries fall back to `generatedAt`); `current(now:)` and Now derive the number from `now`. |

## Verification

- Final green full-suite run: `baby@20261120-211106-0f99-claude-imaceb66-1120-231119-11410`, at b0c63d8d: 320 passed, 0 failed, 1 skipped.
- The one skip is `WidgetCloudSyncTests.testSharedBabyWritesToTheSharedDatabase` ("needs a signed host app"). It is skipped by the test itself, not by this work.
- Tests failing on the base commit too: none. B4 and B6 were run against the old code on purpose (run `...-221621-12180`, `--only BabyTests/ClockBoundaryTests`) and failed as expected: 3 of 31.
- Tests changed: `testBirthDateStoredAtNoonKeepsItsCalendarDay` encoded the old local-noon storage; replaced by `testBirthDateKeepsItsCalendarDayAtTheDayEdges`. Its intent (day edges and DST days keep their day) is kept.
- B7 and B5 had no failing-before run: their tests use APIs the fix adds. B7's control test covers the offer path.

## For the reviewer

- B5 storage choice: `birthDay` reads the UTC day of `stored + 1h`. It reads every earlier-build value from Hawaii (UTC-10) to Tonga (UTC+13) correctly. Samoa and Niue (UTC-11), Chatham in daylight time and Kiribati's Line Islands (UTC+14) entered by an older build can still read one day off. Rewriting the same day (any name save) moves the stored value to UTC noon.
- B5 touches `EventStore.update` callers: name-only saves and `finishSetup` now pass `child.birthDay` (a local day), which `birthStamp` turns back into UTC noon.
- Not changed: the Android port. Its CSV time column still uses the phone's locale (`Format.time`) and its birth date handling is its own. `GoldenParityTest.csvMatchesIOSExceptTheDateColumn` compares against the saved `golden.json`, so it still passes, but regenerating the golden from the iOS tool (needs a Mac) would now differ in the time column.
- Old builds on a partner's phone read the UTC-noon birth date correctly within 12 hours west and 11 hours east of UTC; further east they read one day later, as before.

## Needs Jack

- B3: whether to warn on turning on Pump or a custom button in a shared log, or add a minimum-version marker (the marker needs a schema change and a CloudKit Production deploy).
- Android CSV time parity with iOS (decide whether to change Android and regenerate the golden on a Mac).
