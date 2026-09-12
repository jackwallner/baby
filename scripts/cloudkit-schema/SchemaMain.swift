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
            let container = try await makeContainer()
            if CommandLine.arguments.contains("--list-children") {
                try await listChildren(in: container)
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
            try await waitUntil {
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
            try await waitUntil {
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

    private static func waitUntil(_ condition: () async throws -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(120)
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
    }
}
