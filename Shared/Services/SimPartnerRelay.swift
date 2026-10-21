#if DEBUG
import Combine
import CoreData
import Foundation

/// Two simulators logging one baby with no iCloud account (DEBUG only).
///
/// Each phone writes what it saves to a folder on the Mac and imports the
/// other phone's files the way CloudKit's mirror imports: a background save
/// under the mirroring author, merged into the view context, then the
/// app's own remote-change reload. Only Apple's transport is missing; every
/// receiving path is the app's. Launch with `-SimRelay <folder> <name>`, and
/// optionally `-SimRelayDelay <seconds>` for CloudKit's lag (default 2).
///
/// Each phone also writes `<name>.log` in the folder: what it sent and
/// received, and every redraw of the log with what it then showed, so a run
/// can be checked for agreement and for redraws per tap.
@MainActor
final class SimPartnerRelay {
    static let author = "NSCloudKitMirroringDelegate.import.simRelay"
    private static var running: SimPartnerRelay?

    let folder: URL
    let name: String
    let delay: TimeInterval
    private let persistence: Persistence
    private var token: NSPersistentHistoryToken?
    /// Object URI to entry or baby id, so a delete can name what it removed:
    /// history keeps no values for deleted rows.
    private var known: [URL: (entity: String, id: UUID)] = [:]
    private var applied: Set<String>
    private var timer: Timer?
    private var redraws: AnyCancellable?
    private let appliedKey: String

    /// Starts the relay when the launch asks for it.
    static func startIfAsked(events: EventStore) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-SimRelay"), index + 2 < arguments.count else { return }
        let delay = arguments.firstIndex(of: "-SimRelayDelay").flatMap { $0 + 1 < arguments.count ? TimeInterval(arguments[$0 + 1]) : nil } ?? 2
        let relay = SimPartnerRelay(
            folder: URL(fileURLWithPath: arguments[index + 1], isDirectory: true),
            name: arguments[index + 2],
            delay: delay,
            persistence: events.persistence
        )
        relay.watch(events)
        relay.start()
        running = relay
    }

    init(folder: URL, name: String, delay: TimeInterval, persistence: Persistence, defaults: UserDefaults = .standard) {
        self.folder = folder
        self.name = name
        self.delay = delay
        self.persistence = persistence
        appliedKey = "simRelayApplied.\(name)"
        applied = Set(defaults.stringArray(forKey: appliedKey) ?? [])
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Sends everything the first time this phone joins the folder (a phone
    /// joining late gets the whole log; CloudKit never uploads twice, so a
    /// relaunch does not), then relays saves and imports the partner's
    /// twice a second.
    func start() {
        token = persistence.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        let joined = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .contains { $0.hasPrefix("\(name)-") }
        if joined {
            rememberEverything()
        } else {
            sendEverything()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        log("started, delay \(delay)s")
    }

    func tick(now: Date = .now) {
        send(now: now)
        receive(now: now)
    }

    // MARK: - Sending

    /// Learns every row's id without sending, so deletes can name them.
    private func rememberEverything() {
        let context = persistence.viewContext
        for entity in ["Child", "LogEvent"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            for object in (try? context.fetch(request)) ?? [] {
                if let id = object.value(forKey: "id") as? UUID { known[object.objectID.uriRepresentation()] = (entity, id) }
            }
        }
    }

    private func sendEverything() {
        let context = persistence.viewContext
        var changes: [[String: Any]] = []
        for entity in ["Child", "LogEvent"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            for object in (try? context.fetch(request)) ?? [] {
                if let change = upsert(object) { changes.append(change) }
            }
        }
        write(changes, at: .now)
    }

    /// Every save since the last call that did not come from a partner,
    /// including the widget's from its own process.
    func send(now: Date = .now) {
        let context = persistence.viewContext
        let current = persistence.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        if let filter = NSPersistentHistoryTransaction.fetchRequest {
            filter.predicate = NSPredicate(format: "author == nil OR NOT (author BEGINSWITH %@)", "NSCloudKitMirroringDelegate")
            request.fetchRequest = filter
        }
        let transactions = ((try? context.execute(request)) as? NSPersistentHistoryResult)?.result as? [NSPersistentHistoryTransaction] ?? []
        token = current ?? transactions.last?.token ?? token
        var latest: [NSManagedObjectID: NSPersistentHistoryChangeType] = [:]
        var order: [NSManagedObjectID] = []
        // Checked here too: the store's filter let imports through, and an
        // echo of the partner's own change can undo what they did next.
        let local = transactions.filter { !($0.author ?? "").hasPrefix("NSCloudKitMirroringDelegate") }
        for change in local.flatMap({ $0.changes ?? [] }) {
            if latest[change.changedObjectID] == nil { order.append(change.changedObjectID) }
            latest[change.changedObjectID] = change.changeType
        }
        var changes: [[String: Any]] = []
        for objectID in order {
            if latest[objectID] == .delete {
                guard let gone = known.removeValue(forKey: objectID.uriRepresentation()) else { continue }
                changes.append(["op": "delete", "entity": gone.entity, "id": gone.id.uuidString])
            } else if let object = try? context.existingObject(with: objectID), let change = upsert(object) {
                changes.append(change)
            }
        }
        write(changes, at: now)
    }

    private func upsert(_ object: NSManagedObject) -> [String: Any]? {
        guard let entity = object.entity.name, ["Child", "LogEvent"].contains(entity),
              let id = object.value(forKey: "id") as? UUID else { return nil }
        known[object.objectID.uriRepresentation()] = (entity, id)
        var values: [String: Any] = [:]
        for name in object.entity.attributesByName.keys {
            values[name] = Self.encode(object.value(forKey: name))
        }
        if let event = object as? LogEvent { values["#child"] = event.child?.id?.uuidString ?? NSNull() }
        return ["op": "upsert", "entity": entity, "values": values]
    }

    private func write(_ changes: [[String: Any]], at date: Date) {
        guard !changes.isEmpty else { return }
        // Babies first, so an entry never arrives before its baby.
        let ordered = changes.sorted { ($0["entity"] as? String == "Child") && ($1["entity"] as? String != "Child") }
        let file = folder.appendingPathComponent("\(name)-\(String(format: "%.3f", date.timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json")
        let body: [String: Any] = ["from": name, "sentAt": date.timeIntervalSince1970, "changes": ordered]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        // Written aside and moved in, so the partner never reads half a file.
        let partial = file.appendingPathExtension("partial")
        try? data.write(to: partial)
        try? FileManager.default.moveItem(at: partial, to: file)
        log("sent \(changes.count): \(Self.describe(ordered))")
    }

    // MARK: - Receiving

    /// The partner's files that are due, oldest first, each in one background
    /// save under the mirroring author, as a CloudKit import lands.
    func receive(now: Date = .now) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix("\(name)-") && !applied.contains($0.lastPathComponent) }
        let batches = files.compactMap { url -> (url: URL, sentAt: Double, from: String, changes: [[String: Any]])? in
            guard let data = try? Data(contentsOf: url),
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sentAt = body["sentAt"] as? Double, let changes = body["changes"] as? [[String: Any]] else { return nil }
            return (url, sentAt, body["from"] as? String ?? "?", changes)
        }
        for batch in batches.sorted(by: { $0.sentAt < $1.sentAt }) where now.timeIntervalSince1970 >= batch.sentAt + delay {
            apply(batch.changes)
            applied.insert(batch.url.lastPathComponent)
            UserDefaults.standard.set(Array(applied), forKey: appliedKey)
            let age = now.timeIntervalSince1970 - batch.sentAt
            log("received \(batch.changes.count) from \(batch.from) after \(String(format: "%.1f", age))s: \(Self.describe(batch.changes))")
        }
    }

    func apply(_ changes: [[String: Any]]) {
        let context = persistence.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = Self.author
        let store = persistence.privateStore
        let outcome: (touched: [(URL, String, UUID)], failure: Error?) = context.performAndWait {
            var touched: [NSManagedObject] = []
            for change in changes {
                guard let entity = change["entity"] as? String else { continue }
                if change["op"] as? String == "delete" {
                    guard let id = (change["id"] as? String).flatMap(UUID.init) else { continue }
                    Self.objects(entity, id: id, in: context).forEach(context.delete)
                    continue
                }
                guard let values = change["values"] as? [String: Any],
                      let id = (values["id"] as? [String: Any])?["uuid"] as? String, let uuid = UUID(uuidString: id) else { continue }
                let object = Self.objects(entity, id: uuid, in: context).first ?? {
                    let inserted = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
                    context.assign(inserted, to: store)
                    return inserted
                }()
                for name in object.entity.attributesByName.keys where values[name] != nil {
                    object.setValue(Self.decode(values[name]), forKey: name)
                }
                if let event = object as? LogEvent, let child = (values["#child"] as? String).flatMap(UUID.init) {
                    event.child = Self.objects("Child", id: child, in: context).first as? Child
                }
                touched.append(object)
            }
            do {
                try context.save()
            } catch {
                return ([], error)
            }
            // Saved, so the ids are permanent: this phone can name these
            // rows when it deletes one the partner made.
            let names = touched.compactMap { object -> (URL, String, UUID)? in
                guard let entity = object.entity.name, let id = object.value(forKey: "id") as? UUID else { return nil }
                return (object.objectID.uriRepresentation(), entity, id)
            }
            return (names, nil)
        }
        for (uri, entity, id) in outcome.touched { known[uri] = (entity, id) }
        if let failure = outcome.failure { log("apply failed: \(failure)") }
    }

    private nonisolated static func objects(_ entity: String, id: UUID, in context: NSManagedObjectContext) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return (try? context.fetch(request)) ?? []
    }

    // MARK: - Values

    private nonisolated static func encode(_ value: Any?) -> Any {
        switch value {
        case let date as Date: ["date": date.timeIntervalSinceReferenceDate]
        case let uuid as UUID: ["uuid": uuid.uuidString]
        case let data as Data: ["data": data.base64EncodedString()]
        case let string as String: string
        case let number as NSNumber: number
        default: NSNull()
        }
    }

    private nonisolated static func decode(_ value: Any?) -> Any? {
        switch value {
        case let tagged as [String: Any]:
            if let date = tagged["date"] as? Double { return Date(timeIntervalSinceReferenceDate: date) }
            if let uuid = tagged["uuid"] as? String { return UUID(uuidString: uuid) }
            if let data = tagged["data"] as? String { return Data(base64Encoded: data) }
            return nil
        case is NSNull: return nil
        default: return value
        }
    }

    // MARK: - Log

    /// Every redraw of the log, with what it showed then.
    private func watch(_ events: EventStore) {
        redraws = events.$revision.dropFirst().sink { [weak self, weak events] revision in
            // Published before the change lands; read it on the next turn.
            DispatchQueue.main.async {
                guard let self, let events else { return }
                let s = events.summary
                let running = [s.runningFeedStart.map { _ in "feeding" }, s.runningSleepStart.map { _ in "asleep" }].compactMap { $0 }
                self.log("redraw \(revision): \(events.events.count) entries, today \(s.todayFeeds) feeds \(s.todayWet) wet \(s.todayDirty) dirty, last feed \(s.lastFeedAt.map(Self.clock) ?? "-") \(FeedSide.encode(s.feedSides) ?? "")\(running.isEmpty ? "" : ", " + running.joined(separator: " "))")
            }
        }
    }

    private static func describe(_ changes: [[String: Any]]) -> String {
        let parts = changes.prefix(4).map { change -> String in
            let values = change["values"] as? [String: Any]
            let kind = values?["kind"] as? String ?? (change["entity"] as? String ?? "?")
            let timed = ["feed", "sleep"].contains(kind)
            let ended = values.map { timed && $0["endedAt"] is NSNull ? " open" : "" } ?? ""
            return "\(change["op"] as? String ?? "?") \(kind)\(ended)"
        }
        return parts.joined(separator: ", ") + (changes.count > 4 ? ", …" : "")
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }

    private func log(_ line: String) {
        let stamp = String(format: "%.3f", Date.now.timeIntervalSince1970)
        let url = folder.appendingPathComponent("\(name).log")
        let data = Data("\(stamp) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
#endif
