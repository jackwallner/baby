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
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.showsPump)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.customButtons)
        store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: nil)
    }

    override func tearDown() async throws {
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.hiddenKinds)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.showsPump)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.customButtons)
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

    func testExtraButtonsAreOffByDefaultAndCapped() {
        XCTAssertFalse(TrackedKinds.current.pump)
        XCTAssertEqual(TrackedKinds.current.extras, [])
        XCTAssertFalse(TrackedKinds.all.contains(.pump))
        XCTAssertTrue(TrackedKinds.all.contains(.custom))

        let tracked = TrackedKinds(hidden: [], pump: true, custom: [" Self woke ", "self woke", "", "Woke her", "Vitamin D", "Bath"])
        XCTAssertEqual(tracked.custom, ["Self woke", "Woke her", "Vitamin D"])
        XCTAssertEqual(tracked.extras, [.pump, .custom("Self woke"), .custom("Woke her"), .custom("Vitamin D")])
        XCTAssertFalse(tracked.canAddExtra)
        XCTAssertEqual(LogButtons.rowCount(for: tracked), 5)

        tracked.store()
        XCTAssertEqual(TrackedKinds.current, tracked)
    }

    func testCustomAndPumpEntriesLogWithoutTouchingTheSummary() throws {
        TrackedKinds(hidden: [], pump: true, custom: ["Self woke"]).store()
        store.reload()
        let pump = try XCTUnwrap(store.log(.pump) { $0.amount = 90 })
        let woke = try XCTUnwrap(store.log(.custom, name: "Self woke"))
        XCTAssertNil(store.log(.custom, name: "  "))

        XCTAssertEqual(woke.title, "Self woke")
        XCTAssertEqual(woke.eventKind, .custom)
        XCTAssertTrue(woke.feedSides.isEmpty)
        XCTAssertEqual(pump.title, "Pump")
        XCTAssertNotNil(pump.detailText)
        XCTAssertNil(store.summary.lastFeedAt)
        XCTAssertNil(store.summary.lastDiaperAt)
        XCTAssertEqual(store.summary.todayFeeds, 0)
        XCTAssertEqual(store.summary.recent?.count ?? 0, 0)
        XCTAssertEqual(store.lastLogged?.name, "Self woke")

        let csv = SummaryReport.csv(events: store.events, childName: "Nora")
        XCTAssertTrue(csv.contains(",Self woke,,"))
        XCTAssertTrue(csv.contains(",pump,,90,"))

        // Pump turned off leaves the log; a removed custom button's entries stay.
        TrackedKinds.all.store()
        store.reload()
        XCTAssertEqual(store.events.map(\.eventKind), [.custom])
    }

    func testAKindFromANewerBuildIsNeverReadAsAFeed() {
        let event = LogEvent(context: persistence.viewContext)
        event.kind = "bath"
        XCTAssertEqual(event.eventKind, .custom)
        event.kind = nil
        XCTAssertEqual(event.eventKind, .feed)
    }
}
