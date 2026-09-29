import CoreData
import XCTest
@testable import Baby

@MainActor
final class TrackedKindsTests: XCTestCase {
    private var persistence: Persistence!
    private var store: EventStore!

    override func setUp() async throws {
        persistence = Persistence(cloudKit: false, inMemory: true)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.hiddenKinds)
        store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: nil)
    }

    override func tearDown() async throws {
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.hiddenKinds)
    }

    func testAtLeastOneButtonAlwaysStays() {
        XCTAssertEqual(TrackedKinds(hidden: Set(TrackedKinds.buttons)), .all)
        XCTAssertTrue(TrackedKinds(hidden: [.feed, .wet, .dirty]).contains(.sleep))
        XCTAssertTrue(TrackedKinds(hidden: [.weight]).contains(.weight))
    }

    func testHeadlineNamesOnlyTrackedKinds() {
        XCTAssertEqual(TrackedKinds.all.headline, "Feeds, diapers and sleep")
        XCTAssertEqual(TrackedKinds(hidden: [.sleep]).headline, "Feeds and diapers")
        XCTAssertEqual(TrackedKinds(hidden: [.feed, .wet, .dirty]).headline, "Sleep")
    }

    func testHiddenEntriesLeaveTheLogAndComeBack() {
        store.log(.feed)
        store.log(.wet)
        TrackedKinds(hidden: [.feed]).store()
        store.reload()
        XCTAssertEqual(store.events.map(\.eventKind), [.wet])
        XCTAssertNil(store.summary.lastFeedAt)
        XCTAssertEqual(store.summary.todayFeeds, 0)
        XCTAssertEqual(store.summary.hiddenKinds, [.feed])
        XCTAssertEqual(store.summary.leadKind, .wet)

        TrackedKinds.all.store()
        store.reload()
        XCTAssertEqual(Set(store.events.map(\.eventKind)), [.feed, .wet])
        XCTAssertNotNil(store.summary.lastFeedAt)
        XCTAssertNil(store.summary.hiddenKinds)
    }

    func testSummaryLeadsWithSleepWhenThatIsAllThatIsTracked() {
        let woke = Date.now.addingTimeInterval(-90 * 60)
        store.startTimed(.sleep, at: woke.addingTimeInterval(-3600))
        store.stopRunning(.sleep, at: woke)
        TrackedKinds(hidden: [.feed, .wet, .dirty]).store()
        store.reload()
        XCTAssertEqual(store.summary.leadKind, .sleep)
        XCTAssertEqual(store.summary.lastWokeAt?.timeIntervalSince1970 ?? 0, woke.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(store.summary.leadLine(now: woke.addingTimeInterval(90 * 60)), "Awake 1h 30m")
        XCTAssertEqual(store.summary.todayLine, "")
    }

    func testReportLeavesOutUntrackedKinds() {
        let now = Date.now
        store.log(.feed, at: now)
        store.log(.dirty, at: now)
        let report = SummaryReport.make(
            childName: "Nora",
            birthDate: nil,
            events: store.events,
            from: now,
            to: now,
            tracked: TrackedKinds(hidden: [.dirty])
        )
        XCTAssertEqual(report.totalFeeds, 1)
        XCTAssertEqual(report.totalDirty, 0)
        XCTAssertFalse(report.tracked.contains(.dirty))
    }
}
