import CloudKit
import CoreData
import Foundation
import os

/// Logging together through iCloud: one `CKShare` on the baby's record zone,
/// so every event under that baby follows it. No accounts, no server of ours.
///
/// The share is opened as a read/write invite link. Whoever holds the link
/// (scanned from the owner's screen, or sent in Messages) joins with the same
/// rights as the owner to add, edit and delete entries. A private, contact-only
/// invite fails whenever the partner's Apple ID is not the address it was sent
/// to, which is the usual reason a second parent "can't get in".
@MainActor
final class SharingService: ObservableObject {
    static let shared = SharingService(persistence: .shared, events: .shared)

    @Published private(set) var share: CKShare?
    @Published private(set) var iCloudAvailable = false
    @Published var invitationError: String?
    /// True while iCloud is accepting an invitation, before the baby imports.
    @Published private(set) var isAcceptingInvitation = false

    private let persistence: Persistence
    private let events: EventStore
    private let logger = Logger(subsystem: AppGroup.subsystem, category: "Sharing")

    init(persistence: Persistence, share: CKShare? = nil, events: EventStore? = nil) {
        self.persistence = persistence
        self.share = share
        self.events = events ?? EventStore(persistence: persistence)
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
        // The active baby may have changed since the last async refresh.
        // Never reuse a cached invitation belonging to a different baby.
        await waitForFirstExport(of: child)
        if let existing = try persistence.container.fetchShares(matching: [child.objectID])[child.objectID] {
            share = existing
            return existing
        }
        let (_, newShare, _) = try await persistence.container.share([child], to: nil)
        newShare[CKShare.SystemFieldKey.title] = "\(child.displayName)'s log" as CKRecordValue
        share = newShare
        return newShare
    }

    /// The owner's share with its invite link switched on. A participant gets
    /// the share as it is; only the owner may change who can join.
    func inviteShare(child: Child) async throws -> CKShare {
        guard !persistence.isShared(child) else { return try await shareForPresentation(child: child) }
        await waitForFirstExport(of: child)
        let opened = try await ShareInvite.prepare(
            for: [child],
            title: "\(child.displayName)'s log",
            container: persistence.container,
            database: ckContainer.privateCloudDatabase
        )
        share = opened
        return opened
    }

    /// The link the invite QR code and "Send link" carry. Anyone already in the
    /// log can pass it on while the link is open.
    var inviteURL: URL? {
        guard let share, share.publicPermission == .readWrite else { return nil }
        return share.url
    }

    enum JoinError: Error, Equatable {
        case notAnInvite
        case iCloudUnavailable
        case ownInvite
        case unavailable

        var message: String {
            switch self {
            case .notAnInvite: "That isn't a Baby Tracker invite link. Copy the whole link your partner sent and try again."
            case .iCloudUnavailable: "Sign in to iCloud on this iPhone (Settings > your name), then try again."
            case .ownInvite: "This is your own invite. Show the code or send the link to the person joining."
            case .unavailable: "That invite couldn't be opened. Check your connection, or ask for a new link if sharing was stopped."
            }
        }
    }

    /// Joining from inside the app with a pasted link. Opening the link or
    /// scanning the code with the Camera lands in `accept(_:)` instead.
    func join(pasted text: String) async throws {
        guard let url = ShareInvite.url(in: text) else { throw JoinError.notAnInvite }
        guard (try? await ckContainer.accountStatus()) == .available else { throw JoinError.iCloudUnavailable }
        let metadata: CKShare.Metadata
        do {
            metadata = try await ckContainer.shareMetadata(for: url)
        } catch {
            logger.error("shareMetadata failed: \(String(describing: error), privacy: .public)")
            throw JoinError.unavailable
        }
        guard metadata.participantRole != .owner else { throw JoinError.ownInvite }
        isAcceptingInvitation = true
        do {
            _ = try await persistence.container.acceptShareInvitations(from: [metadata], into: persistence.sharedStore)
        } catch {
            isAcceptingInvitation = false
            logger.error("acceptShareInvitations failed: \(String(describing: error), privacy: .public)")
            throw JoinError.unavailable
        }
        finishAcceptingInvitation(in: metadata.share.recordID.zoneID, error: nil)
    }

    /// A fresh install can reach this screen before Core Data has finished its
    /// first CloudKit setup, and sharing then fails inside Core Data with a
    /// missing `ANSCKRECORDMETADATA` table rather than a useful error. An
    /// exported record is the observable proof that setup is done. Verified
    /// against the real Production container by
    /// `scripts/cloudkit-schema` `--verify-share`.
    private func waitForFirstExport(of child: Child) async {
        guard persistence.cloudKitEnabled else { return }
        let deadline = Date.now.addingTimeInterval(20)
        while Date.now < deadline {
            if persistence.container.recordID(for: child.objectID) != nil { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
        logger.error("share requested before the first CloudKit export finished")
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
        events.reload()
    }

    /// An invite link was opened or a code was scanned with the Camera. Accept
    /// it into the shared store; the baby follows on a remote-change import.
    func accept(_ metadata: CKShare.Metadata) {
        guard metadata.participantRole != .owner else {
            invitationError = JoinError.ownInvite.message
            return
        }
        invitationError = nil
        isAcceptingInvitation = true
        let zoneID = metadata.share.recordID.zoneID
        persistence.container.acceptShareInvitations(from: [metadata], into: persistence.sharedStore) { _, error in
            Task { @MainActor in
                self.finishAcceptingInvitation(in: zoneID, error: error)
            }
        }
    }

    func finishAcceptingInvitation(in zoneID: CKRecordZone.ID, error: Error?) {
        isAcceptingInvitation = false
        if let error {
            logger.error("acceptShareInvitations failed: \(String(describing: error), privacy: .public)")
            invitationError = "Check your internet connection and that iCloud is signed in, then open the invitation again. Your existing log is safe."
            return
        }
        invitationError = nil
        events.adoptSharedChildIfNeeded(in: zoneID)
    }

    /// People who joined, other than the owner, for the Settings row.
    var participantNames: [String] {
        guard let share else { return [] }
        return share.participants
            .filter { $0.role != .owner && $0.acceptanceStatus == .accepted }
            .compactMap(Self.displayName)
    }

    /// The person who started a log this account joined.
    var ownerName: String? {
        share.flatMap { Self.displayName($0.owner) }
    }

    private static func displayName(_ participant: CKShare.Participant) -> String? {
        let name = participant.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) } ?? ""
        if !name.isEmpty { return name }
        return participant.userIdentity.lookupInfo?.emailAddress ?? participant.userIdentity.lookupInfo?.phoneNumber
    }

    var isOwner: Bool {
        guard let share else { return true }
        return share.currentUserParticipant?.role == .owner
    }
}
