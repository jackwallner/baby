import CloudKit
import Darwin
import Foundation
import os

/// One change a widget tap made, on its way straight to CloudKit.
struct WidgetCloudOp: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        /// An entry the widget added, written whole under its own id.
        case create
        /// An entry that already exists (a timer the tap ended or reopened).
        case update
        /// The widget's Undo of an entry it added.
        case delete
    }

    var action: Action
    var recordName: String
    var values: CloudEventValues?
    var target: CloudZoneTarget
    var queuedAt: Date = .now

    var key: WidgetCloudRecordKey {
        WidgetCloudRecordKey(recordName: recordName, zoneName: target.zoneName,
                             ownerName: target.ownerName, isShared: target.isShared)
    }
}

struct WidgetCloudRecordKey: Hashable, Sendable {
    let recordName: String
    let zoneName: String
    let ownerName: String
    let isShared: Bool
}

/// Advisory file locks coordinate separate app and extension processes. A
/// process-local actor or a UserDefaults read/modify/write cannot do that.
private final class WidgetCloudLease: Sendable {
    private let descriptor: Int32

    private init(_ descriptor: Int32) { self.descriptor = descriptor }

    static func acquire(at url: URL, blocking: Bool = true) throws -> WidgetCloudLease? {
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        while flock(descriptor, LOCK_EX | (blocking ? 0 : LOCK_NB)) != 0 {
            if errno == EINTR { continue }
            let code = errno
            close(descriptor)
            if !blocking && code == EWOULDBLOCK { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return WidgetCloudLease(descriptor)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

/// Widget taps reach the partner's phone without anyone opening the app.
///
/// The widget saves to the local store as before, so Logged / Undo shows at
/// once, and then writes the same change to CloudKit itself with
/// `CloudEventWriter`. The app still exports the local save when it next
/// runs; `DuplicateEvents` folds that second copy away on every device. A
/// change that cannot upload (no network, no target yet) is simply left to
/// that export, as before.
///
/// The app publishes what the widget cannot learn on its own: each baby's
/// zone and record, and the record names of running timers. Undo leaves a
/// tombstone so a deleted entry that already reached CloudKit is removed
/// again if it comes back.
enum WidgetCloudSync {
    private static let logger = Logger(subsystem: AppGroup.subsystem, category: "WidgetCloudSync")
    /// Changes older than this are left to the app's own export.
    static let queueLifetime: TimeInterval = 24 * 60 * 60
    /// How long an Undo keeps removing an entry that comes back.
    static let tombstoneLifetime: TimeInterval = 3 * 24 * 60 * 60

    // MARK: - Published by the app

    /// Called by the app after each reload with what its container knows.
    static func publish(targets: [UUID: CloudZoneTarget], recordNames: [UUID: String]) {
        let defaults = AppGroup.defaults
        let encodedTargets = Dictionary(uniqueKeysWithValues: targets.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(encodedTargets) {
            defaults.set(data, forKey: AppGroup.Key.cloudTargets)
        }
        let names = Dictionary(uniqueKeysWithValues: recordNames.map { ($0.key.uuidString, $0.value) })
        defaults.set(names, forKey: AppGroup.Key.cloudRecordNames)
    }

    static func target(for childID: UUID?) -> CloudZoneTarget? {
        guard let childID,
              let data = AppGroup.defaults.data(forKey: AppGroup.Key.cloudTargets),
              let targets = try? JSONDecoder().decode([String: CloudZoneTarget].self, from: data) else { return nil }
        return targets[childID.uuidString]
    }

    /// The record an existing entry lives in. One the widget created itself is
    /// named after the entry.
    static func recordName(for eventID: UUID) -> String {
        let names = AppGroup.defaults.dictionary(forKey: AppGroup.Key.cloudRecordNames) as? [String: String]
        return names?[eventID.uuidString] ?? eventID.uuidString
    }

    // MARK: - Queue

    static let queueDirectory = AppGroup.containerURL.appendingPathComponent("WidgetCloudSync", isDirectory: true)

    private struct State: Codable {
        var ops: [WidgetCloudOp] = []
        var tombstones: [String: Date] = [:]
    }

    /// Reads the latest disk state while locked, then atomically replaces it.
    /// UserDefaults is read only once, to migrate an older installed build.
    private static func transaction<T>(_ body: (inout State) -> T) throws -> T {
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        let lease = try WidgetCloudLease.acquire(at: queueDirectory.appendingPathComponent("state.lock"))
        defer { withExtendedLifetime(lease) {} }
        let url = queueDirectory.appendingPathComponent("state.json")
        var state: State
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
        } else {
            let legacy = AppGroup.defaults.data(forKey: AppGroup.Key.widgetCloudOps)
                .flatMap { try? JSONDecoder().decode([WidgetCloudOp].self, from: $0) } ?? []
            let stones = AppGroup.defaults.dictionary(forKey: AppGroup.Key.undoneEventIDs) as? [String: Date] ?? [:]
            state = State(ops: legacy, tombstones: stones)
        }
        let result = body(&state)
        try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.widgetCloudOps)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.undoneEventIDs)
        return result
    }

    static func pending() -> [WidgetCloudOp] {
        do { return try transaction { $0.ops } }
        catch {
            logger.error("Could not read widget queue: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Adds changes, folding each into any still waiting for the same record:
    /// a sleep started and ended before either uploaded is one create, and an
    /// entry added and undone is only a delete.
    static func enqueue(_ new: [WidgetCloudOp]) {
        guard !new.isEmpty else { return }
        do { try transaction { $0.ops = fold($0.ops, new) } }
        catch { logger.error("Could not queue widget changes: \(String(describing: error), privacy: .public)") }
    }

    static func fold(_ queue: [WidgetCloudOp], _ new: [WidgetCloudOp]) -> [WidgetCloudOp] {
        var ops = queue
        for op in new {
            guard let index = ops.firstIndex(where: { $0.key == op.key }) else {
                ops.append(op)
                continue
            }
            var merged = op
            if ops[index].action == .create && op.action == .update { merged.action = .create }
            ops[index] = merged
        }
        return ops
    }

    /// Starting the app does not prove an export succeeded. In particular a
    /// direct-record delete cannot be exported until that record is imported.
    /// Keep deletes until CloudKit confirms them, even after long offline gaps.
    static func prune(now: Date = .now) {
        do {
            try transaction { state in
                state.ops.removeAll { $0.action != .delete && now.timeIntervalSince($0.queuedAt) >= queueLifetime }
            }
        } catch { logger.error("Could not prune widget queue: \(String(describing: error), privacy: .public)") }
    }

    // MARK: - Undo tombstones

    static func markUndone(_ eventID: UUID, at now: Date = .now) {
        do { try transaction { $0.tombstones[eventID.uuidString] = now } }
        catch { logger.error("Could not record widget Undo: \(String(describing: error), privacy: .public)") }
    }

    static func restore(_ eventID: UUID) {
        do { _ = try transaction { $0.tombstones.removeValue(forKey: eventID.uuidString) } }
        catch { logger.error("Could not restore widget entry: \(String(describing: error), privacy: .public)") }
    }

    static func undoneIDs(now: Date = .now) -> [UUID] {
        Array(undoneDates(now: now).keys)
    }

    static func undoneDates(now: Date = .now) -> [UUID: Date] {
        do {
            return try transaction { state in
                state.tombstones = state.tombstones.filter { now.timeIntervalSince($0.value) < tombstoneLifetime }
                return Dictionary(uniqueKeysWithValues: state.tombstones.compactMap { key, value in
                    UUID(uuidString: key).map { ($0, value) }
                })
            }
        } catch {
            logger.error("Could not read widget Undo: \(String(describing: error), privacy: .public)")
            return [:]
        }
    }

    // MARK: - Upload

    /// Sends everything queued. Called from the widget's intents right after
    /// the local save; short timeouts keep a slow network from holding the
    /// tile's confirmation for long, and anything unsent waits for the next
    /// tap or the app.
    @discardableResult
    static func flush(container: CKContainer = CKContainer(identifier: AppGroup.cloudKitContainerID)) async -> Bool {
        await flush { queue in
            var finished: Set<WidgetCloudRecordKey> = []
            for isShared in [false, true] {
                let ops = queue.filter { $0.target.isShared == isShared }
                guard let first = ops.first else { continue }
                let database = CloudEventWriter.database(for: first.target, in: container)
                finished.formUnion(await send(ops, to: database))
            }
            return finished
        }
    }

    /// One uploader across processes, including while its network calls are
    /// suspended. Queue transactions use a separate short-lived file lock.
    @discardableResult
    static func flush(using send: @Sendable ([WidgetCloudOp]) async -> Set<WidgetCloudRecordKey>) async -> Bool {
        do {
            try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
            guard let lease = try WidgetCloudLease.acquire(at: queueDirectory.appendingPathComponent("upload.lock"), blocking: false)
            else { return false }
            defer { withExtendedLifetime(lease) {} }
            prune()
            // Drain taps queued while a request was suspended, within the
            // extension's short runtime budget. Failed operations stay queued.
            for _ in 0..<3 {
                let queue = try transaction { $0.ops }
                guard !queue.isEmpty else { return true }
                let finished = await send(queue)
                let remaining = try transaction { state in
                    state.ops.removeAll { finished.contains($0.key) && queue.contains($0) }
                    return state.ops
                }
                if remaining.isEmpty { return true }
                if finished.isEmpty { return false }
            }
        } catch { logger.error("Widget cloud flush failed: \(String(describing: error), privacy: .public)") }
        return false
    }

    /// Returns the record names that are done with: saved, deleted, or gone
    /// from CloudKit so there is nothing left to change.
    private static func send(_ ops: [WidgetCloudOp], to database: CKDatabase) async -> Set<WidgetCloudRecordKey> {
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .userInitiated
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        do {
            return try await database.configuredWith(configuration: configuration) { database in
                var done: Set<WidgetCloudRecordKey> = []
                var saving: [CKRecord] = []
                let changes = ops.filter { $0.action != .delete && $0.values != nil }
                if !changes.isEmpty {
                    let ids = changes.map { $0.target.recordID($0.recordName) }
                    let fetched = try await database.records(for: ids)
                    for op in changes {
                        guard let values = op.values else { continue }
                        switch fetched[op.target.recordID(op.recordName)] {
                        case .success(let record)?:
                            // A retried create may already exist and have
                            // partner edits. Patch only the timer fields.
                            CloudEventWriter.apply(values, to: record)
                            if record.changedKeys().isEmpty { done.insert(op.key) }
                            else { saving.append(record) }
                        case .failure(let error as CKError)? where error.code == .unknownItem:
                            if op.action == .create {
                                saving.append(CloudEventWriter.record(for: values, named: op.recordName, in: op.target))
                            }
                        default:
                            break
                        }
                    }
                }
                let deleting = ops.filter { $0.action == .delete }.map { $0.target.recordID($0.recordName) }
                let result = try await database.modifyRecords(
                    saving: saving,
                    deleting: deleting,
                    savePolicy: .ifServerRecordUnchanged,
                    atomically: false
                )
                for (id, outcome) in result.saveResults {
                    if case .success = outcome {
                        done.formUnion(ops.filter { $0.target.recordID($0.recordName) == id }.map(\.key))
                    }
                    if case .failure(let error) = outcome {
                        logger.error("Widget cloud save failed: \(String(describing: error), privacy: .public)")
                    }
                }
                for (id, outcome) in result.deleteResults {
                    switch outcome {
                    case .success:
                        done.formUnion(ops.filter { $0.target.recordID($0.recordName) == id }.map(\.key))
                    case .failure(let error as CKError) where error.code == .unknownItem:
                        done.formUnion(ops.filter { $0.target.recordID($0.recordName) == id }.map(\.key))
                    case .failure(let error):
                        logger.error("Widget cloud delete failed: \(String(describing: error), privacy: .public)")
                    }
                }
                return done
            }
        } catch {
            logger.error("Widget cloud flush failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}
