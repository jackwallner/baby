import AppKit
import CloudKit
import CoreData
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

    /// Exercises the owner half of partner sharing against the real account:
    /// a `CKShare` on the baby's zone, an invitation URL, and the stop-sharing
    /// purge. The accept half needs a second iCloud account and a device.
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

        let (_, share, _) = try await source.share([child], to: nil)
        share[CKShare.SystemFieldKey.title] = "\(child.displayName)'s log" as CKRecordValue
        guard let store = child.objectID.persistentStore else { throw SchemaError.shareHasNoStore }
        let saved = try await source.persistUpdatedShare(share, in: store)

        guard let url = saved.url else { throw SchemaError.shareHasNoURL }
        report("BABY_SHARE_URL: \(url.host ?? "none")")

        let zoneID = saved.recordID.zoneID
        guard zoneID.zoneName != "com.apple.coredata.cloudkit.zone" else {
            throw SchemaError.shareNotInItsOwnZone
        }
        report("BABY_SHARE_ZONE: \(zoneID.zoneName)")

        do {
            let record = try await cloud.privateCloudDatabase.record(for: saved.recordID)
            guard let cloudShare = record as? CKShare else { throw SchemaError.shareNotInCloud }
            let owners = cloudShare.participants.filter { $0.role == .owner }
            guard owners.count == 1, cloudShare.participants.count == 1 else {
                throw SchemaError.shareNotInCloud
            }
            report("BABY_SHARE_RECORD_VERIFIED_IN_CLOUD")
            guard cloudShare.publicPermission == .none else { throw SchemaError.sharePubliclyReadable }
            report("BABY_SHARE_IS_INVITE_ONLY")
        } catch let error as CKError where error.code == .unknownItem {
            throw SchemaError.shareNotInCloud
        }

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
        case sharePubliclyReadable
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
