import CloudKit
import CoreData
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Turns a baby's share into something another person can join. The app and
/// `scripts/cloudkit-schema` both compile this file, so the Production check
/// exercises the code that ships rather than a copy of it.
///
/// The invite is a read/write link. A contact-only invite is rejected whenever
/// the other parent's Apple ID is not the address it was sent to, which is the
/// usual reason a second parent "can't get in".
@MainActor
enum ShareInvite {
    /// Only the owner may change who can join; a participant's copy is left alone.
    static func needsOpening(_ share: CKShare) -> Bool {
        let isOwner = share.currentUserParticipant.map { $0.role == .owner } ?? true
        return isOwner && share.publicPermission != .readWrite
    }

    enum PrepareError: Error {
        case notSaved
    }

    /// The owner's live, joinable share for a baby: the existing one if iCloud
    /// still has it, otherwise a new one. Core Data keeps its cached share after
    /// sharing is stopped from Apple's sheet, so the cache alone is never trusted.
    static func prepare(
        for objects: [NSManagedObject],
        title: String,
        container: NSPersistentCloudKitContainer,
        database: CKDatabase
    ) async throws -> CKShare {
        guard let first = objects.first, let store = first.objectID.persistentStore else { throw PrepareError.notSaved }
        if let cached = try container.fetchShares(matching: [first.objectID])[first.objectID] {
            do {
                if let live = try await database.record(for: cached.recordID) as? CKShare {
                    return try await open(live, in: store, container: container, database: database)
                }
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                // Stopped from Apple's sheet: fall through and share again.
            }
        }
        let (_, share, _) = try await container.share(objects, to: nil)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        return try await open(share, in: store, container: container, database: database, force: true)
    }

    /// Saves the open permission to iCloud, then hands the server's copy back
    /// to Core Data so its cached share matches.
    static func open(
        _ share: CKShare,
        in store: NSPersistentStore,
        container: NSPersistentCloudKitContainer,
        database: CKDatabase,
        force: Bool = false
    ) async throws -> CKShare {
        guard force || needsOpening(share) else { return share }
        share.publicPermission = .readWrite
        let result = try await database.modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys)
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw CKError(.internalError)
        }
        return try await container.persistUpdatedShare(saved, in: store)
    }

    /// Pulls an iCloud share link out of whatever was pasted or scanned: a bare
    /// link, a link without its scheme, or a whole message with the link inside.
    nonisolated static func url(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let links = detector?.matches(in: text, range: range).compactMap(\.url) ?? []
        return links.first { url in
            guard let host = url.host?.lowercased() else { return false }
            return (host == "icloud.com" || host.hasSuffix(".icloud.com")) && url.path.hasPrefix("/share/")
        }
    }

    /// The invite as a QR code, black on white so any camera can read it.
    nonisolated static func qrCode(for url: URL, scale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
