import CoreData
import XCTest
@testable import Baby

@MainActor
final class EventStoreTests: XCTestCase {
    private var persistence: Persistence!
    private var store: EventStore!

    override func setUp() async throws {
        persistence = Persistence(cloudKit: false, inMemory: true)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: Calendar.current.date(byAdding: .day, value: -2, to: .now))
    }

    func testOneTapFeedLogsNowWithTheSuggestedSide() {
        XCTAssertEqual(store.summary.suggestedSide, .left, "first feed suggests the left side")
        store.log(.feed)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.summary.lastFeedSide, .left)
        XCTAssertEqual(store.summary.suggestedSide, .right, "the other side comes next")
        XCTAssertFalse(store.events[0].isRunning, "a one-tap feed is instant, not a timer")
        store.log(.feed, side: .bottle)
        XCTAssertEqual(store.summary.suggestedSide, .bottle, "bottle stays bottle")
    }

    func testDiapersCountTowardTodayAndTheLastDiaperLine() {
        store.log(.wet)
        store.log(.dirty)
        store.log(.wet)
        XCTAssertEqual(store.summary.todayWet, 2)
        XCTAssertEqual(store.summary.todayDirty, 1)
        XCTAssertEqual(store.summary.lastDiaperKind, .wet)
        XCTAssertTrue(store.summary.diaperLine().hasPrefix("Last diaper just now"))
    }

    func testSleepTogglesBetweenRunningAndEnded() {
        store.toggleSleep(at: Date.now.addingTimeInterval(-3600))
        XCTAssertNotNil(store.runningSleep)
        XCTAssertTrue(store.summary.isSleeping)
        XCTAssertEqual(store.summary.sleepLine(), "Asleep 1h")
        store.toggleSleep()
        XCTAssertNil(store.runningSleep)
        XCTAssertEqual(Int((store.events[0].duration ?? 0) / 60), 60)
        XCTAssertEqual(Int(store.tally(on: .now).sleepSeconds / 60), 60)
    }

    func testStartingASecondTimedFeedEndsTheFirst() {
        store.startTimed(.feed, side: .left, at: Date.now.addingTimeInterval(-600))
        store.startTimed(.feed, side: .right)
        XCTAssertEqual(store.events.filter { $0.isRunning }.count, 1)
        XCTAssertEqual(store.runningFeed?.feedSide, .right)
        XCTAssertTrue(store.summary.feedLine().hasPrefix("Feeding · Right"))
    }

    func testUndoRemovesTheLastTapAndReopensAStop() {
        store.log(.wet)
        XCTAssertNotNil(store.lastLogged)
        store.undoLast()
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertNil(store.lastLogged)

        store.toggleSleep(at: Date.now.addingTimeInterval(-1200))
        store.toggleSleep()
        XCTAssertNil(store.runningSleep)
        store.undoLast()
        XCTAssertNotNil(store.runningSleep, "undoing the wake reopens the sleep")
    }

    func testWatchPayloadsApplyOnceEvenWhenRedelivered() {
        let payload = WatchLogPayload(action: .log, kind: .dirty, at: .now)
        store.apply(payload)
        store.apply(payload)
        XCTAssertEqual(store.events.count, 1)
        let start = WatchLogPayload(action: .startSleep, kind: .sleep, at: Date.now.addingTimeInterval(-300))
        store.apply(start)
        store.apply(start)
        XCTAssertEqual(store.events.filter { $0.eventKind == .sleep }.count, 1)
        store.apply(WatchLogPayload(action: .stopSleep, kind: .sleep))
        XCTAssertNil(store.runningSleep)
    }

    func testTallyCountsByCalendarDayAndSplitsSleepAtMidnight() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        store.log(.wet, at: yesterday.addingTimeInterval(3600))
        store.log(.wet, at: today.addingTimeInterval(3600))
        store.startTimed(.sleep, at: yesterday.addingTimeInterval(23 * 3600))
        store.stopRunning(.sleep, at: today.addingTimeInterval(3600))
        XCTAssertEqual(store.tally(on: yesterday).wet, 1)
        XCTAssertEqual(store.tally(on: today).wet, 1)
        XCTAssertEqual(Int(store.tally(on: yesterday).sleepSeconds), 3600)
        XCTAssertEqual(Int(store.tally(on: today).sleepSeconds), 3600)
        XCTAssertEqual(store.eventsByDay.count, 2)
    }

    func testSummaryRoundTripsThroughTheAppGroup() {
        store.log(.feed, side: .right)
        store.log(.dirty)
        let loaded = NowSummary.load()
        XCTAssertEqual(loaded.lastFeedSide, .right)
        XCTAssertEqual(loaded.lastDiaperKind, .dirty)
        XCTAssertEqual(loaded.dayOfLife, 3)
    }
}
