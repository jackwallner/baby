import AppKit
import CloudKit
import CoreData
import CoreImage
import Foundation

/// A setup tool, never part of the iPhone app. It uses the real model and
/// an isolated temporary store, without purchases or user-created records.
@main
@MainActor
struct SchemaMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { await run() }
        app.run()
    }

    private static func report(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func run() async {
        do {
            let environment = Bundle.main.object(forInfoDictionaryKey: "SchemaCloudKitEnvironment") as? String ?? "Unknown"
            report("BABY_CLOUD_ENVIRONMENT: \(environment)")
            if CommandLine.arguments.contains("--initialize-development"), environment != "Development" {
                throw SchemaError.wrongEnvironment
            }
            let cloud = CKContainer(identifier: "iCloud.com.jackwallner.baby")
            guard try await cloud.accountStatus() == .available else {
                throw SchemaError.noAccount
            }
            // These two open no store of their own, so they run before the
            // single-store container exists. A stray extra store would show up
            // in the two-store setup check as a third identifier.
            if CommandLine.arguments.contains("--verify-shared-store") {
                try await verifyTwoStoreSetup()
                exit(EXIT_SUCCESS)
            }
            if CommandLine.arguments.contains("--watch-shares") {
                try await watchShares(in: cloud)
                exit(EXIT_SUCCESS)
            }
            if CommandLine.arguments.contains("--purge-share-zones") {
                try await purgeShareZones(in: cloud)
                exit(EXIT_SUCCESS)
            }
            let container = try await makeContainer()
            if CommandLine.arguments.contains("--list-children") {
                try await listChildren(in: container)
                exit(EXIT_SUCCESS)
            }
            if CommandLine.arguments.contains("--verify-share") {
                try await verifyShare(using: container, cloud: cloud)
                report("BABY_SHARE_VERIFIED_AND_FIXTURE_REMOVED")
                exit(EXIT_SUCCESS)
            }
            if CommandLine.arguments.contains("--verify-sync") {
                try await verifySync(using: container, cloud: cloud)
                report("BABY_CLOUD_SYNC_VERIFIED_AND_FIXTURE_REMOVED")
                exit(EXIT_SUCCESS)
            }
            let dryRun = !CommandLine.arguments.contains("--initialize-development")
            let options: NSPersistentCloudKitContainerSchemaInitializationOptions = dryRun
                ? [.dryRun, .printSchema] : [.printSchema]
            try container.initializeCloudKitSchema(options: options)
            report(dryRun ? "BABY_SCHEMA_VALIDATION_SUCCEEDED" : "BABY_SCHEMA_INITIALIZATION_SUCCEEDED")
            exit(EXIT_SUCCESS)
        } catch {
            report("BABY_SCHEMA_FAILED: \(error)")
            exit(EXIT_FAILURE)
        }
    }

    /// Imports the account's babies into a fresh store and names them, so a
    /// leftover verification fixture cannot hide in Production.
    private static func listChildren(in container: NSPersistentCloudKitContainer) async throws {
        try await Task.sleep(for: .seconds(30))
        let request = NSFetchRequest<Child>(entityName: "Child")
        let children = try container.viewContext.fetch(request)
        report("BABY_CLOUD_CHILD_COUNT: \(children.count)")
        for child in children {
            report("BABY_CLOUD_CHILD: \(child.name ?? "(unnamed)")")
        }
    }

    /// Exercises the owner half of logging together against the real account:
    /// a `CKShare` on the baby's zone opened by the app's own `ShareInvite`,
    /// the link resolving back to that baby, the QR code decoding to the link,
    /// and the stop-sharing purge. Accepting needs a second iCloud account.
    private static func verifyShare(using source: NSPersistentCloudKitContainer, cloud: CKContainer) async throws {
        let child = Child.make(in: source.viewContext, name: "Temporary share verification", birthDate: nil)
        let fixtureID = child.id!
        _ = LogEvent.make(in: source.viewContext, child: child, kind: .wet, at: .now)
        try source.viewContext.save()
        report("BABY_SHARE_FIXTURE: \(fixtureID.uuidString)")

        // Sharing before mirroring has finished its first setup fails inside
        // Core Data with a missing ANSCKRECORDMETADATA table. A completed
        // export is the observable proof that setup is done.
        try await waitUntil(timeout: 600) { source.recordID(for: child.objectID) != nil }
        report("BABY_SHARE_STORE_READY")

        guard let store = child.objectID.persistentStore else { throw SchemaError.shareHasNoStore }
        var zoneID: CKRecordZone.ID?

        do {
            // The app's exact invite routine: share the baby and open the link.
            let saved = try await ShareInvite.prepare(for: [child], title: "\(child.displayName)'s log", container: source, database: cloud.privateCloudDatabase)
            zoneID = saved.recordID.zoneID
            guard saved.recordID.zoneID.zoneName != "com.apple.coredata.cloudkit.zone" else {
                throw SchemaError.shareNotInItsOwnZone
            }
            report("BABY_SHARE_ZONE: \(saved.recordID.zoneID.zoneName)")
            guard let url = saved.url else { throw SchemaError.shareHasNoURL }
            report("BABY_SHARE_URL_HOST: \(url.host ?? "none")")

            let cached = try source.fetchShares(in: store).first { $0.recordID == saved.recordID }
            guard cached?.publicPermission == .readWrite else { throw SchemaError.inviteNotOpen("Core Data cache") }
            report("BABY_SHARE_CORE_DATA_CACHE_IS_OPEN")

            let record = try await cloud.privateCloudDatabase.record(for: saved.recordID)
            guard let cloudShare = record as? CKShare,
                  cloudShare.participants.filter({ $0.role == .owner }).count == 1 else {
                throw SchemaError.shareNotInCloud
            }
            guard cloudShare.publicPermission == .readWrite else { throw SchemaError.inviteNotOpen("iCloud record") }
            report("BABY_SHARE_CLOUD_RECORD_IS_READ_WRITE_LINK")

            // What the second phone does first with a scanned or pasted link.
            let metadata = try await cloud.shareMetadata(for: url)
            guard metadata.share.recordID == saved.recordID,
                  metadata.share.publicPermission == .readWrite,
                  metadata.participantRole == .owner else {
                throw SchemaError.inviteNotOpen("share metadata")
            }
            report("BABY_SHARE_LINK_RESOLVES_TO_THIS_BABY")

            let pasted = "Join \(child.displayName)'s log in Baby Tracker so we can both log feeds, diapers and sleep. \(url.absoluteString)"
            guard ShareInvite.url(in: pasted) == url else { throw SchemaError.inviteNotOpen("pasted message parse") }
            report("BABY_SHARE_PASTED_MESSAGE_PARSES")

            guard let code = ShareInvite.qrCode(for: url),
                  let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
                  let decoded = detector.features(in: CIImage(cgImage: code)).compactMap({ ($0 as? CIQRCodeFeature)?.messageString }).first,
                  let decodedURL = URL(string: decoded),
                  ShareInvite.url(in: decoded) == decodedURL,
                  decodedURL == url else {
                throw SchemaError.inviteNotOpen("QR round trip")
            }
            report("BABY_SHARE_QR_CODE_DECODES_TO_LINK")

            // Stopping from Apple's sheet deletes the share record on the
            // server and nothing else. Inviting again must still work.
            _ = try await cloud.privateCloudDatabase.deleteRecord(withID: saved.recordID)
            report("BABY_SHARE_STOPPED_ON_SERVER")
            let again = try await ShareInvite.prepare(for: [child], title: "\(child.displayName)'s log", container: source, database: cloud.privateCloudDatabase)
            guard let againRecord = try await cloud.privateCloudDatabase.record(for: again.recordID) as? CKShare,
                  againRecord.publicPermission == .readWrite,
                  let againURL = againRecord.url else {
                throw SchemaError.inviteNotOpen("re-invite after stop")
            }
            let againMetadata = try await cloud.shareMetadata(for: againURL)
            guard againMetadata.share.publicPermission == .readWrite else { throw SchemaError.inviteNotOpen("re-invite metadata") }
            zoneID = again.recordID.zoneID
            report("BABY_SHARE_REINVITE_AFTER_STOP_WORKS same_zone=\(again.recordID.zoneID == saved.recordID.zoneID) new_link=\(againURL != url)")
        } catch {
            if let zoneID { _ = try? await source.purgeObjectsAndRecordsInZone(with: zoneID, in: store) }
            throw error
        }
        guard let zoneID else { throw SchemaError.shareHasNoStore }
        let saved = try source.fetchShares(in: store).first { $0.recordID.zoneID == zoneID } ?? CKShare(recordZoneID: zoneID)

        _ = try await source.purgeObjectsAndRecordsInZone(with: zoneID, in: store)
        try await waitUntil {
            do {
                _ = try await cloud.privateCloudDatabase.record(for: saved.recordID)
                return false
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                return true
            }
        }
        report("BABY_SHARE_STOPPED_AND_ZONE_PURGED")
    }

    /// Watches the signed-in account's shared babies from the server's side
    /// while two real phones run the app: who joined each log, and every entry
    /// written into it, labelled by whether the owner or someone else wrote it.
    /// Read-only. A partner's entry showing up here is proof it crossed from
    /// their iCloud account into the owner's log.
    private static func watchShares(in cloud: CKContainer) async throws {
        let minutes = argumentValue(after: "--watch-shares").flatMap(Double.init) ?? 60
        let deadline = Date.now.addingTimeInterval(minutes * 60)
        let database = cloud.privateCloudDatabase
        var tokens: [CKRecordZone.ID: CKServerChangeToken] = [:]
        var seenEntries: Set<CKRecord.ID> = []
        var seenPeople: Set<String> = []
        var seenZones: Set<CKRecordZone.ID> = []
        report("BABY_WATCH_STARTED minutes=\(Int(minutes))")
        while Date.now < deadline {
            do {
                try await watchPass()
            } catch {
                // A dropped connection must not end a watch that runs for hours.
                report("BABY_WATCH_RETRYING: \((error as? CKError)?.code.rawValue ?? -1)")
            }
            try await Task.sleep(for: .seconds(8))
        }
        report("BABY_WATCH_FINISHED")

        func watchPass() async throws {
            let zones = try await database.allRecordZones()
                .filter { $0.zoneID.zoneName.hasPrefix("com.apple.coredata.cloudkit.share.") }
            for zone in zones {
                let zoneID = zone.zoneID
                let short = String(zoneID.zoneName.suffix(8))
                if !seenZones.contains(zoneID) {
                    seenZones.insert(zoneID)
                    report("BABY_WATCH_SHARED_LOG zone=\(short)")
                }
                let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
                let shareResult: CKShare?
                do {
                    shareResult = try await database.record(for: shareID) as? CKShare
                } catch {
                    shareResult = nil
                    let line = "zone=\(short) no-share-record: \((error as? CKError)?.code.rawValue ?? -1)"
                    if seenPeople.insert(line).inserted { report("BABY_WATCH_SHARE \(line)") }
                }
                if let share = shareResult {
                    let summary = "zone=\(short) link=\(share.publicPermission == .readWrite ? "read-write" : share.publicPermission == .none ? "invite-only" : "read-only") others=\(share.participants.filter { $0.role != .owner }.count)"
                    if seenPeople.insert(summary).inserted { report("BABY_WATCH_SHARE \(summary)") }
                    for participant in share.participants where participant.role != .owner {
                        let name = participant.userIdentity.nameComponents
                            .map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) } ?? "unnamed"
                        let status = switch participant.acceptanceStatus {
                        case .accepted: "accepted"
                        case .pending: "pending"
                        case .removed: "removed"
                        default: "unknown"
                        }
                        let line = "zone=\(short) person=\(name) status=\(status) link=\(share.publicPermission == .readWrite ? "read-write" : "\(share.publicPermission.rawValue)")"
                        if seenPeople.insert(line).inserted { report("BABY_WATCH_PARTICIPANT \(line)") }
                    }
                }
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: tokens[zoneID])
                tokens[zoneID] = changes.changeToken
                for (recordID, result) in changes.modificationResultsByID {
                    guard let record = try? result.get().record, record.recordType == "CD_LogEvent" else { continue }
                    let creator = record.creatorUserRecordID?.recordName ?? "?"
                    let editor = record.lastModifiedUserRecordID?.recordName ?? "?"
                    let by = creator == CKCurrentUserDefaultName ? "owner" : "someone-else"
                    let editedBy = editor == CKCurrentUserDefaultName ? "owner" : "someone-else"
                    let kind = record["CD_kind"] as? String ?? "?"
                    let verb = seenEntries.insert(recordID).inserted ? "ENTRY" : "ENTRY_EDITED"
                    report("BABY_WATCH_\(verb) zone=\(short) kind=\(kind) created_by=\(by) last_edit_by=\(editedBy) at=\(ISO8601DateFormatter().string(from: record.modificationDate ?? .now))")
                }
                for deletion in changes.deletions where deletion.recordType == "CD_LogEvent" {
                    report("BABY_WATCH_ENTRY_DELETED zone=\(short)")
                }
            }
        }
    }

    private static func argumentValue(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Removes the share zones a failed verification can leave behind. Core
    /// Data names every one of them `com.apple.coredata.cloudkit.share.*`, and
    /// the app's own records live in `com.apple.coredata.cloudkit.zone`.
    private static func purgeShareZones(in cloud: CKContainer) async throws {
        let zones = try await cloud.privateCloudDatabase.allRecordZones()
        let strays = zones.filter { $0.zoneID.zoneName.hasPrefix("com.apple.coredata.cloudkit.share.") }
        report("BABY_SHARE_ZONE_COUNT: \(strays.count)")
        for zone in strays {
            try await cloud.privateCloudDatabase.deleteRecordZone(withID: zone.zoneID)
            report("BABY_SHARE_ZONE_DELETED: \(zone.zoneID.zoneName)")
        }
    }

    /// The app opens two stores, and only the `.shared` one receives a baby
    /// another parent invited us to. A single-store check never touches that
    /// half, so this mirrors `Persistence` and waits for both stores to report
    /// a successful CloudKit setup.
    private static func verifyTwoStoreSetup() async throws {
        let log = SetupLog()
        let token = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            log.record(event)
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let container = try await makeTwoStoreContainer()
        let scopes = container.persistentStoreDescriptions.compactMap {
            $0.cloudKitContainerOptions?.databaseScope
        }
        guard scopes.contains(.private), scopes.contains(.shared) else {
            throw SchemaError.storeScopesWrong
        }
        do {
            // A cold two-store setup runs well past the default deadline: the
            // single-store case alone took over two minutes on this account.
            try await waitUntil(timeout: 600) {
                if let (store, error) = log.firstFailure {
                    throw SchemaError.storeSetupFailed(store, error)
                }
                return log.succeededCount == 2
            }
        } catch {
            report("BABY_SETUP_EVENTS_SEEN: \(log.summary)")
            throw error
        }
        report("BABY_BOTH_STORES_SET_UP")
    }

    private static func makeTwoStoreContainer() async throws -> NSPersistentCloudKitContainer {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BabyStores-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = NSPersistentCloudKitContainer(name: "Baby", managedObjectModel: BabyModel.model)
        let privateDescription = NSPersistentStoreDescription(url: directory.appendingPathComponent("private.sqlite"))
        let sharedDescription = NSPersistentStoreDescription(url: directory.appendingPathComponent("shared.sqlite"))
        for description in [privateDescription, sharedDescription] {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.jackwallner.baby")
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.jackwallner.baby")
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions
        container.persistentStoreDescriptions = [privateDescription, sharedDescription]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var remaining = 2
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error); remaining = -1; return }
                remaining -= 1
                if remaining == 0 { continuation.resume() }
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    private static func makeContainer() async throws -> NSPersistentCloudKitContainer {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BabySchema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = NSPersistentCloudKitContainer(name: "Baby", managedObjectModel: BabyModel.model)
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("schema.sqlite"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.jackwallner.baby"
        )
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    private static func verifySync(using source: NSPersistentCloudKitContainer, cloud: CKContainer) async throws {
        let child = Child.make(in: source.viewContext, name: "Temporary cloud verification", birthDate: nil)
        let fixtureID = child.id!
        let event = LogEvent.make(in: source.viewContext, child: child, kind: .wet, at: .now)
        try source.viewContext.save()
        report("BABY_SYNC_FIXTURE: \(fixtureID.uuidString)")
        var recordIDs: [CKRecord.ID] = []
        do {
            // The first export cannot start until CloudKit setup finishes, and
            // a cold setup on this account runs well past two minutes. The
            // default deadline turns that wait into a false sync failure.
            try await waitUntil(timeout: 600) {
                recordIDs = [child.objectID, event.objectID].compactMap { source.recordID(for: $0) }
                guard recordIDs.count == 2 else { return false }
                do {
                    for recordID in recordIDs {
                        _ = try await cloud.privateCloudDatabase.record(for: recordID)
                    }
                    return true
                } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                    return false
                }
            }
            report("BABY_SYNC_EXPORT_VERIFIED")
            let destination = try await makeContainer()
            try await waitUntil(timeout: 600) {
                let request = NSFetchRequest<Child>(entityName: "Child")
                request.predicate = NSPredicate(format: "id == %@", fixtureID as NSUUID)
                guard let imported = try destination.viewContext.fetch(request).first else { return false }
                return imported.name == child.name && imported.eventCount == 1
            }
            report("BABY_SYNC_FRESH_STORE_IMPORT_VERIFIED")
        } catch {
            source.viewContext.delete(child)
            try source.viewContext.save()
            for recordID in recordIDs { try await waitForDeletion(recordID, cloud: cloud) }
            throw error
        }
        source.viewContext.delete(child)
        try source.viewContext.save()
        for recordID in recordIDs { try await waitForDeletion(recordID, cloud: cloud) }
    }

    private static func waitForDeletion(_ recordID: CKRecord.ID, cloud: CKContainer) async throws {
        try await waitUntil {
            do {
                _ = try await cloud.privateCloudDatabase.record(for: recordID)
                return false
            } catch let error as CKError where error.code == .unknownItem {
                return true
            }
        }
    }

    private static func waitUntil(timeout: TimeInterval = 120, _ condition: () async throws -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .seconds(2))
        }
        throw SchemaError.syncTimedOut
    }

    enum SchemaError: Error {
        case noAccount
        case syncTimedOut
        case wrongEnvironment
        case shareHasNoStore
        case shareHasNoURL
        case shareNotInCloud
        case shareNotInItsOwnZone
        case inviteNotOpen(String)
        case storeScopesWrong
        case storeSetupFailed(String, Error)
    }

    /// Setup events arrive on Core Data's own queue, so this is locked.
    private final class SetupLog: @unchecked Sendable {
        private let lock = NSLock()
        private var succeeded: Set<String> = []
        private var failures: [(String, Error)] = []
        private var allTypes: Set<String> = []

        func record(_ event: NSPersistentCloudKitContainer.Event) {
            lock.lock()
            allTypes.insert("\(event.type.rawValue):\(event.storeIdentifier):\(event.endDate == nil ? "open" : "done")")
            lock.unlock()
            guard event.type == .setup, event.endDate != nil else { return }
            lock.lock()
            defer { lock.unlock() }
            if let error = event.error { failures.append((event.storeIdentifier, error)) }
            else { succeeded.insert(event.storeIdentifier) }
        }

        var succeededCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return succeeded.count
        }

        var summary: String {
            lock.lock()
            defer { lock.unlock() }
            let ok = succeeded.sorted().joined(separator: ",")
            let bad = failures.map { "\($0.0)=\($0.1)" }.joined(separator: ",")
            return "succeeded=[\(ok)] failed=[\(bad)] allEvents=\(allTypes.sorted().joined(separator: ","))"
        }

        var firstFailure: (String, Error)? {
            lock.lock()
            defer { lock.unlock() }
            return failures.first
        }
    }
}
