import CoreData
import Foundation

/// Record and share lookups run inside Core Data's CloudKit mirroring. On a
/// tester's phone (build 83) one entry's CloudKit metadata had no record name
/// or zone, and asking for that entry's record ID threw an exception no Swift
/// code can catch (`-[PFCloudKitMetadataCache registerRecordMetadata:forObject:]`,
/// nil key from `createRecordID`) at every launch, so the app never opened.
///
/// Each lookup leaves a marker file naming its object while it runs. A
/// process that dies inside one leaves the marker behind, and no later launch
/// asks about that object again, in any build: a crash loop costs more than
/// the lookup. The duplicate cleanup then keeps both copies of that entry,
/// which loses nothing.
final class CloudKitLookupGuard: @unchecked Sendable {
    private static let markerSuffix = ".cloudkit-lookup"

    private let directory: URL
    private let skipFile: URL
    private let lock = NSLock()
    private var skipped: Set<String>
    private let enabled: Bool

    /// Only the app process looks records up, so only it reads the markers.
    /// A widget opening the store must never take the app's running lookup
    /// for a crash.
    init(directory: URL, enabled: Bool) {
        self.directory = directory
        skipFile = directory.appendingPathComponent("cloudkit-lookup-skipped.txt")
        self.enabled = enabled
        skipped = []
        guard enabled else { return }
        skipped = Self.readSkipped(from: skipFile)
        let markers = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var died: [String] = []
        for marker in markers where marker.lastPathComponent.hasSuffix(Self.markerSuffix) {
            if let key = try? String(contentsOf: marker, encoding: .utf8), !key.isEmpty { died.append(key) }
            try? FileManager.default.removeItem(at: marker)
        }
        guard !died.isEmpty else { return }
        skipped.formUnion(died)
        let text = skipped.sorted().joined(separator: "\n")
        try? Data(text.utf8).write(to: skipFile, options: .atomic)
    }

    func isSkipped(_ objectID: NSManagedObjectID) -> Bool {
        lock.withLock { skipped.contains(Self.key(objectID)) }
    }

    /// Runs `body` with a marker naming the object, or returns nil for an
    /// object a lookup has already died on.
    func run<T>(for objectID: NSManagedObjectID, _ body: () throws -> T) rethrows -> T? {
        guard enabled else { return try body() }
        let key = Self.key(objectID)
        guard !lock.withLock({ skipped.contains(key) }) else { return nil }
        let marker = directory.appendingPathComponent(UUID().uuidString + Self.markerSuffix)
        FileManager.default.createFile(atPath: marker.path, contents: Data(key.utf8))
        // A thrown error came back too: only a process death leaves the marker.
        defer { try? FileManager.default.removeItem(at: marker) }
        return try body()
    }

    static func key(_ objectID: NSManagedObjectID) -> String {
        objectID.uriRepresentation().absoluteString
    }

    private static func readSkipped(from file: URL) -> Set<String> {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map(String.init))
    }
}
