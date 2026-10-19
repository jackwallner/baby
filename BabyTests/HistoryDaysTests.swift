import CoreData
import XCTest
@testable import Baby

@MainActor
final class HistoryDaysTests: XCTestCase {
    private var persistence: Persistence!
    private var store: EventStore!
    private let calendar = Calendar.current

    override func setUp() async throws {
        persistence = Persistence(cloudKit: false, inMemory: true)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.hiddenKinds)
        store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: nil)
    }

    private func day(_ back: Int, hour: Int) -> Date {
        let start = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: .now))!
        return start.addingTimeInterval(TimeInterval(hour) * 3600)
    }

    func testTheChartCoversTwoWeeksThroughTodayButNeverBeforeTheFirstEntry() {
        let today = calendar.startOfDay(for: .now)
        let long = DayChartModel.days(through: .now, firstEntry: day(40, hour: 9))
        XCTAssertEqual(long.count, DayChartModel.dayCount)
        XCTAssertEqual(long.last, today)

        let short = DayChartModel.days(through: .now, firstEntry: day(2, hour: 18))
        XCTAssertEqual(short, [day(2, hour: 0), day(1, hour: 0), today])
        XCTAssertEqual(DayChartModel.days(through: .now, firstEntry: nil), [today])
    }

    func testEachBarIsThatDaysFeedsAndTodayIsMarked() {
        for hour in [1, 4, 7, 10] { store.log(.feed, at: day(1, hour: hour)) }
        store.log(.wet, at: day(1, hour: 5))
        store.log(.feed, at: day(0, hour: 0))
        let model = DayChartModel.make(events: store.events, tracked: .all)
        XCTAssertEqual(model.metric, .feeds)
        XCTAssertEqual(model.bars.map(\.value), [4, 1])
        XCTAssertEqual(model.bars.map(\.isToday), [false, true])
        XCTAssertEqual(model.bars.first?.tally.wet, 1)
    }

    func testWithFeedOffTheChartCountsTheDiapersStillShown() {
        store.log(.wet, at: day(0, hour: 0))
        store.log(.dirty, at: day(0, hour: 0))
        let noFeed = TrackedKinds(hidden: [.feed])
        XCTAssertEqual(DayChartModel.make(events: store.events, tracked: noFeed).metric, .diapers)
        XCTAssertEqual(DayChartModel.make(events: store.events, tracked: noFeed).bars.last?.value, 2)
        let onlyWet = TrackedKinds(hidden: [.feed, .dirty])
        XCTAssertEqual(DayChartModel.make(events: store.events, tracked: onlyWet).bars.last?.value, 1)
        XCTAssertEqual(DayChartModel.Metric(tracked: TrackedKinds(hidden: [.feed, .wet, .dirty])), .sleep)
    }

    func testTheDayLineLeadsWithFeedsAndSkipsWhatIsTurnedOff() {
        var tally = DayTally()
        tally.feeds = 9
        tally.wet = 6
        tally.dirty = 1
        tally.sleepSeconds = 30
        XCTAssertEqual(DayLine.parts(tally, tracked: .all).first, "9 feeds")
        XCTAssertEqual(DayLine.parts(tally, tracked: .all).count, 3, "under a minute of sleep is left out")
        XCTAssertEqual(DayLine.parts(tally, tracked: TrackedKinds(hidden: [.feed])).first?.hasPrefix("6 "), true)
    }
}
