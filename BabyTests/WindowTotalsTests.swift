import CoreData
import XCTest
@testable import Baby

@MainActor
final class WindowTotalsTests: XCTestCase {
    private var persistence: Persistence!
    private var store: EventStore!

    override func setUp() async throws {
        persistence = Persistence(cloudKit: false, inMemory: true)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.totalsWindow)
        store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: nil)
    }

    override func tearDown() async throws {
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.totalsWindow)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testTotalsAndHourSquaresComeFromTheSameEntries() {
        store.log(.feed, at: at(28, 5, 50))   // before a 6am day starts
        store.log(.feed, at: at(28, 6, 10))
        store.log(.feed, at: at(28, 6, 40))
        store.log(.wet, at: at(28, 7, 5))
        store.log(.dirty, at: at(28, 9, 0))
        store.startTimed(.sleep, at: at(28, 7, 30))
        store.stopRunning(.sleep, at: at(28, 8, 45))

        let now = at(28, 10, 15)
        let totals = WindowTotals.make(events: store.events, window: .day(startHour: 6), now: now, calendar: utc)
        XCTAssertEqual(totals.feeds, 2, "the 5:50 feed belongs to the day before")
        XCTAssertEqual(totals.wet, 1)
        XCTAssertEqual(totals.dirty, 1)
        XCTAssertEqual(totals.sleepSeconds, 75 * 60)
        XCTAssertEqual(totals.hours[.feed]?[0], 2, "two feeds in the 6am hour")
        XCTAssertEqual(totals.hours[.wet]?[1], 1)
        XCTAssertEqual(totals.hours[.dirty]?[3], 1)
        XCTAssertEqual(totals.hours[.sleep]?[1] ?? 0, 0.5, accuracy: 0.001, "asleep 7:30 to 8")
        XCTAssertEqual(totals.hours[.sleep]?[2] ?? 0, 0.75, accuracy: 0.001, "asleep 8 to 8:45")
        XCTAssertEqual(totals.futureFrom, 5, "10:15 is in the fifth hour; 11am onwards has not happened")
        XCTAssertEqual(totals.line, "2 feeds · 1 \(EventKind.wet.label.lowercased()) · 1 \(EventKind.dirty.label.lowercased()) · 1h 15m sleep")

        let midnight = WindowTotals.make(events: store.events, window: .midnight, now: now, calendar: utc)
        XCTAssertEqual(midnight.feeds, 3)
    }

    func testLastTwentyFourHoursDrawsWholeHoursEndingNow() {
        store.log(.feed, at: at(27, 11, 0))  // 23h15m before now: inside
        store.log(.feed, at: at(27, 10, 0))  // 24h15m before: outside
        store.log(.wet, at: at(28, 10, 5))
        let now = at(28, 10, 15)
        let totals = WindowTotals.make(events: store.events, window: .last24Hours, now: now, calendar: utc)
        XCTAssertEqual(totals.feeds, 1)
        XCTAssertEqual(totals.gridStart, at(27, 11))
        XCTAssertEqual(totals.hours[.feed]?[0], 1)
        XCTAssertEqual(totals.hours[.wet]?[23], 1, "the current hour is the last square")
        XCTAssertEqual(totals.futureFrom, WindowTotals.columns)
    }

    func testTheSummaryCountsInTheChosenWindow() {
        let now = Date.now
        store.log(.wet, at: now.addingTimeInterval(-60))
        store.log(.wet, at: now.addingTimeInterval(-23 * 3600))
        let rolling = NowSummary.make(child: store.child, events: store.events, now: now, window: .last24Hours)
        XCTAssertEqual(rolling.todayWet, 2)
        XCTAssertEqual(rolling.totalsWindow, -1)
    }
}

@MainActor
final class LogClockTests: XCTestCase {
    private func time(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: second, of: .now)!
    }

    func testMinusStepsBackOnTheFiveMinuteGrid() {
        let clock = LogClock()
        let now = time(7, 26, 30)
        XCTAssertFalse(clock.isAdjusted)
        clock.nudge(earlier: true, now: now)
        XCTAssertEqual(clock.chosen, time(7, 25))
        clock.nudge(earlier: true, now: now)
        clock.nudge(earlier: true, now: now)
        XCTAssertEqual(clock.chosen, time(7, 15), "7:26 to 7:15 in three taps")
        XCTAssertEqual(clock.time(now: now), time(7, 15))
    }

    func testMinusJustAfterAMarkStillGoesBack() {
        let clock = LogClock()
        let now = time(8, 30, 10)
        clock.nudge(earlier: true, now: now)
        XCTAssertEqual(clock.chosen, time(8, 25), "8:30 is ten seconds ago, so the first step is 8:25")
    }

    func testPlusPastNowReturnsToLive() {
        let clock = LogClock()
        let now = time(7, 26, 30)
        clock.nudge(earlier: true, now: now)
        clock.nudge(earlier: true, now: now)
        clock.nudge(earlier: false, now: now)
        XCTAssertEqual(clock.chosen, time(7, 25))
        clock.nudge(earlier: false, now: now)
        XCTAssertNil(clock.chosen, "7:30 would be the future: back to now")
    }

    func testTheWheelNeverPicksTheFuture() {
        let clock = LogClock()
        let now = time(0, 10)
        clock.set(time(23, 50), now: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: time(23, 50))!
        XCTAssertEqual(clock.chosen, yesterday, "11:50pm picked at 12:10am means last night")
        XCTAssertEqual(LogClock.label(for: yesterday, now: now), "\(Format.time(yesterday)) yesterday")
        clock.set(now, now: now)
        XCTAssertNil(clock.chosen, "picking the current minute is just now")
    }

    func testItReturnsToNowAfterAMinute() {
        let clock = LogClock()
        let now = time(7, 26)
        clock.nudge(earlier: true, now: now)
        XCTAssertEqual(clock.returnsAt, now.addingTimeInterval(LogClock.hold))
        clock.expireIfDue(now: now.addingTimeInterval(30))
        XCTAssertTrue(clock.isAdjusted)
        clock.touched(now: now.addingTimeInterval(30))
        clock.expireIfDue(now: now.addingTimeInterval(LogClock.hold + 1))
        XCTAssertTrue(clock.isAdjusted, "a tap at the chosen time gives another minute")
        clock.expireIfDue(now: now.addingTimeInterval(30 + LogClock.hold))
        XCTAssertNil(clock.chosen)
    }
}
