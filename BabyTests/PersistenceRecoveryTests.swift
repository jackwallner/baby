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
}
