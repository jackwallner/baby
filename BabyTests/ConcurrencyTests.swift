import CloudKit
import CoreData
import XCTest
@testable import Baby

private final class RecordMap: @unchecked Sendable {
    private let lock = NSLock()
    private var zone = "before-sharing"

    func moveToSharedZone() { lock.withLock { zone = "after-sharing" } }

    func recordID(_ objectID: NSManagedObjectID) -> CKRecord.ID {
        let name = lock.withLock { zone }
        return CKRecord.ID(recordName: objectID.uriRepresentation().lastPathComponent,
                           zoneID: CKRecordZone.ID(zoneName: name))
    }
}

@MainActor
private final class ActivityClient: LiveActivityClient {
    var areActivitiesEnabled = true
    var activities: [LiveActivitySnapshot] = []
    var requests = 0

    func end(_ id: String) async {
        await Task.yield()
        activities.removeAll { $0.id == id }
    }

    func update(_ id: String, to state: LiveActivityState) async {
        await Task.yield()
        if let index = activities.firstIndex(where: { $0.id == id }) { activities[index].state = state }
    }

    func request(_ state: LiveActivityState) {
        requests += 1
        activities.append(LiveActivitySnapshot(id: String(requests), state: state))
    }
}

@MainActor
final class ConcurrencyTests: XCTestCase {
    func testAnUndoDuringActivityShutdownRestartsTheActivity() async throws {
        let client = ActivityClient()
        let service = LiveActivityService(client: client)
        var summary = NowSummary()
        summary.childID = UUID()
        summary.runningSleepStart = .now.addingTimeInterval(-300)
        service.sync(summary: summary)
        await service.waitForUpdates()
        service.sync(summary: .empty)
        service.sync(summary: summary)
        await service.waitForUpdates()
        XCTAssertEqual(client.activities.count, 1, "an activity already ending cannot be reused")
        XCTAssertEqual(client.activities.first?.state, LiveActivityState(summary: summary))
    }

    func testDisablingActivitiesStillEndsAnExistingTimer() async {
        let client = ActivityClient()
        let service = LiveActivityService(client: client)
        var summary = NowSummary()
        summary.runningSleepStart = .now
        service.sync(summary: summary)
        await service.waitForUpdates()
        client.areActivitiesEnabled = false
        service.sync(summary: .empty)
        await service.waitForUpdates()
        XCTAssertTrue(client.activities.isEmpty)
    }

    func testSwitchingBetweenIdenticallyNamedBabiesReplacesTheActivity() async {
        let client = ActivityClient()
        let service = LiveActivityService(client: client)
        var summary = NowSummary()
        summary.childID = UUID()
        summary.runningSleepStart = .now
        service.sync(summary: summary)
        await service.waitForUpdates()
        summary.childID = UUID()
        service.sync(summary: summary)
        await service.waitForUpdates()
        XCTAssertEqual(client.activities.first?.state.childID, summary.childID)
        XCTAssertEqual(client.activities.count, 1)
    }

    func testPartnerTimerEditsUpdateTheExistingActivity() async {
        let client = ActivityClient()
        let service = LiveActivityService(client: client)
        var summary = NowSummary()
        summary.childID = UUID()
        summary.runningFeedStart = .now.addingTimeInterval(-300)
        summary.setRunningFeedSides([.left])
        service.sync(summary: summary)
        await service.waitForUpdates()
        summary.runningFeedStart = summary.runningFeedStart?.addingTimeInterval(-60)
        summary.setRunningFeedSides([.right])
        summary.childName = "Nora"
        service.sync(summary: summary)
        await service.waitForUpdates()
        XCTAssertEqual(client.requests, 1, "a background import must update without requesting a new activity")
        XCTAssertEqual(client.activities.first?.state, LiveActivityState(summary: summary))
    }

    func testPartnerWakeEndsTheLiveActivityThroughTheStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ActivityClient()
        let service = LiveActivityService(client: client)
        let app = EventStore(persistence: Persistence(cloudKit: false, directory: directory), liveActivities: service)
        app.createChild(name: "Nora", birthDate: nil)
        app.startTimed(.sleep, at: .now.addingTimeInterval(-300))
        await service.waitForUpdates()
        XCTAssertEqual(client.activities.count, 1)
        let partner = Persistence(cloudKit: false, directory: directory)
        let context = partner.newBackgroundContext()
        try context.performAndWait {
            context.transactionAuthor = "NSCloudKitMirroringDelegate.import"
            let child = try XCTUnwrap(partner.allChildren(in: context).first)
            for sleep in partner.runningEvents(.sleep, for: child, in: context) { sleep.endedAt = .now }
            try context.save()
        }
        app.refresh(force: false)
        await service.waitForUpdates()
        XCTAssertTrue(client.activities.isEmpty)
    }

    func testAWatchReceiptCarriesTheCommittedSummary() throws {
        let store = EventStore(persistence: Persistence(cloudKit: false, inMemory: true))
        store.createChild(name: "Nora", birthDate: nil)
        let payload = WatchLogPayload(action: .log, kind: .wet)
        XCTAssertTrue(store.apply(payload))
        let receipt = WatchSyncService.receipt(for: payload.id, summary: store.summary)
        let data = try XCTUnwrap(receipt["summary"] as? Data)
        let snapshot = try JSONDecoder().decode(NowSummary.self, from: data)
        XCTAssertTrue(snapshot.sameContent(as: store.summary))
        XCTAssertEqual(snapshot.todayWet, 1)
        XCTAssertEqual(receipt["savedWatchAction"] as? String, payload.id.uuidString)
        let next = WatchLogPayload(action: .log, kind: .dirty)
        XCTAssertEqual(snapshot.applyingPending([next]).todayWet, 1,
                       "releasing a saved tap must not erase it when the next tap is replayed")
    }

    func testSharingRefreshesWidgetTargetsWithoutChangingObjectIDs() async throws {
        let records = RecordMap()
        let store = EventStore(persistence: Persistence(cloudKit: false, inMemory: true),
                               cloudRecordID: { records.recordID($0) })
        store.createChild(name: "Nora", birthDate: nil)
        let id = try XCTUnwrap(store.child?.id)
        await store.waitForCloudTargets()
        XCTAssertEqual(WidgetCloudSync.target(for: id)?.zoneName, "before-sharing")
        records.moveToSharedZone()
        store.cloudRecordsChanged()
        store.refresh(force: false)
        await store.waitForCloudTargets()
        XCTAssertEqual(WidgetCloudSync.target(for: id)?.zoneName, "after-sharing",
                       "a share changes the CloudKit zone while the managed object ID stays the same")
    }
}
