import CoreData
import XCTest
@testable import Baby

/// Two parents' phones, each with its own log files, joined by the relay the
/// simulators use in place of iCloud. A partner's change lands the way a
/// CloudKit import does (a background save under the mirroring author), and
/// shows through the same quiet refresh a remote-change notice runs.
@MainActor
final class TwoPhoneTests: XCTestCase {
    private var root: URL!
    private var jack: EventStore!
    private var elsa: EventStore!
    private var jackRelay: SimPartnerRelay!
    private var elsaRelay: SimPartnerRelay!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("TwoPhoneTests-\(UUID().uuidString)", isDirectory: true)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        let folder = root.appendingPathComponent("relay", isDirectory: true)
        jack = EventStore(persistence: Persistence(cloudKit: false, directory: root.appendingPathComponent("jack")))
        elsa = EventStore(persistence: Persistence(cloudKit: false, directory: root.appendingPathComponent("elsa")))
        jackRelay = relay(folder, "jack", jack)
        elsaRelay = relay(folder, "elsa", elsa)
        jack.createChild(name: "Nora", birthDate: nil)
        sync()
        XCTAssertEqual(elsa.child?.id, jack.child?.id, "the shared baby reached the second phone")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func relay(_ folder: URL, _ name: String, _ store: EventStore) -> SimPartnerRelay {
        let defaults = UserDefaults(suiteName: "TwoPhoneTests-\(UUID().uuidString)")!
        let relay = SimPartnerRelay(folder: folder, name: name, delay: 0, persistence: store.persistence, defaults: defaults)
        return relay
    }

    /// One round of iCloud: each phone sends, then each imports and runs the
    /// refresh its remote-change notice would.
    private func sync() {
        jackRelay.send()
        elsaRelay.send()
        jackRelay.receive()
        elsaRelay.receive()
        // An import reaches the view context on the main queue, before the
        // remote-change reload a moment later.
        RunLoop.main.run(until: .now.addingTimeInterval(0.05))
        jack.refresh(force: false)
        elsa.refresh(force: false)
    }

    private func assertAgree(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(jack.events.map(\.id), elsa.events.map(\.id), "same entries in the same order", file: file, line: line)
        XCTAssertTrue(jack.summary.sameContent(as: elsa.summary), "Now says the same on both phones", file: file, line: line)
    }

    func testAPartnersFeedShowsWithItsSide() {
        jack.log(.feed, side: .left)
        sync()
        XCTAssertEqual(elsa.summary.todayFeeds, 1)
        XCTAssertEqual(elsa.summary.feedSides, [.left])
        assertAgree()
    }

    func testOnePartnerStartsASleepAndTheOtherEndsIt() {
        jack.toggleSleep()
        sync()
        XCTAssertNotNil(elsa.runningSleep, "Elsa sees the baby asleep")
        elsa.toggleSleep()
        sync()
        XCTAssertNil(jack.runningSleep, "Jack sees the baby awake")
        XCTAssertNil(jack.summary.runningSleepStart)
        assertAgree()
    }

    func testBothLoggingAtOnceKeepsBoth() {
        jack.log(.wet)
        elsa.log(.dirty)
        sync()
        XCTAssertEqual(jack.summary.todayWet, 1)
        XCTAssertEqual(jack.summary.todayDirty, 1)
        assertAgree()
    }

    func testAnUndoAfterItSyncedLeavesThePartnersPhone() {
        jack.log(.feed)
        sync()
        XCTAssertEqual(elsa.summary.todayFeeds, 1)
        XCTAssertTrue(jack.undoLast())
        sync()
        XCTAssertEqual(elsa.summary.todayFeeds, 0)
        assertAgree()
    }

    func testASideAddedAfterTheTapFollowsTheFeed() throws {
        let feed = try XCTUnwrap(jack.log(.feed))
        sync()
        feed.feedSides = [.right]
        jack.save()
        sync()
        XCTAssertEqual(elsa.summary.feedSides, [.right])
        assertAgree()
    }

    func testAnEditAndADeleteFromTheOtherPhone() throws {
        jack.log(.wet)
        jack.log(.dirty)
        sync()
        let wet = try XCTUnwrap(elsa.events.first { $0.eventKind == .wet })
        wet.startedAt = wet.start.addingTimeInterval(-600)
        elsa.save()
        XCTAssertTrue(elsa.delete(try XCTUnwrap(elsa.events.first { $0.eventKind == .dirty })))
        sync()
        XCTAssertEqual(jack.events.map(\.eventKind), [.wet])
        assertAgree()
    }

    /// The partner's tap redraws the other phone once, and a phone's own tap
    /// redraws it once: the relay's echo of it changes nothing.
    func testEachTapRedrawsEachPhoneOnce() {
        sync()
        let jackBefore = jack.revision
        let elsaBefore = elsa.revision
        jack.log(.wet)
        for _ in 0..<3 { sync() }
        XCTAssertEqual(jack.revision, jackBefore + 1)
        XCTAssertEqual(elsa.revision, elsaBefore + 1)
    }
}
