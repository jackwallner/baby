import CloudKit
import UIKit
import XCTest
@testable import Baby

@MainActor
final class SharingTests: XCTestCase {
    func testFailedInvitationDoesNotSignalStopSharing() {
        var failed = false
        var stopped = false
        let coordinator = CloudSharingController.Coordinator(finished: { outcome in
            switch outcome {
            case .failed: failed = true
            case .stopped: stopped = true
            case .saved: XCTFail("A failed invitation must not report success")
            }
        }, title: "Nora")
        coordinator.cloudSharingController(UICloudSharingController(), failedToSaveShareWithError: CKError(.networkFailure))
        XCTAssertTrue(failed)
        XCTAssertFalse(stopped, "A network failure must never trigger removal of the shared log")
    }

    func testOwnerKeepsBabyAndLogWhenStoppingSharing() async throws {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let events = EventStore(persistence: persistence)
        events.createChild(name: "Nora", birthDate: .now)
        let child = try XCTUnwrap(events.child)
        events.log(.wet)
        let share = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "TestBaby"))
        let sharing = SharingService(persistence: persistence, share: share)

        try await sharing.stopped(for: child)

        XCTAssertNil(sharing.share)
        XCTAssertEqual(persistence.allChildren(in: persistence.viewContext).count, 1)
        XCTAssertEqual(persistence.events(for: child, in: persistence.viewContext).count, 1)
    }
}
