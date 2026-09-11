import Foundation
import SwiftData

@MainActor
final class CaffeineLogService: ObservableObject {
    static let shared = CaffeineLogService()

    struct LoggedEntry: Equatable {
        let milligrams: Double
        let date: Date
        let drinkName: String?
        let healthKitUUID: UUID?
        let localID: UUID?
    }

    @Published private(set) var lastEntry: LoggedEntry?
    /// When `lastEntry` was written, so the Now screen can offer undo for a
    /// short window instead of indefinitely.
    @Published private(set) var lastLoggedAt: Date?
    /// True when the most recent entry could not reach Apple Health and is
    /// sitting in the local queue. The Now screen shows this rather than letting
    /// the user believe the sample was saved.
    @Published private(set) var lastWriteFellBack = false
    /// Number of entries still waiting for a successful Apple Health write.
    @Published private(set) var pendingWriteCount = 0

    private init() {
        refreshPendingCount()
    }

    @discardableResult
    func log(milligrams: Double, at date: Date = .now, drinkName: String? = nil) async -> Bool {
        guard milligrams > 0 else { return false }
        let saved = await HealthKitService.shared.saveCaffeine(
            milligrams: milligrams,
            at: date,
            drinkName: drinkName
        )
        if let saved {
            lastEntry = LoggedEntry(
                milligrams: milligrams,
                date: date,
                drinkName: drinkName,
                healthKitUUID: saved,
                localID: nil
            )
            lastWriteFellBack = false
        } else {
            let entry = LocalCaffeineEntry(date: date, milligrams: milligrams, drinkName: drinkName)
            let context = DataService.sharedModelContainer.mainContext
            context.insert(entry)
            try? context.save()
            lastEntry = LoggedEntry(
                milligrams: milligrams,
                date: date,
                drinkName: drinkName,
                healthKitUUID: nil,
                localID: entry.id
            )
            lastWriteFellBack = true
        }
        lastLoggedAt = .now
        refreshPendingCount()
        await HealthKitService.shared.refreshCache()
        return true
    }

    /// Changes an existing entry's dose, time, or drink. HealthKit samples are
    /// immutable, so an edit is a delete plus a fresh write, which also keeps the
    /// Health app's own record correct.
    @discardableResult
    func update(
        sample: CaffeineSample,
        milligrams: Double,
        at date: Date,
        drinkName: String?
    ) async -> Bool {
        guard sample.isOurs, milligrams > 0 else { return false }
        guard await delete(sample: sample) else { return false }
        return await log(milligrams: milligrams, at: date, drinkName: drinkName)
    }

    @discardableResult
    func undoLast() async -> Bool {
        guard let entry = lastEntry else { return false }
        let removed: Bool
        if let uuid = entry.healthKitUUID {
            removed = await HealthKitService.shared.deleteCaffeine(uuid: uuid)
        } else if let id = entry.localID {
            removed = deleteLocalEntry(id: id)
        } else {
            removed = false
        }
        if removed {
            lastEntry = nil
            lastLoggedAt = nil
            refreshPendingCount()
            await HealthKitService.shared.refreshCache()
        }
        return removed
    }

    @discardableResult
    func delete(sample: CaffeineSample) async -> Bool {
        guard sample.isOurs, let id = UUID(uuidString: sample.id) else { return false }
        let removed: Bool
        if sample.isLocalOnly {
            removed = deleteLocalEntry(id: id)
        } else {
            removed = await HealthKitService.shared.deleteCaffeine(uuid: id)
        }
        if removed {
            if lastEntry?.healthKitUUID == id || lastEntry?.localID == id {
                lastEntry = nil
                lastLoggedAt = nil
            }
            refreshPendingCount()
            await HealthKitService.shared.refreshCache()
        }
        return removed
    }

    /// Retries every queued entry against Apple Health. Called on foreground and
    /// from the "not saved to Health" banner's retry action.
    @discardableResult
    func retryPendingLocalEntries() async -> Int {
        let health = HealthKitService.shared
        health.refreshWriteAuthorization()
        guard health.canWrite else {
            refreshPendingCount()
            return 0
        }
        let context = DataService.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<LocalCaffeineEntry>(predicate: #Predicate { $0.healthKitUUID == nil })
        var written = 0
        for entry in (try? context.fetch(descriptor)) ?? [] {
            if let uuid = await health.saveCaffeine(
                milligrams: entry.milligrams,
                at: entry.date,
                drinkName: entry.drinkName
            ) {
                // Health now owns the sample, so the queue row has nothing left
                // to do. It is deleted rather than stamped with the new UUID so
                // the local store stays a queue and never becomes a second,
                // silently diverging copy of the log.
                context.delete(entry)
                written += 1
            }
        }
        try? context.save()
        refreshPendingCount()
        if written > 0 { lastWriteFellBack = false }
        await health.refreshCache()
        return written
    }

    private func deleteLocalEntry(id: UUID) -> Bool {
        let context = DataService.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<LocalCaffeineEntry>(predicate: #Predicate { $0.id == id })
        guard let row = try? context.fetch(descriptor).first else { return false }
        context.delete(row)
        try? context.save()
        return true
    }

    private func refreshPendingCount() {
        let context = DataService.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<LocalCaffeineEntry>(predicate: #Predicate { $0.healthKitUUID == nil })
        pendingWriteCount = (try? context.fetchCount(descriptor)) ?? 0
        if pendingWriteCount == 0 { lastWriteFellBack = false }
    }
}
