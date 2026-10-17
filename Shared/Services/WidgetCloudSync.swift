import CloudKit
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

    static func pending() -> [WidgetCloudOp] {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.Key.widgetCloudOps),
              let ops = try? JSONDecoder().decode([WidgetCloudOp].self, from: data) else { return [] }
        return ops
    }

    private static func save(_ ops: [WidgetCloudOp]) {
        if ops.isEmpty {
            AppGroup.defaults.removeObject(forKey: AppGroup.Key.widgetCloudOps)
        } else if let data = try? JSONEncoder().encode(ops) {
            AppGroup.defaults.set(data, forKey: AppGroup.Key.widgetCloudOps)
        }
    }

    /// Adds changes, folding each into any still waiting for the same record:
    /// a sleep started and ended before either uploaded is one create, and an
    /// entry added and undone is only a delete.
    static func enqueue(_ new: [WidgetCloudOp]) {
        guard !new.isEmpty else { return }
        save(fold(pending(), new))
    }

    static func fold(_ queue: [WidgetCloudOp], _ new: [WidgetCloudOp]) -> [WidgetCloudOp] {
        var ops = queue
        for op in new {
            guard let index = ops.firstIndex(where: { $0.recordName == op.recordName }) else {
                ops.append(op)
                continue
            }
            var merged = op
            if ops[index].action == .create && op.action == .update { merged.action = .create }
            ops[index] = merged
        }
        return ops
    }

    /// Drops what the app has already exported itself: everything queued
    /// before it started, and everything past its lifetime.
    static func dropExported(before launch: Date, now: Date = .now) {
        let kept = pending().filter { $0.queuedAt >= launch && now.timeIntervalSince($0.queuedAt) < queueLifetime }
        save(kept)
    }

    // MARK: - Undo tombstones

    static func markUndone(_ eventID: UUID, at now: Date = .now) {
        var stones = tombstones(now: now)
        stones[eventID.uuidString] = now
        AppGroup.defaults.set(stones, forKey: AppGroup.Key.undoneEventIDs)
    }

    /// Entries undone recently enough that a copy coming back is removed.
    static func undoneIDs(now: Date = .now) -> [UUID] {
        let stones = tombstones(now: now)
        AppGroup.defaults.set(stones, forKey: AppGroup.Key.undoneEventIDs)
        return stones.keys.compactMap(UUID.init(uuidString:))
    }

    private static func tombstones(now: Date) -> [String: Date] {
        let stored = AppGroup.defaults.dictionary(forKey: AppGroup.Key.undoneEventIDs) as? [String: Date] ?? [:]
        return stored.filter { now.timeIntervalSince($0.value) < tombstoneLifetime }
    }

    // MARK: - Upload

    /// Sends everything queued. Called from the widget's intents right after
    /// the local save; short timeouts keep a slow network from holding the
    /// tile's confirmation for long, and anything unsent waits for the next
    /// tap or the app.
    @discardableResult
    static func flush(container: CKContainer = CKContainer(identifier: AppGroup.cloudKitContainerID)) async -> Bool {
        let now = Date.now
        let queue = pending().filter { now.timeIntervalSince($0.queuedAt) < queueLifetime }
        guard !queue.isEmpty else { return true }
        var finished: Set<String> = []
        for isShared in [false, true] {
            let ops = queue.filter { $0.target.isShared == isShared }
            guard !ops.isEmpty else { continue }
            let database = CloudEventWriter.database(for: ops[0].target, in: container)
            finished.formUnion(await send(ops, to: database))
        }
        // Only what this flush sent leaves; a tap queued meanwhile stays.
        let remaining = pending().filter { op in
            !(finished.contains(op.recordName) && queue.contains(op))
        }
        save(remaining)
        logger.info("Widget cloud flush sent \(finished.count) of \(queue.count)")
        return remaining.isEmpty
    }

    /// Returns the record names that are done with: saved, deleted, or gone
    /// from CloudKit so there is nothing left to change.
    private static func send(_ ops: [WidgetCloudOp], to database: CKDatabase) async -> Set<String> {
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .userInitiated
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        do {
            return try await database.configuredWith(configuration: configuration) { database in
                var done: Set<String> = []
                var saving: [CKRecord] = []
                for op in ops where op.action == .create {
                    guard let values = op.values else { continue }
                    saving.append(CloudEventWriter.record(for: values, named: op.recordName, in: op.target))
                }
                let updates = ops.filter { $0.action == .update && $0.values != nil }
                if !updates.isEmpty {
                    let ids = updates.map { $0.target.recordID($0.recordName) }
                    let fetched = try await database.records(for: ids)
                    for op in updates {
                        switch fetched[op.target.recordID(op.recordName)] {
                        case .success(let record)?:
                            CloudEventWriter.apply(op.values!, to: record)
                            saving.append(record)
                        case .failure(let error as CKError)? where error.code == .unknownItem:
                            done.insert(op.recordName)
                        default:
                            break
                        }
                    }
                }
                let deleting = ops.filter { $0.action == .delete }.map { $0.target.recordID($0.recordName) }
                let result = try await database.modifyRecords(
                    saving: saving,
                    deleting: deleting,
                    savePolicy: .changedKeys,
                    atomically: false
                )
                for (id, outcome) in result.saveResults {
                    if case .success = outcome { done.insert(id.recordName) }
                    if case .failure(let error) = outcome {
                        logger.error("Widget cloud save failed: \(String(describing: error), privacy: .public)")
                    }
                }
                for (id, outcome) in result.deleteResults {
                    switch outcome {
                    case .success:
                        done.insert(id.recordName)
                    case .failure(let error as CKError) where error.code == .unknownItem:
                        done.insert(id.recordName)
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
