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
        XCTAssertEqual(ShareInvite.url(in: message)?.absoluteString, "https://www.icloud.com/share/0abcDEF123#Nora_s_log")
        XCTAssertNotNil(ShareInvite.url(in: "icloud.com/share/0abc"))
    }

    func testNonInviteLinksAreRejected() {
        XCTAssertNil(ShareInvite.url(in: "https://example.com/share/0abc"))
        XCTAssertNil(ShareInvite.url(in: "https://www.icloud.com/photos/0abc"))
        XCTAssertNil(ShareInvite.url(in: "nothing here"))
    }

    func testNewOwnerShareIsOpenedAsAnEditableInviteLink() {
        let share = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "TestBaby"))
        XCTAssertTrue(ShareInvite.needsOpening(share), "A private share would reject a partner whose Apple ID differs from the invited address")
        share.publicPermission = .readWrite
        XCTAssertFalse(ShareInvite.needsOpening(share))
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

    // MARK: - The joining parent's side

    /// Every way a tap reaches the log must write into the shared store when
    /// the active baby came from someone else, or it never reaches them.
    func testEveryLoggingPathOnASharedBabyWritesToTheSharedStore() throws {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let shared = Child.make(in: persistence.viewContext, name: "Shared Nora", birthDate: .now)
        persistence.viewContext.assign(shared, to: persistence.sharedStore)
        persistence.save(persistence.viewContext)
        AppGroup.defaults.set(shared.id?.uuidString, forKey: AppGroup.Key.activeChildID)
        let events = EventStore(persistence: persistence)
        XCTAssertEqual(events.child?.objectID, shared.objectID)

        XCTAssertNotNil(events.log(.wet))
        XCTAssertNotNil(events.log(.feed, side: .left))
        XCTAssertNotNil(events.log(.dirty) { $0.note = "from the editor" })
        XCTAssertNotNil(events.startTimed(.sleep))
        XCTAssertTrue(events.stopRunning(.sleep))
        XCTAssertTrue(events.apply(WatchLogPayload(id: UUID(), action: .log, kind: .wet, side: nil, at: .now, childID: shared.id), forChildID: shared.id))

        let all = persistence.events(for: shared, in: persistence.viewContext)
        XCTAssertEqual(all.count, 5)
        XCTAssertTrue(all.allSatisfy { $0.objectID.persistentStore == persistence.sharedStore }, "An entry in the private store would never reach the other parent")
        XCTAssertEqual(events.summary.todayWet, 2)
    }

    func testJoiningStateLastsUntilTheInvitedBabyArrives() throws {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let zone = CKRecordZone.ID(zoneName: "InvitedBaby", ownerName: "OtherParent")
        let events = EventStore(persistence: persistence, sharedZoneID: { _ in zone })
        let sharing = SharingService(persistence: persistence, events: events)

        sharing.finishAcceptingInvitation(in: zone, error: nil)
        XCTAssertTrue(events.isAwaitingSharedBaby)
        XCTAssertFalse(sharing.isAcceptingInvitation)
        XCTAssertNil(events.arrivedSharedChild)

        let invited = Child.make(in: persistence.viewContext, name: "Nora", birthDate: nil)
        persistence.viewContext.assign(invited, to: persistence.sharedStore)
        persistence.save(persistence.viewContext)
        events.reload()

        XCTAssertFalse(events.isAwaitingSharedBaby)
        XCTAssertEqual(events.child?.objectID, invited.objectID)
        XCTAssertEqual(events.arrivedSharedChild?.objectID, invited.objectID)
    }

    func testGivingUpOnAnInvitationKeepsEverything() {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let events = EventStore(persistence: persistence)
        let sharing = SharingService(persistence: persistence, events: events)
        sharing.finishAcceptingInvitation(in: CKRecordZone.ID(zoneName: "Slow"), error: nil)
        XCTAssertTrue(events.isAwaitingSharedBaby)

        events.stopWaitingForSharedBaby()

        XCTAssertFalse(events.isAwaitingSharedBaby)
        XCTAssertNil(AppGroup.defaults.object(forKey: AppGroup.Key.pendingSharedZone))
    }

    func testEntriesLoggedBeforeJoiningMoveIntoTheSharedBaby() throws {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let events = EventStore(persistence: persistence)
        events.createChild(name: "My Nora", birthDate: nil)
        let separate = try XCTUnwrap(events.child)
        let feed = try XCTUnwrap(events.log(.feed, side: .bottle) { $0.amount = 60; $0.note = "hospital" })
        let feedID = feed.id
        let feedStart = feed.startedAt
        events.log(.dirty) { $0.stool = .yellow }
        let emptyProfile = Child.make(in: persistence.viewContext, name: "Future baby", birthDate: nil)
        persistence.viewContext.assign(emptyProfile, to: persistence.privateStore)
        let shared = Child.make(in: persistence.viewContext, name: "Nora", birthDate: nil)
        persistence.viewContext.assign(shared, to: persistence.sharedStore)
        persistence.save(persistence.viewContext)
        events.reload()

        let separateLogs = events.separateLogs(besides: shared)
        XCTAssertEqual(separateLogs.map(\.objectID), [separate.objectID], "Only a private baby with entries is offered; empty profiles are left alone")

        XCTAssertEqual(events.moveEvents(from: separate, into: shared), 2)

        let moved = persistence.events(for: shared, in: persistence.viewContext)
        XCTAssertEqual(moved.count, 2)
        XCTAssertTrue(moved.allSatisfy { $0.objectID.persistentStore == persistence.sharedStore })
        let movedFeed = try XCTUnwrap(moved.first { $0.eventKind == .feed })
        XCTAssertEqual(movedFeed.id, feedID)
        XCTAssertEqual(movedFeed.startedAt, feedStart)
        XCTAssertEqual(movedFeed.feedSide, .bottle)
        XCTAssertEqual(movedFeed.amount, 60)
        XCTAssertEqual(movedFeed.note, "hospital")
        XCTAssertEqual(moved.first { $0.eventKind == .dirty }?.stool, .yellow)
        XCTAssertFalse(events.children.contains { $0.objectID == separate.objectID }, "The emptied separate profile is removed")
        XCTAssertTrue(events.children.contains { $0.objectID == emptyProfile.objectID })
        XCTAssertEqual(events.child?.objectID, shared.objectID)
    }

    func testJoinFormReportsANonInviteLink() async {
        let persistence = Persistence(cloudKit: false, inMemory: true)
        let sharing = SharingService(persistence: persistence, events: EventStore(persistence: persistence))
        let model = JoinLogModel()
        XCTAssertFalse(model.canJoin)
        model.link = "https://example.com/not-an-invite"
        XCTAssertTrue(model.canJoin)
        await model.join(using: sharing)
        XCTAssertEqual(model.phase, .failed(SharingService.JoinError.notAnInvite.message))
    }
}
