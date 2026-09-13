import CloudKit
import CoreData
import UIKit
import XCTest
@testable import Baby

@MainActor
final class SharingTests: XCTestCase {
    override func setUp() async throws {
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.pendingSharedZone)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
    }

    override func tearDown() async throws {
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.pendingSharedZone)
    }

    func testAcceptedInviteWaitsForItsBabyAcrossRestartWithoutDeletingProfiles() throws {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let invitedZone = CKRecordZone.ID(zoneName: "InvitedBaby", ownerName: "OtherParent")
        let olderZone = CKRecordZone.ID(zoneName: "ExistingShare", ownerName: "AnotherParent")
        let resolve: (Child) -> CKRecordZone.ID? = { $0.name == "Shared Nora" ? invitedZone : olderZone }
        let events = EventStore(persistence: persistence, sharedZoneID: resolve)
        events.createChild(name: "Local baby", birthDate: nil)
        let localID = try XCTUnwrap(events.child?.id)
        events.log(.wet)
        let emptyProfile = Child.make(in: persistence.viewContext, name: "Future baby", birthDate: nil)
        persistence.viewContext.assign(emptyProfile, to: persistence.privateStore)
        let existingShare = Child.make(in: persistence.viewContext, name: "Already shared", birthDate: nil)
        persistence.viewContext.assign(existingShare, to: persistence.sharedStore)
        persistence.save(persistence.viewContext)

        let sharing = SharingService(persistence: persistence, events: events)
        sharing.finishAcceptingInvitation(in: invitedZone, error: nil)
        XCTAssertEqual(events.child?.id, localID, "Do not select a different shared baby while the invitation imports")
        XCTAssertNotNil(AppGroup.defaults.object(forKey: AppGroup.Key.pendingSharedZone))

        let invited = Child.make(in: persistence.viewContext, name: "Shared Nora", birthDate: nil)
        persistence.viewContext.assign(invited, to: persistence.sharedStore)
        persistence.save(persistence.viewContext)
        let restarted = EventStore(persistence: persistence, sharedZoneID: resolve)

        XCTAssertEqual(restarted.child?.id, invited.id)
        XCTAssertNil(AppGroup.defaults.object(forKey: AppGroup.Key.pendingSharedZone))
        XCTAssertEqual(restarted.children.count, 4, "Accepting a share must preserve other babies, even empty profiles")
        let local = try XCTUnwrap(restarted.children.first(where: { $0.id == localID }))
        XCTAssertEqual(local.eventCount, 1)
    }

    func testFailedAcceptanceShowsAnErrorAndKeepsTheCurrentLog() {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let events = EventStore(persistence: persistence)
        events.createChild(name: "Nora", birthDate: nil)
        events.log(.feed)
        let childID = events.child?.id
        let sharing = SharingService(persistence: persistence, events: events)

        sharing.finishAcceptingInvitation(in: CKRecordZone.ID(zoneName: "Invite"), error: CKError(.networkFailure))

        XCTAssertNotNil(sharing.invitationError)
        XCTAssertNil(AppGroup.defaults.object(forKey: AppGroup.Key.pendingSharedZone))
        XCTAssertEqual(events.child?.id, childID)
        XCTAssertEqual(events.events.count, 1)
    }

    func testSceneDelegateReceivesColdStartInvitations() {
        let delegate = SceneDelegate()
        XCTAssertTrue(delegate.responds(to: #selector(UISceneDelegate.scene(_:willConnectTo:options:))))
        XCTAssertTrue(delegate.responds(to: #selector(UIWindowSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:))))
    }

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

    func testInviteLinkIsFoundInsideAPastedMessage() {
        let message = "Join Nora's log in Baby Tracker https://www.icloud.com/share/0abcDEF123#Nora_s_log thanks"
        XCTAssertEqual(SharingService.inviteURL(in: message)?.absoluteString, "https://www.icloud.com/share/0abcDEF123#Nora_s_log")
        XCTAssertNotNil(SharingService.inviteURL(in: "icloud.com/share/0abc"))
    }

    func testNonInviteLinksAreRejected() {
        XCTAssertNil(SharingService.inviteURL(in: "https://example.com/share/0abc"))
        XCTAssertNil(SharingService.inviteURL(in: "https://www.icloud.com/photos/0abc"))
        XCTAssertNil(SharingService.inviteURL(in: "nothing here"))
    }

    func testNewOwnerShareIsOpenedAsAnEditableInviteLink() {
        let share = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "TestBaby"))
        XCTAssertTrue(SharingService.needsOpenInvite(share), "A private share would reject a partner whose Apple ID differs from the invited address")
        share.publicPermission = .readWrite
        XCTAssertFalse(SharingService.needsOpenInvite(share))
    }

    func testPastingSomethingElseFailsBeforeTouchingICloud() async {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let sharing = SharingService(persistence: persistence, events: EventStore(persistence: persistence))
        do {
            try await sharing.join(pasted: "https://example.com/not-an-invite")
            XCTFail("A non-invite link must not be accepted")
        } catch let error as SharingService.JoinError {
            XCTAssertEqual(error, .notAnInvite)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}
