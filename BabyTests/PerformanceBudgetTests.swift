import CoreData
import XCTest
@testable import Baby

/// Worst-case open and scroll paths against three years of dense logging: about
/// 20 entries a day, every day, with a partner's duplicate copies of some. Each
/// budget is about 5x the best of three runs on the simulator, with the
/// measurement beside it, so a normal machine passes with wide margin and a
/// quadratic regression does not.
@MainActor
final class PerformanceBudgetTests: XCTestCase {
    private var persistence: Persistence!
    private var store: EventStore!

    private let la: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let dayCount = 3 * 365
    private var now: Date {
        la.date(from: DateComponents(year: 2027, month: 8, day: 20, hour: 12))!
    }

    override func setUp() async throws {
        persistence = Persistence(cloudKit: false, inMemory: true)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.hiddenKinds)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.totalsWindow)
        store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: la.date(byAdding: .day, value: -dayCount, to: now))
    }

    override func tearDown() async throws {
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
    }

    /// 8 feeds (a few bottles), 6 diapers, 3 night and nap sleeps across midnight,
    /// and a weigh-in on Mondays: 17 to 18 entries a day through `now`.
    @discardableResult
    private func fillThreeYears() throws -> Int {
        let child = try XCTUnwrap(store.child)
        let context = store.context
        let today = la.startOfDay(for: now)
        var count = 0
        for back in stride(from: dayCount, through: 0, by: -1) {
            let day = la.date(byAdding: .day, value: -back, to: today)!
            for slot in 0..<8 {
                let start = day.addingTimeInterval(TimeInterval(slot * 10_800 + 1_800))
                if start > now { continue }
                persistence.insert(kind: .feed, at: start, side: slot % 3 == 0 ? .bottle : .left, ended: start.addingTimeInterval(900), for: child, in: context)
                count += 1
            }
            for slot in 0..<6 {
                let start = day.addingTimeInterval(TimeInterval(slot * 14_400 + 600))
                if start > now { continue }
                persistence.insert(kind: slot % 2 == 0 ? .wet : .dirty, at: start, for: child, in: context)
                count += 1
            }
            for (slot, hour) in [(0, 21.0), (1, 2.5), (2, 13.0)] {
                let start = day.addingTimeInterval(hour * 3_600)
                let length = slot == 0 ? 5 * 3_600 : 3_600
                if start.addingTimeInterval(TimeInterval(length)) > now { continue }
                persistence.insert(kind: .sleep, at: start, ended: start.addingTimeInterval(TimeInterval(length)), for: child, in: context)
                count += 1
            }
        }
        XCTAssertTrue(persistence.save(context))
        store.reload()
        return count
    }

    private func best(_ label: String, budget: Double, _ body: () throws -> Void) rethrows {
        var fastest = Double.infinity
        for _ in 0..<3 {
            let start = ContinuousClock.now
            try body()
            let elapsed = start.duration(to: .now)
            fastest = min(fastest, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        }
        print("PERF \(label): \(String(format: "%.1f", fastest * 1_000)) ms (budget \(Int(budget * 1_000)) ms)")
        XCTAssertLessThan(fastest, budget, "\(label) took \(fastest) s")
    }

    func testFixtureBuildsInUnderTwoSeconds() throws {
        let start = ContinuousClock.now
        let count = try fillThreeYears()
        let elapsed = start.duration(to: .now)
        print("PERF fixture: \(count) entries in \(elapsed)")
        XCTAssertGreaterThan(count, 15_000)
        XCTAssertEqual(store.events.count, count)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    // 08394f90 / d519c5b8 (the whole log walked on every render): opening the
    // app refetches three years and rebuilds the summary the widgets and Watch read.
    func testOpeningTheAppOverThreeYears() throws {
        try fillThreeYears()
        best("reload", budget: 3.5) {  // measured 662 ms store.reload() }
        best("now summary", budget: 1.5) {  // measured 281 ms
            let summary = NowSummary.make(
                child: store.child, events: store.events, now: now, calendar: la,
                window: .midnight, tracked: .all, feedTypes: .all
            )
            XCTAssertGreaterThan(summary.todayFeeds, 0)
        }
        best("window totals", budget: 0.1) {  // measured 9.3 ms
            let totals = WindowTotals.make(events: store.events, window: .last24Hours, now: now, calendar: la)
            XCTAssertGreaterThan(totals.feeds, 0)
        }
    }

    // d519c5b8: the log buttons ask for the running sleep on every render.
    func testRunningSleepLookupIsCheapWithNothingRunning() throws {
        try fillThreeYears()
        best("running sleep reads", budget: 0.1) {  // measured 1.2 ms
            for _ in 0..<2_000 { XCTAssertNil(store.runningSleep) }
        }
    }

    // 08394f90: History's chart, month grid and day list reuse one pass of totals.
    func testHistoryScrollOverThreeYears() throws {
        try fillThreeYears()
        best("history day groups", budget: 0.1) {  // measured 0 ms
            XCTAssertGreaterThan(store.eventsByDay.count, 1_000)
        }
        best("history chart bars", budget: 0.7) {  // measured 136 ms
            let model = DayChartModel.make(events: store.events, tracked: .all, now: now, calendar: la)
            XCTAssertEqual(model.bars.count, DayChartModel.dayCount)
        }
        best("month grid cells", budget: 0.1) {  // measured 0.2 ms
            for back in 0..<31 {
                let day = la.date(byAdding: .day, value: -back, to: now)!
                _ = store.hasEntries(on: day)
            }
        }
    }

    // 7125df1c (report scans only entries in range): a report over a long range
    // and the CSV of the whole log.
    func testReportsOverThreeYears() throws {
        try fillThreeYears()
        let events = store.events
        for (label, days, budget) in [("report 14 days", 14, 0.25), ("report 90 days", 90, 1.0), ("report 1 year", 365, 12.0)]  // measured 40 ms, 186 ms, 2.4 s {
            best(label, budget: budget) {
                let report = SummaryReport.make(
                    childName: "Nora", birthDate: nil, events: events,
                    from: la.date(byAdding: .day, value: -days, to: now)!, to: now, now: now, calendar: la
                )
                XCTAssertEqual(report.days.count, days + 1)
            }
        }
        best("csv", budget: 1.5) {  // measured 286 ms
            XCTAssertGreaterThan(SummaryReport.csv(events: events, childName: "Nora", timeZone: la.timeZone).count, 100_000)
        }
    }

    // 79d311b5: merging two copies of every widget entry stays linear.
    func testCoalescingTwoCopiesOfThreeYears() throws {
        try fillThreeYears()
        let child = try XCTUnwrap(store.child)
        var doubled = store.events
        for event in store.events.prefix(2_000) {
            let copy = persistence.insert(kind: event.eventKind, at: event.start, ended: event.endedAt, for: child, in: store.context)
            copy.id = event.id
            copy.updatedAt = .now
            doubled.append(copy)
        }
        best("coalesce", budget: 1.5) {  // measured 262 ms
            XCTAssertEqual(LogEvent.coalesced(doubled).count, store.events.count)
        }
    }
}
