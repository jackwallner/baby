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
            if CommandLine.arguments.contains("--self-test") {
                try selfTest()
                report("BABY_SELF_TEST_PASSED")
                exit(EXIT_SUCCESS)
            }
            if CommandLine.arguments.contains("--verify-shared-store") {
                try await verifyTwoStoreSetup()
                exit(EXIT_SUCCESS)
            }
            if CommandLine.arguments.contains("--watch-shares") {
                try await watchShares(in: cloud)
                exit(EXIT_SUCCESS)
            }
            if CommandLine.arguments.contains("--verify-direct-import") {
                try await verifyDirectImport(in: cloud)
                report("BABY_DIRECT_IMPORT_VERIFIED_AND_FIXTURE_REMOVED")
                exit(EXIT_SUCCESS)
            }
            if CommandLine.arguments.contains("--compare-event-layout") {
                try await compareEventLayout(in: cloud)
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
            if CommandLine.arguments.contains("--host-partner-test") {
                try await hostPartnerTest(using: container, cloud: cloud)
                exit(EXIT_SUCCESS)
            }
            if CommandLine.arguments.contains("--verify-share") {
                try await verifyShare(using: container, cloud: cloud)
                report("BABY_SHARE_VERIFIED_AND_FIXTURE_REMOVED")
                exit(EXIT_SUCCESS)
            }
            if CommandLine.arguments.contains("--verify-direct-write") {
                try await verifyDirectWrite(using: container, cloud: cloud)
                report("BABY_DIRECT_WRITE_VERIFIED_AND_FIXTURE_REMOVED")
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

    /// The owner's phone in a two-account test, played by this Mac's iCloud
    /// account: it starts a clearly named baby, logs two entries, opens an
    /// invite with the app's own `ShareInvite`, and prints the link. Then it
    /// waits for another account to join, reports every entry that account
    /// writes, answers the first one with an owner entry the other device must
    /// show, and removes the fixture at the end.
    private static func hostPartnerTest(using source: NSPersistentCloudKitContainer, cloud: CKContainer) async throws {
        let minutes = argumentValue(after: "--host-partner-test").flatMap(Double.init) ?? 30
        let name = "Two-device check"
        let child = Child.make(in: source.viewContext, name: name, birthDate: Calendar.current.date(byAdding: .day, value: -3, to: .now))
        let hostFeed = LogEvent.make(in: source.viewContext, child: child, kind: .feed, at: .now.addingTimeInterval(-3600))
        hostFeed.side = "left"
        hostFeed.endedAt = hostFeed.startedAt
        _ = LogEvent.make(in: source.viewContext, child: child, kind: .wet, at: .now.addingTimeInterval(-1800))
        try source.viewContext.save()
        guard let store = child.objectID.persistentStore else { throw SchemaError.shareHasNoStore }
        report("BABY_HOST_FIXTURE_SAVED")
        try await waitUntil(timeout: 600) { source.recordID(for: child.objectID) != nil }
        report("BABY_HOST_STORE_READY")

        let share = try await ShareInvite.prepare(for: [child], title: "\(name)'s log", container: source, database: cloud.privateCloudDatabase)
        let zoneID = share.recordID.zoneID
        guard let url = share.url else { throw SchemaError.shareHasNoURL }
        report("BABY_HOST_INVITE_URL: \(url.absoluteString)")

        var outcome = "timed out"
        defer { report("BABY_HOST_RESULT: \(outcome)") }
        do {
            let deadline = Date.now.addingTimeInterval(minutes * 60)
            var token: CKServerChangeToken?
            var joined = false
            var partnerEntries = 0
            var answered = false
            var seen: Set<CKRecord.ID> = []
            while Date.now < deadline {
                do {
                    if !joined, let live = try await cloud.privateCloudDatabase.record(for: share.recordID) as? CKShare,
                       live.participants.contains(where: { $0.role != .owner && $0.acceptanceStatus == .accepted }) {
                        joined = true
                        report("BABY_HOST_PARTNER_JOINED")
                    }
                    let changes = try await cloud.privateCloudDatabase.recordZoneChanges(inZoneWith: zoneID, since: token)
                    token = changes.changeToken
                    for (recordID, result) in changes.modificationResultsByID {
                        guard let record = try? result.get().record, record.recordType == "CD_LogEvent",
                              record.creatorUserRecordID?.recordName != CKCurrentUserDefaultName,
                              seen.insert(recordID).inserted else { continue }
                        partnerEntries += 1
                        report("BABY_HOST_PARTNER_ENTRY kind=\(record["CD_kind"] as? String ?? "?")")
                    }
                    for deletion in changes.deletions where deletion.recordType == "CD_LogEvent" {
                        report("BABY_HOST_ENTRY_DELETED")
                    }
                } catch {
                    report("BABY_HOST_RETRYING: \((error as? CKError)?.code.rawValue ?? -1)")
                }
                if partnerEntries > 0, !answered {
                    answered = true
                    let reply = LogEvent.make(in: source.viewContext, child: child, kind: .sleep, at: .now.addingTimeInterval(-600))
                    reply.endedAt = .now.addingTimeInterval(-60)
                    try source.viewContext.save()
                    try await waitUntil(timeout: 300) { source.recordID(for: reply.objectID) != nil }
                    report("BABY_HOST_OWNER_ENTRY_EXPORTED kind=sleep")
                }
                if partnerEntries >= 2 {
                    outcome = "partner joined and wrote \(partnerEntries) entries"
                    break
                }
                try await Task.sleep(for: .seconds(5))
            }
        }
        if !CommandLine.arguments.contains("--keep-fixture") {
            _ = try? await source.purgeObjectsAndRecordsInZone(with: zoneID, in: store)
            report("BABY_HOST_FIXTURE_REMOVED")
        }
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

    /// Proves the widget's direct CloudKit write: a record built by
    /// `CloudEventWriter` imports into a fresh store as a real entry of its
    /// baby, an in-place change to it imports too, the app's own export of the
    /// same tap is reduced to one copy by `DuplicateEvents`, and deleting the
    /// record (the widget's Undo) removes the entry.
    private static func verifyDirectWrite(using source: NSPersistentCloudKitContainer, cloud: CKContainer) async throws {
        let database = cloud.privateCloudDatabase
        let child = Child.make(in: source.viewContext, name: "Temporary direct write verification", birthDate: nil)
        let fixtureID = child.id!
        let reference = LogEvent.make(in: source.viewContext, child: child, kind: .wet, at: .now)
        try source.viewContext.save()
        report("BABY_DIRECT_FIXTURE: \(fixtureID.uuidString)")
        var cleanup: [CKRecord.ID] = []
        do {
            var childRecordID: CKRecord.ID?
            var referenceRecord: CKRecord?
            var lastReport = Date.distantPast
            try await waitUntil(timeout: 1500) {
                if Date.now.timeIntervalSince(lastReport) > 60 {
                    lastReport = .now
                    report("BABY_DIRECT_WAITING_EXPORT: child=\(source.recordID(for: child.objectID)?.recordName ?? "none") event=\(source.recordID(for: reference.objectID)?.recordName ?? "none")")
                }
                guard let childID = source.recordID(for: child.objectID),
                      let eventID = source.recordID(for: reference.objectID) else { return false }
                do {
                    _ = try await database.record(for: childID)
                    referenceRecord = try await database.record(for: eventID)
                    childRecordID = childID
                    return true
                } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                    return false
                }
            }
            guard let childRecordID, let referenceRecord else { throw SchemaError.syncTimedOut }
            cleanup.append(childRecordID)
            let referenceFields = referenceRecord.allKeys().sorted()
            report("BABY_REFERENCE_FIELDS: " + referenceFields.map { "\($0)=\(type(of: referenceRecord[$0]!))" }.joined(separator: ","))
            report("BABY_REFERENCE_CHILD: \(String(describing: referenceRecord["CD_child"])) child=\(childRecordID.recordName)")

            // The widget's tap, written straight to CloudKit.
            let target = CloudZoneTarget(childRecordID: childRecordID, isShared: false)
            let local = LogEvent.make(in: source.viewContext, child: child, kind: .dirty, at: .now.addingTimeInterval(-60))
            local.side = nil
            let values = CloudEventValues(local)
            let direct = CloudEventWriter.record(for: values, named: values.id.uuidString, in: target)
            let written = Set(direct.allKeys())
            let unknown = written.subtracting(referenceFields)
            report("BABY_DIRECT_FIELDS: \(written.sorted().joined(separator: ","))")
            guard unknown.isEmpty else { throw SchemaError.inviteNotOpen("fields not in the mirrored record: \(unknown.sorted())") }
            for key in written {
                guard let mine = direct[key], let theirs = referenceRecord[key] else { continue }
                guard valueKind(mine) == valueKind(theirs) else {
                    throw SchemaError.inviteNotOpen("\(key) is \(type(of: mine)) but the container writes \(type(of: theirs))")
                }
            }
            _ = try await database.modifyRecords(saving: [direct], deleting: [], savePolicy: .allKeys)
            cleanup.append(direct.recordID)
            report("BABY_DIRECT_RECORD_SAVED")

            // The app's own export of the same tap (the widget's local save).
            try source.viewContext.save()
            var appCopyID: CKRecord.ID?
            try await waitUntil(timeout: 600) {
                guard let id = source.recordID(for: local.objectID) else { return false }
                do {
                    _ = try await database.record(for: id)
                    appCopyID = id
                    return true
                } catch let error as CKError where error.code == .unknownItem {
                    return false
                }
            }
            guard let appCopyID else { throw SchemaError.syncTimedOut }
            cleanup.append(appCopyID)
            report("BABY_APP_COPY_EXPORTED: \(appCopyID.recordName)")

            // A later change, like a widget ending a sleep it started.
            let ended = Date.now
            let fetched = try await database.record(for: direct.recordID)
            fetched["CD_endedAt"] = ended
            _ = try await database.modifyRecords(saving: [fetched], deleting: [], savePolicy: .changedKeys)
            report("BABY_DIRECT_CHANGE_SAVED")

            let destination = try await makeContainer()
            func imported() throws -> [LogEvent] {
                let request = NSFetchRequest<LogEvent>(entityName: "LogEvent")
                request.predicate = NSPredicate(format: "id == %@", values.id as NSUUID)
                return try destination.viewContext.fetch(request)
            }
            try await waitUntil(timeout: 600) { try imported().count == 2 }
            let copies = try imported()
            guard copies.allSatisfy({ $0.child?.id == fixtureID && $0.kind == "dirty" }) else {
                throw SchemaError.inviteNotOpen("imported copies lost their baby or kind")
            }
            guard let viaWidget = copies.first(where: { destination.recordID(for: $0.objectID)?.recordName == values.id.uuidString }),
                  let endedAt = viaWidget.endedAt, abs(endedAt.timeIntervalSince(ended)) < 1 else {
                throw SchemaError.inviteNotOpen("the direct record or its change did not import")
            }
            report("BABY_DIRECT_RECORD_IMPORTED_WITH_CHANGE")

            let removed = DuplicateEvents.remove(in: destination.viewContext) { destination.recordID(for: $0)?.recordName }
            try destination.viewContext.save()
            guard removed == 1, try imported().count == 1,
                  destination.recordID(for: try imported()[0].objectID)?.recordName == values.id.uuidString else {
                throw SchemaError.inviteNotOpen("duplicate removal kept the wrong copy (removed \(removed))")
            }
            try await waitForDeletion(appCopyID, cloud: cloud)
            report("BABY_DUPLICATE_REMOVED_AND_EXPORTED")

            // The widget's Undo.
            _ = try await database.modifyRecords(saving: [], deleting: [direct.recordID])
            let afterUndo = try await makeContainer()
            try await waitUntil(timeout: 600) {
                let request = NSFetchRequest<Child>(entityName: "Child")
                request.predicate = NSPredicate(format: "id == %@", fixtureID as NSUUID)
                guard let baby = try afterUndo.viewContext.fetch(request).first else { return false }
                return baby.eventCount == 1
            }
            report("BABY_DIRECT_DELETE_IMPORTED")
        } catch {
            report("BABY_DIRECT_WRITE_FAILED: \(error)")
            source.viewContext.delete(child)
            try? source.viewContext.save()
            _ = try? await database.modifyRecords(saving: [], deleting: cleanup)
            throw error
        }
        source.viewContext.delete(child)
        try source.viewContext.save()
        _ = try? await database.modifyRecords(saving: [], deleting: cleanup)
        if let childID = cleanup.first { try await waitForDeletion(childID, cloud: cloud) }
    }

    /// Read-only. Finds one entry the app itself exported, in the private or
    /// shared database, and checks that `CloudEventWriter` writes the same
    /// fields with the same value kinds and points at its baby the same way.
    /// Prints field names and kinds only, never a value.
    private static func compareEventLayout(in cloud: CKContainer) async throws {
        for database in [cloud.privateCloudDatabase, cloud.sharedCloudDatabase] {
            let zones = try await database.allRecordZones()
            for zone in zones where zone.zoneID.zoneName.hasPrefix("com.apple.coredata.cloudkit") {
                var token: CKServerChangeToken?
                var event: CKRecord?
                var children: Set<String> = []
                repeat {
                    let changes = try await database.recordZoneChanges(inZoneWith: zone.zoneID, since: token)
                    for (_, result) in changes.modificationResultsByID {
                        guard let record = try? result.get().record else { continue }
                        if record.recordType == "CD_Child" { children.insert(record.recordID.recordName) }
                        if record.recordType == CloudEventWriter.recordType, event == nil { event = record }
                    }
                    token = changes.changeToken
                    if !changes.moreComing { break }
                } while event == nil
                guard let event else { continue }
                let scope = database.databaseScope == .shared ? "shared" : "private"
                let theirs = Dictionary(uniqueKeysWithValues: event.allKeys().map { ($0, valueKind(event[$0]!)) })
                report("BABY_LAYOUT_SOURCE: \(scope) zone, \(theirs.count) fields")
                report("BABY_LAYOUT_THEIRS: " + theirs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))
                let childName = event["CD_child"] as? String
                report("BABY_LAYOUT_CHILD_LINK: \(childName == nil ? "missing" : (children.contains(childName!) ? "string recordName of a CD_Child in the zone" : "string, child not in this zone"))")
                let target = CloudZoneTarget(childRecordID: CKRecord.ID(recordName: childName ?? "x", zoneID: zone.zoneID), isShared: scope == "shared")
                var values = CloudEventValues(id: UUID(), kind: "wet", startedAt: .now, endedAt: .now, side: "left", amount: 0, stoolColor: "yellow", note: "n", createdAt: .now, updatedAt: .now)
                values.amount = 1
                let mine = CloudEventWriter.record(for: values, named: values.id.uuidString, in: target)
                var problems: [String] = []
                for key in mine.allKeys() {
                    let kind = valueKind(mine[key]!)
                    if let expected = theirs[key], expected != kind { problems.append("\(key): \(kind) vs \(expected)") }
                    if theirs[key] == nil, !["CD_endedAt", "CD_side", "CD_stoolColor", "CD_note"].contains(key) {
                        problems.append("\(key): not on the app's record")
                    }
                }
                let required = Set(theirs.keys).subtracting(mine.allKeys())
                report("BABY_LAYOUT_ONLY_THEIRS: \(required.sorted().joined(separator: ","))")
                guard problems.isEmpty else {
                    report("BABY_LAYOUT_MISMATCH: \(problems.joined(separator: "; "))")
                    throw SchemaError.inviteNotOpen("layout mismatch")
                }
                report("BABY_LAYOUT_MATCHES")
                return
            }
        }
        report("BABY_LAYOUT_NO_EVENT_FOUND")
    }

    /// Development only. Writes a temporary baby and two copies of one tap
    /// straight to CloudKit, the widget's copy through `CloudEventWriter`
    /// (then changed in place, as when a widget ends a sleep) and a second
    /// one standing in for the app's later export. A fresh store must import
    /// both as entries of that baby with the change applied, and
    /// `DuplicateEvents` must keep the widget's copy. Nothing here waits on
    /// the container's own export.
    private static func verifyDirectImport(in cloud: CKContainer) async throws {
        let database = cloud.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        let fixtureID = UUID()
        let child = CKRecord(recordType: "CD_Child", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
        child["CD_entityName"] = "Child"
        child["CD_id"] = fixtureID.uuidString
        child["CD_name"] = "Temporary direct import verification"
        child["CD_createdAt"] = Date.now
        let target = CloudZoneTarget(childRecordID: child.recordID, isShared: false)
        let values = CloudEventValues(id: UUID(), kind: "sleep", startedAt: .now.addingTimeInterval(-600), endedAt: nil, side: nil, amount: 0, stoolColor: nil, note: nil, createdAt: .now, updatedAt: .now)
        let widgetCopy = CloudEventWriter.record(for: values, named: values.id.uuidString, in: target)
        let appCopy = CloudEventWriter.record(for: values, named: "0000-app-export-" + UUID().uuidString, in: target)
        let all = [child.recordID, widgetCopy.recordID, appCopy.recordID]
        report("BABY_DIRECT_IMPORT_FIXTURE: \(fixtureID.uuidString)")
        do {
            _ = try await database.modifyRecords(saving: [child, widgetCopy, appCopy], deleting: [], savePolicy: .allKeys)
            let ended = Date.now
            let fetched = try await database.record(for: widgetCopy.recordID)
            var changed = values
            changed.endedAt = ended
            changed.updatedAt = ended
            CloudEventWriter.apply(changed, to: fetched)
            _ = try await database.modifyRecords(saving: [fetched], deleting: [], savePolicy: .changedKeys)
            report("BABY_DIRECT_RECORDS_SAVED")

            let destination = try await makeContainer()
            func copies() throws -> [LogEvent] {
                let request = NSFetchRequest<LogEvent>(entityName: "LogEvent")
                request.predicate = NSPredicate(format: "id == %@", values.id as NSUUID)
                return try destination.viewContext.fetch(request)
            }
            var lastReport = Date.distantPast
            try await waitUntil(timeout: 1500) {
                let found = try copies()
                if Date.now.timeIntervalSince(lastReport) > 60 {
                    lastReport = .now
                    report("BABY_DIRECT_IMPORT_WAITING: \(found.count) copies")
                }
                return found.count == 2 && found.allSatisfy { $0.child != nil }
            }
            let found = try copies()
            guard found.allSatisfy({ $0.child?.id == fixtureID && $0.kind == "sleep" }) else {
                throw SchemaError.inviteNotOpen("imported entries lost their baby or kind")
            }
            guard let widgetEntry = found.first(where: { destination.recordID(for: $0.objectID)?.recordName == values.id.uuidString }),
                  let endedAt = widgetEntry.endedAt, abs(endedAt.timeIntervalSince(ended)) < 1 else {
                throw SchemaError.inviteNotOpen("the widget's record or its change did not import")
            }
            report("BABY_DIRECT_RECORD_IMPORTED_WITH_CHANGE")
            let removed = DuplicateEvents.remove(in: destination.viewContext) { destination.recordID(for: $0)?.recordName }
            try destination.viewContext.save()
            let left = try copies()
            guard removed == 1, left.count == 1,
                  destination.recordID(for: left[0].objectID)?.recordName == values.id.uuidString else {
                throw SchemaError.inviteNotOpen("duplicate removal kept the wrong copy (removed \(removed))")
            }
            report("BABY_DUPLICATE_FOLDED_TO_WIDGET_COPY")
        } catch {
            report("BABY_DIRECT_IMPORT_FAILED: \(error)")
            _ = try? await database.modifyRecords(saving: [], deleting: all)
            throw error
        }
        _ = try await database.modifyRecords(saving: [], deleting: all)
    }

    /// The widget sync's local logic, mirroring `WidgetCloudSyncTests`, for a
    /// Mac with no free simulator. Uses an in-memory store and no CloudKit.
    private static func selfTest() throws {
        func check(_ condition: Bool, _ what: String) throws {
            report((condition ? "ok   " : "FAIL ") + what)
            if !condition { throw SchemaError.inviteNotOpen(what) }
        }
        let container = NSPersistentContainer(name: "Baby", managedObjectModel: BabyModel.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, _ in }
        let context = container.viewContext
        let target = CloudZoneTarget(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName, isShared: false, childRecordName: "child-record")
        for key in [AppGroup.Key.widgetCloudOps, AppGroup.Key.undoneEventIDs, AppGroup.Key.cloudTargets, AppGroup.Key.cloudRecordNames] {
            AppGroup.defaults.removeObject(forKey: key)
        }
        let child = Child.make(in: context, name: "Nora", birthDate: nil)

        let feed = LogEvent.make(in: context, child: child, kind: .feed, at: .now)
        feed.side = "left"
        let values = CloudEventValues(feed)
        let record = CloudEventWriter.record(for: values, named: values.id.uuidString, in: target)
        try check(record.recordType == "CD_LogEvent" && record["CD_entityName"] as? String == "LogEvent"
                  && record["CD_child"] as? String == "child-record" && record["CD_id"] as? String == values.id.uuidString
                  && record["CD_kind"] as? String == "feed" && record["CD_side"] as? String == "left" && record["CD_endedAt"] == nil,
                  "record uses the mirrored layout")
        var shared = target
        shared.isShared = true
        try check(CloudEventWriter.database(for: shared, in: CKContainer(identifier: "iCloud.com.jackwallner.baby")).databaseScope == .shared,
                  "a shared baby writes to the shared database")

        func event(_ id: UUID, updatedAt: Date = .now) -> LogEvent {
            let e = LogEvent.make(in: context, child: child, kind: .wet, at: .now)
            e.id = id
            e.updatedAt = updatedAt
            return e
        }
        let id = UUID()
        let widgetCopy = event(id)
        let appCopy = event(id)
        let other = event(UUID())
        try context.save()
        let names = [widgetCopy.objectID: id.uuidString, appCopy.objectID: "0000-app-export", other.objectID: "other"]
        let removed = DuplicateEvents.remove(in: context) { names[$0] }
        try check(removed == 1 && appCopy.isDeleted && !widgetCopy.isDeleted && !other.isDeleted, "the widget's copy wins even against a lower name")
        try context.save()

        let id2 = UUID()
        let imported = event(id2, updatedAt: .now.addingTimeInterval(-60))
        let local = event(id2)
        local.endedAt = .now
        try context.save()
        _ = DuplicateEvents.remove(in: context) { $0 == imported.objectID ? "Z-record" : nil }
        try check(local.isDeleted && imported.endedAt != nil, "an unexported copy loses and its newer edit moves over")
        try context.save()

        let id3 = UUID()
        let first = event(id3)
        let second = event(id3)
        try context.save()
        let ranked = [first.objectID: "B", second.objectID: "A"]
        _ = DuplicateEvents.remove(in: context) { ranked[$0] }
        try check(first.isDeleted && !second.isDeleted, "the lowest record name wins otherwise")
        try context.save()

        let sleep = LogEvent.make(in: context, child: child, kind: .sleep, at: .now)
        let name = sleep.id!.uuidString
        let start = WidgetCloudOp(action: .create, recordName: name, values: CloudEventValues(sleep), target: target)
        sleep.endedAt = .now
        let end = WidgetCloudOp(action: .update, recordName: name, values: CloudEventValues(sleep), target: target)
        let folded = WidgetCloudSync.fold([start], [end])
        try check(folded.count == 1 && folded[0].action == .create && folded[0].values?.endedAt != nil, "start then end before upload is one create")
        let undone = WidgetCloudSync.fold(folded, [WidgetCloudOp(action: .delete, recordName: name, values: nil, target: target)])
        try check(undone.map(\.action) == [.delete], "add then undo is only a delete")

        let old = WidgetCloudOp(action: .create, recordName: "old", values: nil, target: target, queuedAt: .now.addingTimeInterval(-120))
        let fresh = WidgetCloudOp(action: .create, recordName: "fresh", values: nil, target: target, queuedAt: .now)
        WidgetCloudSync.enqueue([old, fresh])
        WidgetCloudSync.dropExported(before: .now.addingTimeInterval(-60))
        try check(WidgetCloudSync.pending().map(\.recordName) == ["fresh"], "the app drops uploads it already exported")

        let partners = UUID()
        let mine = UUID()
        let baby = UUID()
        WidgetCloudSync.publish(targets: [baby: target], recordNames: [partners: "core-data-name"])
        try check(WidgetCloudSync.recordName(for: partners) == "core-data-name" && WidgetCloudSync.recordName(for: mine) == mine.uuidString,
                  "record names fall back to the entry id")
        try check(WidgetCloudSync.target(for: baby) == target && WidgetCloudSync.target(for: UUID()) == nil, "targets round-trip per baby")

        let stone = UUID()
        WidgetCloudSync.markUndone(stone, at: .now.addingTimeInterval(-WidgetCloudSync.tombstoneLifetime - 1))
        try check(WidgetCloudSync.undoneIDs().isEmpty, "old tombstones expire")
        WidgetCloudSync.markUndone(stone)
        try check(WidgetCloudSync.undoneIDs() == [stone], "fresh tombstones stay")
        for key in [AppGroup.Key.widgetCloudOps, AppGroup.Key.undoneEventIDs, AppGroup.Key.cloudTargets, AppGroup.Key.cloudRecordNames] {
            AppGroup.defaults.removeObject(forKey: key)
        }
    }

    private static func valueKind(_ value: Any) -> String {
        switch value {
        case is String: "string"
        case is Date: "date"
        case is NSNumber: "number"
        default: "\(type(of: value))"
        }
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

/// Sample values for the layout check, built without a managed object.
extension CloudEventValues {
    init(id: UUID, kind: String?, startedAt: Date?, endedAt: Date?, side: String?, amount: Double, stoolColor: String?, note: String?, createdAt: Date?, updatedAt: Date?) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.side = side
        self.amount = amount
        self.stoolColor = stoolColor
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
