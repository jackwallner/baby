import CloudKit
import CoreData
import XCTest
@testable import Baby

private actor SuspendedUpload {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var actions: [WidgetCloudOp.Action] = []
    var isWaiting: Bool { continuation != nil }

    func send(_ ops: [WidgetCloudOp]) async -> Set<WidgetCloudRecordKey> {
        actions.append(contentsOf: ops.map(\.action))
        if actions.count == 1 { await withCheckedContinuation { continuation = $0 } }
        return Set(ops.map(\.key))
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class WidgetCloudSyncTests: XCTestCase {
    private var persistence: Persistence!
    private var context: NSManagedObjectContext { persistence.viewContext }
    private let target = CloudZoneTarget(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName, isShared: false, childRecordName: "child-record")

    override func setUp() async throws {
        persistence = Persistence(cloudKit: false, inMemory: true)
        try? FileManager.default.removeItem(at: WidgetCloudSync.queueDirectory)
        for key in [AppGroup.Key.widgetCloudOps, AppGroup.Key.undoneEventIDs, AppGroup.Key.cloudTargets, AppGroup.Key.cloudRecordNames] {
            AppGroup.defaults.removeObject(forKey: key)
        }
    }

    private func makeEvent(id: UUID, kind: EventKind = .wet, child: Child, updatedAt: Date = .now) -> LogEvent {
        let event = LogEvent.make(in: context, child: child, kind: kind, at: .now)
        event.id = id
        event.updatedAt = updatedAt
        return event
    }

    func testRecordUsesTheMirroredLayout() {
        let child = Child.make(in: context, name: "Nora", birthDate: nil)
        let event = LogEvent.make(in: context, child: child, kind: .feed, at: .now)
        event.feedSide = .left
        let values = CloudEventValues(event)
        let record = CloudEventWriter.record(for: values, named: values.id.uuidString, in: target)
        XCTAssertEqual(record.recordType, "CD_LogEvent")
        XCTAssertEqual(record.recordID.zoneID.zoneName, target.zoneName)
        XCTAssertEqual(record["CD_entityName"] as? String, "LogEvent")
        XCTAssertEqual(record["CD_child"] as? String, "child-record")
        XCTAssertEqual(record["CD_id"] as? String, values.id.uuidString)
        XCTAssertEqual(record["CD_kind"] as? String, "feed")
        XCTAssertEqual(record["CD_side"] as? String, "left")
        XCTAssertNil(record["CD_endedAt"], "a feed with no end has no end field")
    }

    func testSharedBabyWritesToTheSharedDatabase() {
        let container = CKContainer(identifier: AppGroup.cloudKitContainerID)
        var shared = target
        shared.isShared = true
        XCTAssertEqual(CloudEventWriter.database(for: shared, in: container).databaseScope, .shared)
        XCTAssertEqual(CloudEventWriter.database(for: target, in: container).databaseScope, .private)
    }

    func testDuplicateRemovalKeepsTheWidgetCopyEverywhere() throws {
        let child = Child.make(in: context, name: "Nora", birthDate: nil)
        let id = UUID()
        let widgetCopy = makeEvent(id: id, child: child)
        let appCopy = makeEvent(id: id, child: child)
        let other = makeEvent(id: UUID(), child: child)
        try context.save()
        let names = [widgetCopy.objectID: id.uuidString, appCopy.objectID: "0000-app-export", other.objectID: "other"]
        XCTAssertEqual(DuplicateEvents.remove(in: context) { names[$0] }, 1)
        try context.save()
        let left = persistence.events(ids: [id], in: context)
        XCTAssertEqual(left.map(\.objectID), [widgetCopy.objectID], "the widget's record wins even against a lower name")
        XCTAssertFalse(other.isDeleted)
    }

    func testDuplicateRemovalDropsTheUnexportedCopyAndKeepsTheNewerEdit() throws {
        let child = Child.make(in: context, name: "Nora", birthDate: nil)
        let id = UUID()
        let imported = makeEvent(id: id, child: child, updatedAt: .now.addingTimeInterval(-60))
        let local = makeEvent(id: id, child: child, updatedAt: .now)
        local.endedAt = .now
        try context.save()
        XCTAssertEqual(DuplicateEvents.remove(in: context) { $0 == imported.objectID ? "Z-record" : nil }, 0)
        XCTAssertEqual(DuplicateEvents.remove(in: context) { $0 == imported.objectID ? "Z-record" : "ZZ-local" }, 1)
        XCTAssertTrue(local.isDeleted, "cleanup waits until both record names are known")
        XCTAssertNotNil(imported.endedAt, "the losing copy's newer edit moves to the keeper")
    }

    func testDuplicateRemovalRanksTheSameWayWhateverTheFetchOrder() throws {
        let child = Child.make(in: context, name: "Nora", birthDate: nil)
        let id = UUID()
        let first = makeEvent(id: id, child: child)
        let second = makeEvent(id: id, child: child)
        try context.save()
        let names = [first.objectID: "B", second.objectID: "A"]
        _ = DuplicateEvents.remove(in: context) { names[$0] }
        XCTAssertTrue(first.isDeleted)
        XCTAssertFalse(second.isDeleted, "the lowest record name wins when neither is the widget's")
    }

    func testQueueFoldsChangesToTheSameRecord() {
        let child = Child.make(in: context, name: "Nora", birthDate: nil)
        let sleep = LogEvent.make(in: context, child: child, kind: .sleep, at: .now)
        let name = sleep.id!.uuidString
        let start = WidgetCloudOp(action: .create, recordName: name, values: CloudEventValues(sleep), target: target)
        sleep.endedAt = .now
        let end = WidgetCloudOp(action: .update, recordName: name, values: CloudEventValues(sleep), target: target)
        let folded = WidgetCloudSync.fold([start], [end])
        XCTAssertEqual(folded.count, 1)
        XCTAssertEqual(folded[0].action, .create, "a sleep started and ended before uploading is one whole record")
        XCTAssertNotNil(folded[0].values?.endedAt)
        let undone = WidgetCloudSync.fold(folded, [WidgetCloudOp(action: .delete, recordName: name, values: nil, target: target)])
        XCTAssertEqual(undone.map(\.action), [.delete])
    }

    func testAppRetainsUploadsUntilExportIsConfirmed() {
        let old = WidgetCloudOp(action: .create, recordName: "old", values: nil, target: target, queuedAt: .now.addingTimeInterval(-120))
        let fresh = WidgetCloudOp(action: .create, recordName: "fresh", values: nil, target: target, queuedAt: .now)
        WidgetCloudSync.enqueue([old, fresh])
        WidgetCloudSync.prune()
        XCTAssertEqual(WidgetCloudSync.pending().map(\.recordName), ["old", "fresh"])
    }

    func testRecordNamesFallBackToTheEntryID() {
        let mine = UUID()
        let partners = UUID()
        WidgetCloudSync.publish(targets: [:], recordNames: [partners: "core-data-name"])
        XCTAssertEqual(WidgetCloudSync.recordName(for: partners), "core-data-name")
        XCTAssertEqual(WidgetCloudSync.recordName(for: mine), mine.uuidString)
    }

    func testTargetsRoundTripPerBaby() {
        let baby = UUID()
        WidgetCloudSync.publish(targets: [baby: target], recordNames: [:])
        XCTAssertEqual(WidgetCloudSync.target(for: baby), target)
        XCTAssertNil(WidgetCloudSync.target(for: UUID()))
    }

    func testTombstonesExpire() {
        let id = UUID()
        WidgetCloudSync.markUndone(id, at: .now.addingTimeInterval(-WidgetCloudSync.tombstoneLifetime - 1))
        XCTAssertEqual(WidgetCloudSync.undoneIDs(), [])
        WidgetCloudSync.markUndone(id)
        XCTAssertEqual(WidgetCloudSync.undoneIDs(), [id])
    }

    func testUnresolvedCopiesWaitForStableCloudRecordNames() throws {
        let child = Child.make(in: context, name: "Nora", birthDate: nil)
        let id = UUID()
        _ = makeEvent(id: id, child: child)
        _ = makeEvent(id: id, child: child)
        try context.save()
        XCTAssertEqual(DuplicateEvents.remove(in: context) { _ in nil }, 0,
                       "two phones must not delete different copies before names resolve")
        XCTAssertEqual(persistence.events(ids: [id], in: context).count, 2)
    }

    func testDuplicateIDsInDifferentBabiesKeepBothLogs() throws {
        let first = Child.make(in: context, name: "First", birthDate: nil)
        let second = Child.make(in: context, name: "Second", birthDate: nil)
        let id = UUID()
        _ = makeEvent(id: id, child: first)
        _ = makeEvent(id: id, child: second)
        try context.save()
        XCTAssertEqual(DuplicateEvents.remove(in: context) { $0.uriRepresentation().absoluteString }, 0)
        XCTAssertEqual(persistence.events(ids: [id], in: context).count, 2)
    }

    func testQueueDoesNotFoldDifferentZonesTogether() {
        var other = target
        other.zoneName = "another-baby"
        let first = WidgetCloudOp(action: .delete, recordName: "same-name", target: target)
        let second = WidgetCloudOp(action: .delete, recordName: "same-name", target: other)
        XCTAssertEqual(WidgetCloudSync.fold([first], [second]).count, 2)
    }

    func testLaunchingTheAppDoesNotDiscardAnUnsentCloudDelete() {
        let deletion = WidgetCloudOp(action: .delete, recordName: "undone", target: target,
                                     queuedAt: .now.addingTimeInterval(-120))
        WidgetCloudSync.enqueue([deletion])
        WidgetCloudSync.prune()
        XCTAssertEqual(WidgetCloudSync.pending(), [deletion],
                       "the app cannot export deletion of a direct record it has never imported")
    }

    func testConcurrentEnqueuesKeepEveryOperation() {
        let target = target
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            WidgetCloudSync.enqueue([WidgetCloudOp(action: .delete, recordName: "concurrent-\(index)", target: target)])
        }
        XCTAssertEqual(Set(WidgetCloudSync.pending().map(\.recordName)).count, 64)
    }

    func testTimerUpdatePreservesAPartnersOtherFields() {
        let child = Child.make(in: context, name: "Nora", birthDate: nil)
        let sleep = LogEvent.make(in: context, child: child, kind: .sleep, at: .now)
        let record = CloudEventWriter.record(for: CloudEventValues(sleep), named: "sleep", in: target)
        record["CD_note"] = "partner's note"
        record["CD_startedAt"] = sleep.start.addingTimeInterval(-60)
        sleep.endedAt = .now
        sleep.updatedAt = .now
        CloudEventWriter.apply(CloudEventValues(sleep), to: record)
        XCTAssertEqual(record["CD_note"] as? String, "partner's note")
        XCTAssertEqual(record["CD_startedAt"] as? Date, sleep.start.addingTimeInterval(-60))
        XCTAssertEqual(record["CD_endedAt"] as? Date, sleep.endedAt)
    }

    func testAnUndoQueuedDuringUploadIsSentAfterTheCreate() async {
        let upload = SuspendedUpload()
        WidgetCloudSync.enqueue([WidgetCloudOp(action: .create, recordName: "one", target: target)])
        let first = Task { await WidgetCloudSync.flush { await upload.send($0) } }
        while !(await upload.isWaiting) { await Task.yield() }
        WidgetCloudSync.enqueue([WidgetCloudOp(action: .delete, recordName: "one", target: target)])
        let competing = await WidgetCloudSync.flush { await upload.send($0) }
        XCTAssertFalse(competing, "an overlapping flush must not send a delete ahead of an in-flight create")
        await upload.resume()
        let success = await first.value
        XCTAssertTrue(success)
        let actions = await upload.actions
        XCTAssertEqual(actions, [.create, .delete])
        XCTAssertTrue(WidgetCloudSync.pending().isEmpty)
    }

    func testConcurrentUndoTombstonesKeepEveryID() {
        let ids = (0..<64).map { _ in UUID() }
        DispatchQueue.concurrentPerform(iterations: ids.count) { index in WidgetCloudSync.markUndone(ids[index]) }
        XCTAssertEqual(Set(WidgetCloudSync.undoneIDs()), Set(ids))
    }

    func testWidgetSummaryCountsCopiesOnceAndUsesTheLatestTimerState() throws {
        let child = Child.make(in: context, name: "Nora", birthDate: nil)
        let id = UUID()
        let older = makeEvent(id: id, kind: .feed, child: child, updatedAt: .now.addingTimeInterval(-60))
        let newer = makeEvent(id: id, kind: .feed, child: child)
        newer.endedAt = .now
        let summary = NowSummary.make(child: child, events: [older, newer])
        XCTAssertEqual(summary.todayFeeds, 1)
        XCTAssertNil(summary.runningFeedStart, "a stale duplicate must not keep the timer running")
        XCTAssertEqual(EventStore.shown([older, newer]).first, newer)
    }

    func testUnacknowledgedDeletesSurviveLongOfflineGaps() {
        let deletion = WidgetCloudOp(action: .delete, recordName: "offline-undo", target: target,
                                     queuedAt: .now.addingTimeInterval(-WidgetCloudSync.queueLifetime * 4))
        WidgetCloudSync.enqueue([deletion])
        WidgetCloudSync.prune()
        XCTAssertEqual(WidgetCloudSync.pending(), [deletion])
    }

    func testAStaleWidgetTimerCannotOverwriteANewerTimerEdit() {
        let child = Child.make(in: context, name: "Nora", birthDate: nil)
        let sleep = LogEvent.make(in: context, child: child, kind: .sleep, at: .now.addingTimeInterval(-600))
        let values = CloudEventValues(sleep)
        let record = CloudEventWriter.record(for: values, named: "sleep", in: target)
        let ended = Date.now
        record["CD_endedAt"] = ended
        record["CD_updatedAt"] = ended.addingTimeInterval(60)
        CloudEventWriter.apply(values, to: record)
        XCTAssertEqual(record["CD_endedAt"] as? Date, ended)
    }
}
