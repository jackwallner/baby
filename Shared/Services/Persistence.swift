import CloudKit
import CoreData
import Foundation
import os

/// The Core Data stack: one private store (the family's own iCloud data) and
/// one shared store (a baby another parent shared with this account). Both
/// use the same model, so every query runs across the pair.
///
/// The app opens it with CloudKit mirroring on. Widgets and intents open the
/// same files with mirroring off and simply write; the app's container picks
/// their inserts up from persistent history and exports them next time it
/// runs. Tests use an in-memory pair.
final class Persistence: @unchecked Sendable {
    static let shared = Persistence(cloudKit: Persistence.processWantsCloudKit)

    let container: NSPersistentCloudKitContainer
    let privateStore: NSPersistentStore
    let sharedStore: NSPersistentStore
    let cloudKitEnabled: Bool
    /// Nil in production. Tests can inject a throwing operation to exercise
    /// rollback paths without changing the persistent model or store files.
    private let saveOperation: ((NSManagedObjectContext) throws -> Void)?

    private static let logger = Logger(subsystem: AppGroup.subsystem, category: "Persistence")

    /// Only the app process mirrors to CloudKit. Extensions are short-lived and
    /// memory-capped, and two exporters on one zone gain nothing.
    private static var processWantsCloudKit: Bool {
        Bundle.main.bundleIdentifier == AppGroup.bundleID && !ProcessInfo.processInfo.arguments.contains("-NoCloudKit")
    }

    init(
        cloudKit: Bool,
        inMemory: Bool = false,
        saveOperation: ((NSManagedObjectContext) throws -> Void)? = nil
    ) {
        cloudKitEnabled = cloudKit && !inMemory
        self.saveOperation = saveOperation
        container = NSPersistentCloudKitContainer(name: "Baby", managedObjectModel: BabyModel.model)

        let directory = AppGroup.containerURL.appendingPathComponent("BabyData", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let privateDescription = NSPersistentStoreDescription(
            url: inMemory ? URL(fileURLWithPath: "/dev/null/private") : directory.appendingPathComponent("private.sqlite")
        )
        let sharedDescription = NSPersistentStoreDescription(
            url: inMemory ? URL(fileURLWithPath: "/dev/null/shared") : directory.appendingPathComponent("shared.sqlite")
        )
        for description in [privateDescription, sharedDescription] {
            description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        if cloudKitEnabled {
            let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: AppGroup.cloudKitContainerID)
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions
            let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: AppGroup.cloudKitContainerID)
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions
        }
        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        var loadError: Error?
        let coordinator = container.persistentStoreCoordinator
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if let loadError {
            Self.logger.error("Store load failed: \(String(describing: loadError), privacy: .public)")
        }
        // Coordinator lookups by URL are the reliable way to get the store
        // objects back; the descriptions alone do not carry them.
        guard let privateURL = privateDescription.url, let sharedURL = sharedDescription.url,
              let p = coordinator.persistentStore(for: privateURL),
              let s = coordinator.persistentStore(for: sharedURL) else {
            fatalError("Baby data stores did not load: \(String(describing: loadError))")
        }
        privateStore = p
        sharedStore = s

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.transactionAuthor = Bundle.main.bundleIdentifier
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = Bundle.main.bundleIdentifier
        return context
    }

    // MARK: - Children

    /// The baby the four buttons log for. The stored choice wins; otherwise a
    /// baby someone shared with us beats one created locally, because the
    /// local one is usually the empty placeholder from onboarding.
    func activeChild(in context: NSManagedObjectContext) -> Child? {
        let request = NSFetchRequest<Child>(entityName: "Child")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let children = (try? context.fetch(request)) ?? []
        guard !children.isEmpty else { return nil }
        if let stored = AppGroup.defaults.string(forKey: AppGroup.Key.activeChildID),
           let id = UUID(uuidString: stored),
           let match = children.first(where: { $0.id == id }) {
            return match
        }
        if let shared = children.first(where: { $0.objectID.persistentStore == sharedStore }) {
            return shared
        }
        return children.max { $0.eventCount < $1.eventCount } ?? children[0]
    }

    func allChildren(in context: NSManagedObjectContext) -> [Child] {
        let request = NSFetchRequest<Child>(entityName: "Child")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func isShared(_ child: Child) -> Bool {
        child.objectID.persistentStore == sharedStore
    }

    /// Events for one child, newest first.
    func events(for child: Child, in context: NSManagedObjectContext, limit: Int = 0) -> [LogEvent] {
        let request = NSFetchRequest<LogEvent>(entityName: "LogEvent")
        request.predicate = NSPredicate(format: "child == %@", child)
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        if limit > 0 { request.fetchLimit = limit }
        return (try? context.fetch(request)) ?? []
    }

    /// Running feeds or sleeps for one child, however many entries are newer.
    /// Outside-app actions use this so an old timer is never out of reach.
    func runningEvents(_ kind: EventKind, for child: Child, in context: NSManagedObjectContext) -> [LogEvent] {
        let request = NSFetchRequest<LogEvent>(entityName: "LogEvent")
        request.predicate = NSPredicate(format: "child == %@ AND kind == %@ AND endedAt == nil", child, kind.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    /// Inserts one event next to its child, in whichever store the child lives
    /// in. Used by the app, the widgets, the Watch relay and Siri alike.
    @discardableResult
    func insert(kind: EventKind, at date: Date, side: FeedSide? = nil, ended: Date? = nil, for child: Child, in context: NSManagedObjectContext) -> LogEvent {
        let event = LogEvent.make(in: context, child: child, kind: kind, at: date)
        event.feedSide = side
        event.endedAt = ended
        if let store = child.objectID.persistentStore {
            context.assign(event, to: store)
        }
        return event
    }

    @discardableResult
    func save(_ context: NSManagedObjectContext) -> Bool {
        guard context.hasChanges else { return true }
        do {
            if let saveOperation {
                try saveOperation(context)
            } else {
                try context.save()
            }
            return true
        } catch {
            Self.logger.error("Save failed: \(String(describing: error), privacy: .public)")
            context.rollback()
            return false
        }
    }
}
