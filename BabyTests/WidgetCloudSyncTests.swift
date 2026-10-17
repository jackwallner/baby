import CloudKit
import CoreData
import XCTest
@testable import Baby

@MainActor
final class WidgetCloudSyncTests: XCTestCase {
    private var persistence: Persistence!
    private var context: NSManagedObjectContext { persistence.viewContext }
    private let target = CloudZoneTarget(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName, isShared: false, childRecordName: "child-record")

    override func setUp() async throws {
        persistence = Persistence(cloudKit: false, inMemory: true)
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
        XCTAssertEqual(DuplicateEvents.remove(in: context) { $0 == imported.objectID ? "Z-record" : nil }, 1)
        XCTAssertTrue(local.isDeleted, "a copy that never left this phone always loses")
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

    func testAppDropsUploadsItAlreadyExported() {
        let old = WidgetCloudOp(action: .create, recordName: "old", values: nil, target: target, queuedAt: .now.addingTimeInterval(-120))
        let fresh = WidgetCloudOp(action: .create, recordName: "fresh", values: nil, target: target, queuedAt: .now)
        WidgetCloudSync.enqueue([old, fresh])
        WidgetCloudSync.dropExported(before: .now.addingTimeInterval(-60))
        XCTAssertEqual(WidgetCloudSync.pending().map(\.recordName), ["fresh"])
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
}
