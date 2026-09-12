import CloudKit
import CoreData
import Foundation
import os

/// Partner sharing through iCloud: one `CKShare` on the baby's record zone,
/// so every event under that baby follows it. No accounts, no server of ours.
@MainActor
final class SharingService: ObservableObject {
    static let shared = SharingService(persistence: .shared)

    @Published private(set) var share: CKShare?
    @Published private(set) var iCloudAvailable = false

    private let persistence: Persistence
    private let logger = Logger(subsystem: AppGroup.subsystem, category: "Sharing")

    init(persistence: Persistence, share: CKShare? = nil) {
        self.persistence = persistence
        self.share = share
    }

    var ckContainer: CKContainer { CKContainer(identifier: AppGroup.cloudKitContainerID) }

    /// True when this baby arrived from someone else's iCloud.
    func isSharedChild(_ child: Child) -> Bool { persistence.isShared(child) }

    func refresh(for child: Child?) async {
        iCloudAvailable = (try? await ckContainer.accountStatus()) == .available
        guard let child, persistence.cloudKitEnabled else {
            share = nil
            return
        }
        do {
            let shares = try persistence.container.fetchShares(matching: [child.objectID])
            share = shares[child.objectID]
        } catch {
            logger.error("fetchShares failed: \(String(describing: error), privacy: .public)")
            share = nil
        }
    }

    /// Existing share, or a new one for the baby. The caller presents it.
    func shareForPresentation(child: Child) async throws -> CKShare {
        if let share { return share }
        let (_, newShare, _) = try await persistence.container.share([child], to: nil)
        newShare[CKShare.SystemFieldKey.title] = "\(child.displayName)'s log" as CKRecordValue
        share = newShare
        return newShare
    }

    /// Called from the sharing controller after it saves, and after a share is
    /// stopped, so Core Data's copy of the share matches iCloud.
    func persist(_ updated: CKShare, for child: Child) async throws {
        guard let store = child.objectID.persistentStore else { return }
        let saved = try await persistence.container.persistUpdatedShare(updated, in: store)
        share = saved
    }

    func stopped(for child: Child) async throws {
        guard let share, let store = child.objectID.persistentStore else { return }
        // Leaving someone else's share removes its local copy. Stopping our
        // own share must never purge the baby's original log.
        if persistence.isShared(child) {
            _ = try await persistence.container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: store)
        }
        self.share = nil
        EventStore.shared.reload()
    }

    /// An invite link was opened. Accept it into the shared store; the store
    /// then sees a new baby on its next remote-change notification.
    func accept(_ metadata: CKShare.Metadata) {
        persistence.container.acceptShareInvitations(from: [metadata], into: persistence.sharedStore) { _, error in
            if let error {
                self.logger.error("acceptShareInvitations failed: \(String(describing: error), privacy: .public)")
                return
            }
            Task { @MainActor in
                EventStore.shared.adoptSharedChildIfNeeded()
            }
        }
    }

    /// People on the share other than the owner, for the Settings row.
    var participantNames: [String] {
        guard let share else { return [] }
        return share.participants
            .filter { $0.role != .owner }
            .compactMap { participant in
                let name = participant.userIdentity.nameComponents.map { PersonNameComponentsFormatter().string(from: $0) } ?? ""
                if !name.isEmpty { return name }
                return participant.userIdentity.lookupInfo?.emailAddress ?? participant.userIdentity.lookupInfo?.phoneNumber
            }
    }

    var isOwner: Bool {
        guard let share else { return true }
        return share.currentUserParticipant?.role == .owner
    }
}
