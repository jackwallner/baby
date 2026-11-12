import CoreData
import XCTest
@testable import Baby

/// A store that will not open must never end the process: a parent who taps
/// the app and gets a crash has no way back in. These cover the two shapes a
/// shut store takes on a phone, and the crash report that prompted them
/// (build 15, a background launch from a CloudKit push).
final class PersistenceRecoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: directory.appendingPathComponent(file).path
            )
        }
        try? FileManager.default.removeItem(at: directory)
    }

    func testACorruptStoreIsMovedAsideAndTheLogStillOpens() throws {
        let store = directory.appendingPathComponent("private.sqlite")
        try Data("not a database".utf8).write(to: store)

        let persistence = Persistence(cloudKit: false, directory: directory)

        XCTAssertFalse(persistence.isStandingIn, "a fresh file replaced the corrupt one")
        let child = Child.make(in: persistence.viewContext, name: "Nora", birthDate: nil)
        persistence.viewContext.assign(child, to: persistence.privateStore)
        XCTAssertTrue(persistence.save(persistence.viewContext), "logging works after the recovery")

        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("private.sqlite.unopenable-") }
        XCTAssertEqual(kept.count, 1, "the old file is moved aside, never deleted")
    }

    func testAStoreThatDataProtectionKeepsShutIsLeftAloneAndWritesAreRefused() throws {
        // A locked phone reads like this: the file is there and intact, and
        // opening it fails with a permission error. It must not be moved
        // aside, and nothing may be written where it would be lost.
        let store = directory.appendingPathComponent("private.sqlite")
        let seeded = Persistence(cloudKit: false, directory: directory)
        let child = Child.make(in: seeded.viewContext, name: "Nora", birthDate: nil)
        seeded.viewContext.assign(child, to: seeded.privateStore)
        XCTAssertTrue(seeded.save(seeded.viewContext))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: store.path)

        let persistence = Persistence(cloudKit: false, directory: directory)

        XCTAssertTrue(persistence.isStandingIn, "the app opens rather than crashing")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: store.path),
            "a locked file is not a corrupt one: the log stays where it is"
        )
        let added = Child.make(in: persistence.viewContext, name: "Ada", birthDate: nil)
        persistence.viewContext.assign(added, to: persistence.privateStore)
        XCTAssertFalse(persistence.save(persistence.viewContext), "a write that would vanish is refused")
    }

    func testBusyAndFullDisksDoNotReplaceAHealthySharedDatabase() {
        for error in [
            NSError(domain: NSSQLiteErrorDomain, code: 5),
            NSError(domain: NSSQLiteErrorDomain, code: 13),
            NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)),
            NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreTimeoutError),
            NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreIncompatibleVersionHashError),
        ] {
            XCTAssertFalse(Persistence.isCorrupt(error), "\(error) must not move a healthy log aside")
        }
    }

    /// Build 83 crashed 0.2 s after launch inside Core Data's mirroring
    /// delegate: the duplicate cleanup asked for record names before CloudKit
    /// setup had finished. Lookups wait until both stores report setup.
    func testRecordLookupsWaitForCloudKitSetupOnBothStores() {
        let stores: [String?] = ["private", "shared"]
        XCTAssertFalse(Persistence.cloudKitReady(standingIn: false, stores: stores, setUp: []))
        XCTAssertFalse(Persistence.cloudKitReady(standingIn: false, stores: stores, setUp: ["private"]))
        XCTAssertTrue(Persistence.cloudKitReady(standingIn: false, stores: stores, setUp: ["private", "shared"]))
        XCTAssertFalse(Persistence.cloudKitReady(standingIn: true, stores: stores, setUp: ["private", "shared"]))
        XCTAssertFalse(Persistence.cloudKitReady(standingIn: false, stores: [nil, "shared"], setUp: ["shared"]))
    }

    func testAStackWithoutCloudKitNeverAsksForRecordIDs() throws {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let child = Child.make(in: persistence.viewContext, name: "Nora", birthDate: nil)
        XCTAssertTrue(persistence.save(persistence.viewContext))
        XCTAssertFalse(persistence.isCloudKitReady)
        XCTAssertNil(persistence.recordID(for: child.objectID))
    }

    /// The build 83 tester could not open the app: every launch died inside
    /// a record lookup for one entry with broken CloudKit metadata. A launch
    /// after a death never asks about that entry again, in any build.
    func testALookupThatKilledTheProcessIsNeverRepeated() throws {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let context = persistence.viewContext
        let child = Child.make(in: context, name: "Nora", birthDate: nil)
        let bad = LogEvent.make(in: context, child: child, kind: .feed, at: .now)
        let good = LogEvent.make(in: context, child: child, kind: .wet, at: .now)
        try context.obtainPermanentIDs(for: [child, bad, good])
        let dir = directory!

        // The process dies inside the lookup: the marker is left behind.
        var guardian = CloudKitLookupGuard(directory: dir, enabled: true)
        _ = guardian.run(for: bad.objectID) {
            let markers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in markers where name.hasSuffix(".cloudkit-lookup") {
                try? FileManager.default.copyItem(
                    atPath: dir.appendingPathComponent(name).path,
                    toPath: dir.appendingPathComponent("left-" + name).path
                )
            }
        }

        guardian = CloudKitLookupGuard(directory: dir, enabled: true)
        XCTAssertTrue(guardian.isSkipped(bad.objectID))
        XCTAssertNil(guardian.run(for: bad.objectID) { 1 })
        XCTAssertEqual(guardian.run(for: good.objectID) { 1 }, 1)
        XCTAssertTrue(CloudKitLookupGuard(directory: dir, enabled: true).isSkipped(bad.objectID),
                      "the skip outlives the launch that found it")
    }

    func testAReturnedOrThrownLookupLeavesNoMarker() throws {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let child = Child.make(in: persistence.viewContext, name: "Nora", birthDate: nil)
        try persistence.viewContext.obtainPermanentIDs(for: [child])
        let guardian = CloudKitLookupGuard(directory: directory, enabled: true)
        struct Failed: Error {}
        XCTAssertEqual(guardian.run(for: child.objectID) { 1 }, 1)
        XCTAssertThrowsError(try guardian.run(for: child.objectID) { throw Failed() })
        XCTAssertFalse(CloudKitLookupGuard(directory: directory, enabled: true).isSkipped(child.objectID))
    }

    func testAWidgetNeverTakesTheAppsRunningLookupForACrash() throws {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let child = Child.make(in: persistence.viewContext, name: "Nora", birthDate: nil)
        try persistence.viewContext.obtainPermanentIDs(for: [child])
        let app = CloudKitLookupGuard(directory: directory, enabled: true)
        _ = app.run(for: child.objectID) {
            let widget = CloudKitLookupGuard(directory: directory, enabled: false)
            XCTAssertFalse(widget.isSkipped(child.objectID))
        }
        XCTAssertFalse(CloudKitLookupGuard(directory: directory, enabled: true).isSkipped(child.objectID))
    }
}
