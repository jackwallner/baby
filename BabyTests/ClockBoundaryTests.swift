import CoreData
import XCTest
@testable import Baby

/// Day, window and timer boundaries driven by a fixed clock and an explicit
/// calendar (America/Los_Angeles), never the machine's. DST days: 2026-11-01
/// is 25 hours long, 2027-03-14 is 23.
@MainActor
final class ClockBoundaryTests: XCTestCase {
    private var persistence: Persistence!
    private var child: Child!

    private let la: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    override func setUp() async throws {
        persistence = Persistence(cloudKit: false, inMemory: true)
        child = Child.make(in: persistence.viewContext, name: "Nora", birthDate: nil)
    }

    private func at(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) -> Date {
        la.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    @discardableResult
    private func event(_ kind: EventKind, _ start: Date, until end: Date? = nil, sides: [FeedSide] = []) -> LogEvent {
        let event = LogEvent.make(in: persistence.viewContext, child: child, kind: kind, at: start)
        event.endedAt = end ?? (kind.canRun ? nil : start)
        event.feedSides = sides
        return event
    }

    private func hours(_ seconds: TimeInterval) -> Double { seconds / 3_600 }

    // MARK: - Sleep across midnight

    // fed929e5: a sleep is credited to the day it happened in, split at midnight.
    func testSleepThroughMidnightSplitsBetweenTheTwoDays() {
        let sleep = event(.sleep, at(2026, 7, 21, 22), until: at(2026, 7, 22, 2))
        let now = at(2026, 7, 22, 9)
        let before = DayTally.make(events: [sleep], on: at(2026, 7, 21), now: now, calendar: la)
        let after = DayTally.make(events: [sleep], on: at(2026, 7, 22), now: now, calendar: la)
        XCTAssertEqual(hours(before.sleepSeconds), 2, accuracy: 0.001)
        XCTAssertEqual(hours(after.sleepSeconds), 2, accuracy: 0.001)
    }

    // fed929e5: a timer still running stops counting at now, so the minutes on
    // either side of midnight add to the real elapsed time, not to the end of day.
    func testRunningTimerSpanningMidnightCountsOnlyUntilNow() {
        let sleep = event(.sleep, at(2026, 7, 21, 23, 50))
        let now = at(2026, 7, 22, 0, 10)
        let before = DayTally.make(events: [sleep], on: at(2026, 7, 21), now: now, calendar: la)
        let after = DayTally.make(events: [sleep], on: at(2026, 7, 22), now: now, calendar: la)
        XCTAssertEqual(before.sleepSeconds, 600, accuracy: 0.001)
        XCTAssertEqual(after.sleepSeconds, 600, accuracy: 0.001)
        // One second before midnight the new day has nothing yet.
        let early = at(2026, 7, 21, 23, 59, 59)
        XCTAssertEqual(DayTally.make(events: [sleep], on: at(2026, 7, 22), now: early, calendar: la).sleepSeconds, 0)
    }

    // fed929e5: a night through the fall-back change is 10 real hours, 2 before
    // midnight and 8 after (the 25 hour day), and the sum is never off by an hour.
    func testNightThroughFallBackSplitsOnRealHours() {
        let sleep = event(.sleep, at(2026, 10, 31, 22), until: at(2026, 11, 1, 7))
        let now = at(2026, 11, 1, 12)
        let before = DayTally.make(events: [sleep], on: at(2026, 10, 31), now: now, calendar: la)
        let after = DayTally.make(events: [sleep], on: at(2026, 11, 1), now: now, calendar: la)
        XCTAssertEqual(hours(before.sleepSeconds), 2, accuracy: 0.001)
        XCTAssertEqual(hours(after.sleepSeconds), 8, accuracy: 0.001)
    }

    // fed929e5: and through spring forward, 2 hours then 6 of a night that lasts 8.
    func testNightThroughSpringForwardSplitsOnRealHours() {
        let sleep = event(.sleep, at(2027, 3, 13, 22), until: at(2027, 3, 14, 7))
        let now = at(2027, 3, 14, 12)
        let before = DayTally.make(events: [sleep], on: at(2027, 3, 13), now: now, calendar: la)
        let after = DayTally.make(events: [sleep], on: at(2027, 3, 14), now: now, calendar: la)
        XCTAssertEqual(hours(before.sleepSeconds), 2, accuracy: 0.001)
        XCTAssertEqual(hours(after.sleepSeconds), 6, accuracy: 0.001)
    }

    // fed929e5: day totals bucket the last second and the first second of a day apart.
    func testEntriesAtTheMidnightEdgeLandOnTheirOwnDay() {
        let late = event(.feed, at(2026, 7, 21, 23, 59, 59))
        let early = event(.feed, at(2026, 7, 22, 0, 0, 0))
        let now = at(2026, 7, 22, 8)
        XCTAssertEqual(DayTally.make(events: [late, early], on: at(2026, 7, 21), now: now, calendar: la).feeds, 1)
        XCTAssertEqual(DayTally.make(events: [late, early], on: at(2026, 7, 22), now: now, calendar: la).feeds, 1)
    }

    // MARK: - The totals window

    // 3046bbb6 era "By day keeps its start hour": a 6 AM day flips at 06:00:00 sharp.
    func testCustomDayWindowFlipsAtItsStartHour() {
        let window = TotalsWindow.day(startHour: 6)
        let before = window.interval(at: at(2026, 7, 22, 5, 59, 59), calendar: la)
        XCTAssertEqual(before.start, at(2026, 7, 21, 6))
        XCTAssertEqual(before.end, at(2026, 7, 22, 6))
        let after = window.interval(at: at(2026, 7, 22, 6), calendar: la)
        XCTAssertEqual(after.start, at(2026, 7, 22, 6))
        XCTAssertEqual(after.end, at(2026, 7, 23, 6))
        XCTAssertFalse(window.holds(at(2026, 7, 22, 6), in: before))
        XCTAssertTrue(window.holds(at(2026, 7, 22, 5, 59, 59), in: before))
    }

    // fed929e5: the calendar day on the 25 and 23 hour days runs midnight to
    // midnight, so the late evening still belongs to it and the stroke of the
    // next midnight does not.
    func testMidnightWindowOnDSTDaysRunsToTheNextMidnight() {
        let window = TotalsWindow.midnight
        let fall = window.interval(at: at(2026, 11, 1, 12), calendar: la)
        XCTAssertEqual(fall.start, at(2026, 11, 1))
        XCTAssertEqual(fall.end, at(2026, 11, 2))
        XCTAssertEqual(fall.duration, 25 * 3_600, accuracy: 0.001)
        XCTAssertTrue(window.holds(at(2026, 11, 1, 23, 59, 59), in: fall))
        XCTAssertFalse(window.holds(at(2026, 11, 2), in: fall))
        let spring = window.interval(at: at(2027, 3, 14, 12), calendar: la)
        XCTAssertEqual(spring.duration, 23 * 3_600, accuracy: 0.001)
        XCTAssertEqual(spring.end, at(2027, 3, 15))
    }

    // fed929e5 (widget entries clear today's counts at the day start): the Watch's
    // copy resets the first moment after midnight, and not a minute before.
    func testWatchSummaryClearsTodaysCountsAtMidnight() {
        var summary = NowSummary()
        summary.generatedAt = at(2026, 7, 21, 23, 50)
        summary.todayFeeds = 7
        summary.todayWet = 4
        XCTAssertEqual(summary.current(now: at(2026, 7, 21, 23, 59, 59), calendar: la).todayFeeds, 7)
        let next = summary.current(now: at(2026, 7, 22, 0, 0, 0), calendar: la)
        XCTAssertEqual(next.todayFeeds, 0)
        XCTAssertEqual(next.todayWet, 0)
    }

    func testWatchSummaryWithASixAmDayClearsAtSixNotMidnight() {
        var summary = NowSummary()
        summary.totalsWindow = 6
        summary.generatedAt = at(2026, 7, 22, 3)
        summary.todayFeeds = 3
        XCTAssertEqual(summary.current(now: at(2026, 7, 22, 5, 59, 59), calendar: la).todayFeeds, 3)
        XCTAssertEqual(summary.current(now: at(2026, 7, 22, 6, 0, 1), calendar: la).todayFeeds, 0)
    }

    // d519c5b8 / fed929e5: the summary counts the window the parent chose, from
    // the first to the last second of it, and finds the open timer.
    func testSummaryCountsTheWindowEdgesAndFindsTheRunningSleep() {
        let events = [
            event(.feed, at(2026, 7, 21, 23, 59, 59)),
            event(.feed, at(2026, 7, 22, 0, 0, 0)),
            event(.wet, at(2026, 7, 22, 0, 0, 1)),
            event(.feed, at(2026, 7, 22, 23, 59, 59)),
            event(.sleep, at(2026, 7, 22, 22)),
        ]
        let summary = NowSummary.make(
            child: child, events: events, now: at(2026, 7, 22, 23, 59, 59), calendar: la,
            window: .midnight, tracked: .all, feedTypes: .all
        )
        XCTAssertEqual(summary.todayFeeds, 2)
        XCTAssertEqual(summary.todayWet, 1)
        XCTAssertEqual(summary.runningSleepStart, at(2026, 7, 22, 22))
        let nextDay = NowSummary.make(
            child: child, events: events, now: at(2026, 7, 23, 0, 0, 0), calendar: la,
            window: .midnight, tracked: .all, feedTypes: .all
        )
        XCTAssertEqual(nextDay.todayFeeds, 0)
    }

    // d519c5b8: the hour strip and the totals come from one pass, so an entry the
    // totals count is in a square, including on the 23 hour day.
    func testHourStripAgreesWithTheTotalsOnASpringForwardDay() {
        let events = [
            event(.feed, at(2027, 3, 14, 0, 30)),
            event(.feed, at(2027, 3, 14, 3, 15)),
            event(.feed, at(2027, 3, 14, 12)),
            event(.wet, at(2027, 3, 14, 12, 5)),
        ]
        let totals = WindowTotals.make(events: events, window: .midnight, now: at(2027, 3, 14, 13), calendar: la)
        XCTAssertEqual(totals.feeds, 3)
        XCTAssertEqual(totals.wet, 1)
        XCTAssertEqual(totals.hours[.feed]?.reduce(0, +), 3)
        XCTAssertEqual(totals.interval.duration, 23 * 3_600, accuracy: 0.001)
    }

    // MARK: - History, reports and day of life

    // fed929e5 (the calendar follows midnight): the 14 day chart is 14 distinct
    // local days through the fall-back change, none skipped or doubled.
    func testChartDaysAreFourteenDistinctLocalDaysAcrossFallBack() {
        let days = DayChartModel.days(through: at(2026, 11, 8, 0, 0, 5), firstEntry: at(2026, 9, 1), calendar: la)
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.first, at(2026, 10, 26))
        XCTAssertEqual(days.last, at(2026, 11, 8))
        XCTAssertEqual(Set(days).count, 14)
        XCTAssertTrue(days.allSatisfy { la.startOfDay(for: $0) == $0 })
        let onFirstDay = DayChartModel.days(through: at(2026, 11, 8, 23, 59, 59), firstEntry: at(2026, 11, 8, 23, 59, 58), calendar: la)
        XCTAssertEqual(onFirstDay, [at(2026, 11, 8)])
    }

    // 7125df1c / fed929e5: one row per calendar day through spring forward, a
    // sleep over midnight splits across rows, and the running day is partial.
    func testReportHasOneRowPerLocalDayAcrossSpringForward() {
        let events = [
            event(.feed, at(2027, 3, 12, 9)),
            event(.sleep, at(2027, 3, 13, 22), until: at(2027, 3, 14, 7)),
            event(.feed, at(2027, 3, 14, 23, 59, 59)),
            event(.feed, at(2027, 3, 15, 0, 0, 1)),
        ]
        let report = SummaryReport.make(
            childName: "Nora", birthDate: nil, events: events,
            from: at(2027, 3, 12, 15), to: at(2027, 3, 15, 1),
            now: at(2027, 3, 15, 8), calendar: la
        )
        XCTAssertEqual(report.days.map(\.date), [at(2027, 3, 12), at(2027, 3, 13), at(2027, 3, 14), at(2027, 3, 15)])
        XCTAssertEqual(report.days.map(\.feeds), [1, 0, 1, 1])
        XCTAssertEqual(hours(report.days[1].sleepSeconds), 2, accuracy: 0.001)
        XCTAssertEqual(hours(report.days[2].sleepSeconds), 6, accuracy: 0.001)
        // The 8 hour bout belongs to the day it started on.
        XCTAssertEqual(hours(report.days[1].longestSleepSeconds), 8, accuracy: 0.001)
        XCTAssertEqual(report.days[3].partial, .today)
    }

    // fed929e5: the day logging began is partial from the first second of that day.
    func testLoggingBeganDayIsPartialAtItsFirstAndLastSecond() {
        for began in [at(2026, 7, 21, 0, 0, 0), at(2026, 7, 21, 23, 59, 59)] {
            let events = [event(.feed, began), event(.feed, at(2026, 7, 22, 9))]
            let report = SummaryReport.make(
                childName: "Nora", birthDate: nil, events: events,
                from: at(2026, 7, 21), to: at(2026, 7, 22), now: at(2026, 7, 22, 12), calendar: la
            )
            XCTAssertEqual(report.days[0].partial, .loggingBegan(began))
        }
    }

    // fed929e5: day 1 is the calendar day of birth, whatever the hour, and the
    // count steps exactly at local midnight, including over the 25 hour day.
    func testDayOfLifeStepsAtLocalMidnightAcrossFallBack() {
        let birth = at(2026, 10, 31, 12)
        XCTAssertEqual(DateHelpers.dayOfLife(birthDate: birth, on: at(2026, 10, 31, 23, 59, 59), calendar: la), 1)
        XCTAssertEqual(DateHelpers.dayOfLife(birthDate: birth, on: at(2026, 11, 1, 0, 0, 0), calendar: la), 2)
        XCTAssertEqual(DateHelpers.dayOfLife(birthDate: birth, on: at(2026, 11, 1, 23, 59, 59), calendar: la), 2)
        XCTAssertEqual(DateHelpers.dayOfLife(birthDate: birth, on: at(2026, 11, 2, 0, 0, 0), calendar: la), 3)
        XCTAssertNil(DateHelpers.dayOfLife(birthDate: birth, on: at(2026, 10, 30, 23, 59, 59), calendar: la))
        XCTAssertEqual(DateHelpers.date(forDayOfLife: 3, birthDate: birth, calendar: la), at(2026, 11, 2))
    }

    // fed929e5 (birth dates are stored at noon): a birth picked at the first or
    // last minute of the day keeps its day, on both DST days.
    func testBirthDateStoredAtNoonKeepsItsCalendarDay() {
        for picked in [at(2026, 11, 1, 0, 0, 1), at(2026, 11, 1, 23, 59), at(2027, 3, 14, 0, 30), at(2027, 3, 14, 23, 30)] {
            let noon = EventStore.noon(of: picked, calendar: la)
            XCTAssertEqual(noon.map { la.component(.hour, from: $0) }, 12)
            XCTAssertEqual(noon.map { DateHelpers.dayKey(for: $0, calendar: la) }, DateHelpers.dayKey(for: picked, calendar: la))
        }
    }

    // fed929e5 (CSV dates are local days): an entry just before local midnight
    // is the evening's date even though it is already the next day in UTC.
    func testCSVDateIsTheLocalDayAtTheMidnightEdge() {
        let late = event(.feed, at(2026, 7, 21, 23, 59, 59))
        let early = event(.feed, at(2026, 7, 22, 0, 0, 0))
        let rows = SummaryReport.csv(events: [late, early], childName: "Nora", timeZone: la.timeZone)
            .split(separator: "\n").dropFirst().map { $0.split(separator: ",", omittingEmptySubsequences: false) }
        XCTAssertEqual(rows.map { String($0[1]) }, ["2026-07-21", "2026-07-22"])
    }

    // MARK: - Partner sync

    // fed929e5 / 7125df1c: a partner in another zone logs at 02:30 Eastern, which
    // is 23:30 here the evening before, and every day bucket follows the local clock.
    func testAPartnersEntryLandsOnThisPhonesLocalDay() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let partnerStamp = eastern.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 2, minute: 30))!
        XCTAssertEqual(partnerStamp, at(2026, 7, 21, 23, 30))
        let theirs = event(.feed, partnerStamp)
        let now = at(2026, 7, 22, 8)
        XCTAssertEqual(DayTally.make(events: [theirs], on: at(2026, 7, 21), now: now, calendar: la).feeds, 1)
        XCTAssertEqual(DayTally.make(events: [theirs], on: at(2026, 7, 22), now: now, calendar: la).feeds, 0)
        XCTAssertEqual(DateHelpers.dayKey(for: partnerStamp, calendar: la), "2026-07-21")
        XCTAssertEqual(DateHelpers.dayKey(for: partnerStamp, calendar: eastern), "2026-07-22")
    }

    // 79d311b5 / 01b3675e: two copies of one entry (the widget's and the export)
    // show once, the newer edit wins, even when the copies straddle midnight.
    func testTwoCopiesOfOneEntryCollapseToTheNewerEdit() {
        let id = UUID()
        let older = event(.feed, at(2026, 7, 21, 23, 58))
        older.id = id
        older.updatedAt = at(2026, 7, 21, 23, 59)
        let newer = event(.feed, at(2026, 7, 22, 0, 2))
        newer.id = id
        newer.updatedAt = at(2026, 7, 22, 0, 3)
        let shown = LogEvent.coalesced([older, newer])
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown.first?.start, at(2026, 7, 22, 0, 2))
    }

    // MARK: - Reminders

    // 08394f90 / fed929e5: the checkup note is 19:00 the evening before, on the
    // spring-forward date too, and drops out the second its time passes.
    func testCheckupNoteIsTheEveningBeforeAndExpiresAtItsMinute() {
        let checkup = at(2027, 3, 14, 9)
        let evening = at(2027, 3, 13, 19)
        let before = Reminders.checkupReminders(birthDate: nil, nextCheckup: checkup, now: evening.addingTimeInterval(-1), calendar: la)
        XCTAssertEqual(before.map(\.date), [evening])
        XCTAssertTrue(Reminders.checkupReminders(birthDate: nil, nextCheckup: checkup, now: evening, calendar: la).isEmpty)
    }

    func testNewbornCheckupNotesFollowTheBirthDayAcrossFallBack() {
        let birth = at(2026, 10, 28, 12)
        let notes = Reminders.checkupReminders(birthDate: birth, nextCheckup: nil, now: at(2026, 10, 28, 13), calendar: la)
        // Day 4 is Oct 31, day 14 is Nov 10, day 30 is Nov 26.
        XCTAssertEqual(notes.map(\.date), [at(2026, 10, 30, 19), at(2026, 11, 9, 19), at(2026, 11, 25, 19)])
    }

    // 08394f90: the feed reminder is due the chosen gap after the feed began,
    // measured in real seconds across midnight, and not planned inside 30 seconds.
    func testFeedReminderAcrossMidnightAndTheThirtySecondMargin() {
        var summary = NowSummary()
        summary.childName = "Nora"
        summary.lastFeedAt = at(2026, 7, 21, 22, 30)
        let planned = Reminders.feedReminder(for: summary, interval: .threeHours, now: at(2026, 7, 21, 23, 45))
        XCTAssertEqual(planned?.date, at(2026, 7, 22, 1, 30))
        XCTAssertNotNil(Reminders.feedReminder(for: summary, interval: .threeHours, now: at(2026, 7, 22, 1, 29, 29)))
        XCTAssertNil(Reminders.feedReminder(for: summary, interval: .threeHours, now: at(2026, 7, 22, 1, 29, 30)))
        // The fall-back night adds an hour of real time.
        summary.lastFeedAt = at(2026, 11, 1, 0, 30)
        XCTAssertEqual(
            Reminders.feedReminder(for: summary, interval: .fourHours, now: at(2026, 11, 1, 1))?.date,
            summary.lastFeedAt!.addingTimeInterval(4 * 3_600)
        )
    }

    // MARK: - Backdating

    // fed929e5: a time-only wheel that lands later than now means yesterday, even
    // just after midnight and over a DST change.
    func testWheelTimeLaterThanNowMeansYesterdayJustAfterMidnight() {
        let clock = LogClock()
        defer { clock.reset() }
        clock.set(at(2026, 11, 2, 23, 50), now: at(2026, 11, 2, 0, 10), calendar: la)
        XCTAssertEqual(clock.chosen, at(2026, 11, 1, 23, 50))
        XCTAssertTrue(LogClock.label(for: at(2026, 11, 1, 23, 50), now: at(2026, 11, 2, 0, 10), calendar: la).hasSuffix(" yesterday"))
        XCTAssertFalse(LogClock.label(for: at(2026, 11, 2, 0, 5), now: at(2026, 11, 2, 0, 10), calendar: la).hasSuffix(" yesterday"))
    }

    func testWheelTimeWithinAMinuteOfNowIsNow() {
        let clock = LogClock()
        defer { clock.reset() }
        clock.set(at(2027, 3, 14, 3, 0, 40), now: at(2027, 3, 14, 3, 0, 0), calendar: la)
        XCTAssertNil(clock.chosen)
    }
}
