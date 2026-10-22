import CloudKit
import Foundation

/// Where one baby's entries live in CloudKit, as the app's mirroring placed
/// them: the zone, its owner, which database reaches it, and the baby's own
/// record. The app learns this from its container; the widget, which never
/// mirrors, reads it back to write a tap straight to CloudKit.
struct CloudZoneTarget: Codable, Equatable, Sendable {
    var zoneName: String
    var ownerName: String
    /// True for a baby another parent shared: reached through the shared
    /// database. False for the account's own private database.
    var isShared: Bool
    var childRecordName: String

    var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName) }

    func recordID(_ recordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    init(zoneName: String, ownerName: String, isShared: Bool, childRecordName: String) {
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.isShared = isShared
        self.childRecordName = childRecordName
    }

    /// From the child's mirrored record and the store it sits in.
    init(childRecordID: CKRecord.ID, isShared: Bool) {
        self.init(
            zoneName: childRecordID.zoneID.zoneName,
            ownerName: childRecordID.zoneID.ownerName,
            isShared: isShared,
            childRecordName: childRecordID.recordName
        )
    }
}

/// One entry's stored values, copied off the managed object so they can be
/// queued and uploaded after its context is gone.
struct CloudEventValues: Codable, Equatable, Sendable {
    var id: UUID
    var kind: String?
    var startedAt: Date?
    var endedAt: Date?
    var side: String?
    var amount: Double
    var stoolColor: String?
    var note: String?
    var createdAt: Date?
    var updatedAt: Date?

    init(_ event: LogEvent) {
        id = event.id ?? UUID()
        kind = event.kind
        startedAt = event.startedAt
        endedAt = event.endedAt
        side = event.side
        amount = event.amount
        stoolColor = event.stoolColor
        note = event.note
        createdAt = event.createdAt
        updatedAt = event.updatedAt
    }
}

/// Writes entries to CloudKit in the record layout `NSPersistentCloudKitContainer`
/// uses for `LogEvent`, so every device's container imports them as if
/// another device's app had exported them. Apple's suggested route for an
/// interactive widget, which cannot run the container's own sync.
///
/// Only fields the deployed schema already has are written: Production
/// rejects new ones.
enum CloudEventWriter {
    static let recordType = "CD_LogEvent"

    /// A complete record for an entry, named so the widget can find it again
    /// for Undo or to end a timer it started.
    static func record(for values: CloudEventValues, named recordName: String, in target: CloudZoneTarget) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: target.recordID(recordName))
        record["CD_entityName"] = "LogEvent"
        record["CD_child"] = target.childRecordName
        record["CD_id"] = values.id.uuidString
        applyAllValues(values, to: record)
        return record
    }

    /// Widget updates only stop or reopen timers. The other fields may have
    /// been edited on the partner's phone since this local snapshot was made.
    static func apply(_ values: CloudEventValues, to record: CKRecord) {
        if let remote = record["CD_updatedAt"] as? Date,
           remote > (values.updatedAt ?? .distantPast) { return }
        record["CD_endedAt"] = values.endedAt
        record["CD_updatedAt"] = values.updatedAt
    }

    private static func applyAllValues(_ values: CloudEventValues, to record: CKRecord) {
        record["CD_kind"] = values.kind
        record["CD_startedAt"] = values.startedAt
        record["CD_endedAt"] = values.endedAt
        record["CD_side"] = values.side
        record["CD_amount"] = values.amount
        record["CD_stoolColor"] = values.stoolColor
        record["CD_note"] = values.note
        record["CD_createdAt"] = values.createdAt
        record["CD_updatedAt"] = values.updatedAt
    }

    static func database(for target: CloudZoneTarget, in container: CKContainer) -> CKDatabase {
        target.isShared ? container.sharedCloudDatabase : container.privateCloudDatabase
    }
}
