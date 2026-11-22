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

## Android parity (2026-11-21)

Android code only; no iOS file changed. Settles the "Android CSV time parity" item under Needs Jack and the "Not changed: the Android port" note above.

| Item | Android had it? | Evidence | Commit | Tests |
|---|---|---|---|---|
| B4 CSV time column | Yes | `SummaryReport.csv` wrote `Format.time(start, zone, locale)`, the phone's locale format | 0e4a8820 | `CsvTimeTest` (6 locales, same zone as the date), `GoldenParityTest.csvMatchesIOS` |
| B5 birth date shifts a day | Yes, and worse (any zone west of entry, not only 12 hours) | The birth date was stored as `dayStartOf(date, zone)` (local midnight, `SettingsScreen.kt`, `OnboardingScreen.kt`) and read with `localDate(birthDate, zone)` in `DateHelpers.dayOfLife` and `dateForDayOfLife` | 48355f0a | `BirthDateTest` (11 zones from UTC-11 to UTC+14) |
| B5 Settings rewrites it on open | No | Nothing in `SettingsScreen` writes on open; `updateChild` runs only from the Born toggle, the name Save and the date dialog's Done, and the name save passes `child.birthDate` back untouched | none | `BirthDateTest.readingABirthDateWritesNothing` |
| B6 2 AM day start on spring-forward morning | Yes | `TotalsWindow.interval`: `today.minusDays(1)` after `withHour(startHour)` pushed `today` to 3:00 | a9325796 | `ClockBoundaryTest` |
| B8 Day N does not roll over | Yes on the home screen, no widgets | `NowSummary.dayOfLife` was a value stored at `make` time, shown by `LogScreen` (`summary.dayOfLife`). The screen's `now` ticks but the number did not. Android has no widgets (no Glance or AppWidget code) and no Watch | 9f2b030f | `ClockBoundaryTest.dayOfLife*` |

What changed:

- CSV: `Format.csvTime` writes fixed `HH:mm` (`Locale.ROOT`, ASCII digits) in the date column's zone. `golden.json` could not be regenerated here (the exporter needs Swift 5.9 for the iOS sources; this Mac has 5.7), so its time column was converted by hand from `h:mm a` to `HH:mm`, which is what the iOS code now writes for the same events. The test is renamed `csvMatchesIOS` (was `...ExceptTheDateColumn`) and now compares every column. The old comment that iOS writes the date in UTC was stale: iOS formats it in the same zone as the time and the golden's date column is local, so the date column is compared too. `.claude/rules/android.md` is updated to say so.
- Birth date: stored as noon UTC of the calendar day (`DateHelpers.birthStamp`), read with `DateHelpers.birthDay`, displayed with `Format.birthDate`. A value that is not exactly noon UTC came from an earlier build (local midnight) and is read in the phone's current zone, as before, so existing logs keep their day on the phone that entered it. A legacy midnight that falls on exactly 12:00 UTC (UTC+12 standard time, e.g. New Zealand winter) is read as the day before until the date is saved again.
- Day start: steps back a day before setting the hour, as iOS does.
- Day N: `NowSummary` keeps `birthDate` and `dayOfLife(now, zone)` counts from the time it is read.
- Next checkup: stored as noon UTC of the picked day (`DateHelpers.birthStamp`) and read with `birthDay`, so the visit and the evening-before note keep the picked day in any zone; a value that is not exactly noon UTC is read as before in the phone's zone; `NextCheckupTest` (LA entry read in Tokyo, Auckland, London, Honolulu, legacy value), 78 tests passed via gh-gradle `testDebugUnitTest assembleDebug`.

Tests (`gh-gradle`, fm-gradle is not installed on jmbp; public snapshot, GitHub Linux, JDK 17):

- Before the fixes (base `82734e0a` plus the new CSV and day-start tests): 61 passed, 5 failed. The failures are the new tests: `CsvTimeTest.timeAndDateAreInTheSameZone` ("11:45 PM"), `CsvTimeTest.timeIsTwentyFourHourInEveryLocale` ("5:05 AM"), `GoldenParityTest.csvMatchesIOS` ("2:05 PM" against "14:05"), `ClockBoundaryTest.twoAMWindowKeepsYesterdaysTwoAMOnSpringForwardMorning` (3:00 instead of 2:00) and `springForwardEntryAtTwoThirtyYesterdayIsCountedInTotals` (0 feeds, expected 1). Run `baby-before-mbpro35897-1121-004806-27841`.
- B5 and B8 tests use new API (`birthStamp`, `birthDay`, `dayOfLife(now, zone)`), so they have no failing-before run, as on iOS.
- After all four fixes: `testDebugUnitTest assembleDebug`, 74 passed, 0 failed, 0 skipped, debug APK builds. Run `baby@20261121-004421-ca22-claude-mbpro35897-1121-005103-26296`.
- Not run: instrumented tests (no emulator on this run), a manual check on a device.

Not changed: the iOS exporter's golden values other than the CSV time column; the "Next checkup" date in Settings > Reminders, which is a local-midnight instant in the zone it was entered and shows the same class of one-day shift when the phone changes zones (not in the iOS fixes, not touched here).

## Next checkup date (iOS, 2026-11-21)

Found in the Android parity pass: the "Next checkup" date in Reminders was stored
as the picker's moment, so a trip across time zones could move the visit and its
evening-before reminder to another day. iOS now stores it as noon UTC of the
picked day, like the birth date, and reads values from earlier builds as stored.
Tests: `ClockBoundaryTests.testCheckupDateKeepsItsCalendarDayAcrossZones`,
`testCheckupDateFromAnEarlierBuildReadsAsStored`; ClockBoundaryTests and
RemindersTests, 48 passed, on a local simulator.
