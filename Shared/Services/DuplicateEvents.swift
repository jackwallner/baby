import CoreData
import Foundation

/// A widget tap is saved twice on the way to CloudKit: the widget writes its
/// own record straight away, and the app exports the same entry from the
/// local store when it next runs. Both carry the entry's `id`, so every
/// device keeps one and deletes the rest.
///
/// The choice has to be the same on every device, or two phones could each
/// delete a different copy and lose the entry: the copy whose record is named
/// after the entry (the widget's) wins, then the lowest record name. A copy
/// with no record yet has never left this phone and always loses.
enum DuplicateEvents {
    /// Deletes the extra copies and returns how many went. Does not save.
    static func remove(in context: NSManagedObjectContext, recordName: (NSManagedObjectID) -> String?) -> Int {
        let ids = duplicatedIDs(in: context)
        guard !ids.isEmpty else { return 0 }
        let request = NSFetchRequest<LogEvent>(entityName: "LogEvent")
        request.predicate = NSPredicate(format: "id IN %@", ids)
        guard let copies = try? context.fetch(request) else { return 0 }
        var removed = 0
        for group in Dictionary(grouping: copies, by: { $0.id }).values where group.count > 1 {
            let ranked = group.sorted { rank($0, recordName) < rank($1, recordName) }
            let keeper = ranked[0]
            for extra in ranked.dropFirst() {
                // An edit made to the losing copy since must not be lost.
                if let newer = extra.updatedAt, newer > (keeper.updatedAt ?? .distantPast) {
                    copyValues(from: extra, to: keeper)
                }
                context.delete(extra)
                removed += 1
            }
        }
        return removed
    }

    /// Ids held by more than one entry. Reads only the id column, never whole
    /// entries, and counts here: GROUP BY would be faster but an in-memory
    /// store throws an exception Swift cannot catch.
    private static func duplicatedIDs(in context: NSManagedObjectContext) -> [UUID] {
        let request = NSFetchRequest<NSDictionary>(entityName: "LogEvent")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        request.predicate = NSPredicate(format: "id != nil")
        guard let rows = try? context.fetch(request) else { return [] }
        var seen: Set<UUID> = []
        var repeated: Set<UUID> = []
        for case let id as UUID in rows.map({ $0["id"] }) where !seen.insert(id).inserted {
            repeated.insert(id)
        }
        return Array(repeated)
    }

    /// Lower ranks first. Only names, never local object ids, decide, so
    /// every device ranks the same copies the same way.
    private static func rank(_ event: LogEvent, _ recordName: (NSManagedObjectID) -> String?) -> String {
        guard let name = recordName(event.objectID) else { return "2" }
        if name == event.id?.uuidString { return "0" }
        return "1" + name
    }

    private static func copyValues(from source: LogEvent, to target: LogEvent) {
        target.kind = source.kind
        target.startedAt = source.startedAt
        target.endedAt = source.endedAt
        target.side = source.side
        target.amount = source.amount
        target.stoolColor = source.stoolColor
        target.note = source.note
        target.updatedAt = source.updatedAt
    }
}
