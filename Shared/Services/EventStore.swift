import CloudKit
import Combine
import CoreData
import Foundation
import os
import WidgetKit

/// The app's one door to the log: every tap, edit, undo and delete goes
/// through here, and every surface that shows the log reads from here.
///
/// Holds every event for the active baby, newest first. The volume is small
/// (a busy newborn is about 25 rows a day) so a full refetch on every change is
/// cheaper than keeping the list patched by hand, and it makes remote changes
/// from the partner, the widgets and the Watch land the same way local ones do.
@MainActor
final class EventStore: ObservableObject {
    static let shared = EventStore(persistence: .shared)

    @Published private(set) var child: Child?
    @Published private(set) var children: [Child] = []
    @Published private(set) var events: [LogEvent] = []
    @Published private(set) var summary: NowSummary = .empty
    @Published private(set) var revision = 0
    /// The last thing logged from a button, offered for undo for a short while.
    @Published private(set) var lastLogged: LoggedEvent?
    /// An invitation was accepted and its baby has not imported yet.
    @Published private(set) var isAwaitingSharedBaby = false
    /// The baby from an accepted invitation, once it arrives. The app uses it
    /// once to offer folding a separate log into the shared one.
    @Published var arrivedSharedChild: Child?

    struct LoggedEvent: Equatable {
        let objectID: NSManagedObjectID
        let kind: EventKind
        let detail: String?
        let at: Date
        var reopensTimer = false
    }

    let persistence: Persistence
    private let logger = Logger(subsystem: AppGroup.subsystem, category: "EventStore")
    private var observers: [Any] = []
    private var undoTask: Task<Void, Never>?
    private let sharedZoneID: (Child) -> CKRecordZone.ID?
    /// How long the undo stays offered after a tap.
    static let undoWindow: TimeInterval = 8

    var context: NSManagedObjectContext { persistence.viewContext }

    init(persistence: Persistence, sharedZoneID: ((Child) -> CKRecordZone.ID?)? = nil) {
        self.persistence = persistence
        self.sharedZoneID = sharedZoneID ?? { persistence.container.recordID(for: $0.objectID)?.zoneID }
        reload()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        })
    }

    // MARK: - Reading

    func reload() {
        children = persistence.allChildren(in: context)
        finishPendingShareImport()
        isAwaitingSharedBaby = AppGroup.defaults.dictionary(forKey: AppGroup.Key.pendingSharedZone) != nil
        child = persistence.activeChild(in: context)
        if let child {
            events = persistence.events(for: child, in: context)
        } else {
            events = []
        }
        summary = NowSummary.make(child: child, events: events)
        revision += 1
        summary.store()
        publish()
    }

    /// Pushes the fresh summary to every other surface.
    private func publish() {
        WidgetCenter.shared.reloadAllTimelines()
        WatchSyncService.shared.push(summary: summary)
        LiveActivityService.shared.sync(summary: summary)
    }

    var runningSleep: LogEvent? { events.first { $0.eventKind == .sleep && $0.isRunning } }
    var runningFeed: LogEvent? { events.first { $0.eventKind == .feed && $0.isRunning } }

    func tally(on day: Date, now: Date = .now) -> DayTally {
        DayTally.make(events: events, on: day, now: now)
    }

    /// Events grouped by local day, newest day first.
    var eventsByDay: [(day: Date, events: [LogEvent])] {
        let calendar = Calendar.current
        var groups: [Date: [LogEvent]] = [:]
        for event in events {
            groups[calendar.startOfDay(for: event.start), default: []].append(event)
        }
        return groups.keys.sorted(by: >).map { (day: $0, events: groups[$0] ?? []) }
    }

    // MARK: - Children

    @discardableResult
    func createChild(name: String?, birthDate: Date?) -> Bool {
        let child = Child.make(in: context, name: name, birthDate: birthDate)
        context.assign(child, to: persistence.privateStore)
        guard persistence.save(context) else {
            reload()
            return false
        }
        setActive(child)
        return true
    }

    func setActive(_ child: Child) {
        AppGroup.defaults.set(child.id?.uuidString, forKey: AppGroup.Key.activeChildID)
        reload()
    }

    @discardableResult
    func update(child: Child, name: String?, birthDate: Date?) -> Bool {
        child.name = name
        child.birthDate = birthDate
        guard persistence.save(context) else {
            reload()
            return false
        }
        reload()
        return true
    }

    /// Acceptance can finish before CloudKit imports the baby. Persist the
    /// exact zone and retry on remote changes, including after an app restart.
    func adoptSharedChildIfNeeded(in zoneID: CKRecordZone.ID) {
        AppGroup.defaults.set(["name": zoneID.zoneName, "owner": zoneID.ownerName], forKey: AppGroup.Key.pendingSharedZone)
        reload()
    }

    private func finishPendingShareImport() {
        guard let pending = AppGroup.defaults.dictionary(forKey: AppGroup.Key.pendingSharedZone),
              let name = pending["name"] as? String, let owner = pending["owner"] as? String else { return }
        let zoneID = CKRecordZone.ID(zoneName: name, ownerName: owner)
        guard let shared = children.first(where: { persistence.isShared($0) && sharedZoneID($0) == zoneID }),
              let id = shared.id else { return }
        // Keep every existing baby and log. An invitation must never delete
        // a parent's other profiles just because they have no entries yet.
        AppGroup.defaults.set(id.uuidString, forKey: AppGroup.Key.activeChildID)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.pendingSharedZone)
        arrivedSharedChild = shared
    }

    /// The person gave up waiting for an invitation's baby. Nothing is deleted;
    /// if the baby turns up later it simply appears in the list.
    func stopWaitingForSharedBaby() {
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.pendingSharedZone)
        reload()
    }

    /// Logs on this phone that are not part of `target`: a parent who started
    /// logging on their own before joining.
    func separateLogs(besides target: Child) -> [Child] {
        children.filter { !persistence.isShared($0) && $0.objectID != target.objectID && $0.eventCount > 0 }
    }

    /// Copies every entry of `source` into `target` (objects cannot change
    /// store, so each is recreated in the target's store), then removes the
    /// emptied profile. Returns how many entries moved, or nil if nothing saved.
    @discardableResult
    func moveEvents(from source: Child, into target: Child) -> Int? {
        guard source.objectID != target.objectID, let store = target.objectID.persistentStore else { return nil }
        let entries = persistence.events(for: source, in: context)
        for entry in entries {
            let copy = LogEvent(context: context)
            for name in entry.entity.attributesByName.keys {
                copy.setValue(entry.value(forKey: name), forKey: name)
            }
            copy.child = target
            context.assign(copy, to: store)
        }
        context.delete(source)
        guard persistence.save(context) else {
            reload()
            return nil
        }
        AppGroup.defaults.set(target.id?.uuidString, forKey: AppGroup.Key.activeChildID)
        reload()
        return entries.count
    }

    // MARK: - Logging

    /// One tap. Feeds get a side; a nil side takes the suggested one.
    @discardableResult
    func log(
        _ kind: EventKind,
        side: FeedSide? = nil,
        at date: Date = .now,
        configure: ((LogEvent) -> Void)? = nil
    ) -> LogEvent? {
        guard let child else { return nil }
        let resolvedSide = kind == .feed ? (side ?? summary.suggestedSide) : nil
        let event = persistence.insert(kind: kind, at: date, side: resolvedSide, ended: kind == .feed ? date : nil, for: child, in: context)
        configure?(event)
        guard persistence.save(context) else {
            reload()
            return nil
        }
        rememberForUndo(event)
        reload()
        return event
    }

    /// Starts a timed feed or sleep. A running one of the same kind ends first,
    /// so two taps never leave two open rows.
    @discardableResult
    func startTimed(
        _ kind: EventKind,
        side: FeedSide? = nil,
        at date: Date = .now,
        configure: ((LogEvent) -> Void)? = nil
    ) -> LogEvent? {
        guard kind.canRun, let child else { return nil }
        if let running = events.first(where: { $0.eventKind == kind && $0.isRunning }) {
            running.endedAt = max(date, running.start)
            running.updatedAt = .now
        }
        let event = persistence.insert(kind: kind, at: date, side: kind == .feed ? (side ?? summary.suggestedSide) : nil, ended: nil, for: child, in: context)
        configure?(event)
        guard persistence.save(context) else {
            reload()
            return nil
        }
        rememberForUndo(event)
        reload()
        return event
    }

    /// Ends the running feed or sleep. Returns false if nothing was running.
    @discardableResult
    func stopRunning(_ kind: EventKind, at date: Date = .now, remember: Bool = true) -> Bool {
        guard let running = events.first(where: { $0.eventKind == kind && $0.isRunning }) else { return false }
        running.endedAt = max(date, running.start)
        running.updatedAt = .now
        guard persistence.save(context) else {
            reload()
            return false
        }
        if remember { rememberForUndo(running, reopensTimer: true) }
        reload()
        return true
    }

    /// The Sleep button: start if nothing is running, otherwise end.
    func toggleSleep(at date: Date = .now) {
        if runningSleep != nil {
            stopRunning(.sleep, at: date)
        } else {
            startTimed(.sleep, at: date)
        }
    }

    @discardableResult
    func delete(_ event: LogEvent) -> Bool {
        context.delete(event)
        guard persistence.save(context) else {
            reload()
            return false
        }
        if lastLogged?.objectID == event.objectID { lastLogged = nil }
        reload()
        return true
    }

    @discardableResult
    func save() -> Bool {
        for event in events where context.updatedObjects.contains(event) {
            event.updatedAt = .now
        }
        let saved = persistence.save(context)
        reload()
        return saved
    }

    // MARK: - Undo

    private func rememberForUndo(_ event: LogEvent, reopensTimer: Bool = false) {
        lastLogged = LoggedEvent(objectID: event.objectID, kind: event.eventKind, detail: event.detailText, at: .now, reopensTimer: reopensTimer)
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            guard !Task.isCancelled else { return }
            self?.lastLogged = nil
        }
    }

    @discardableResult
    func undoLast() -> Bool {
        guard let lastLogged, let event = try? context.existingObject(with: lastLogged.objectID) as? LogEvent else {
            self.lastLogged = nil
            return false
        }
        // Undoing a "stop" reopens the row; undoing a log removes it.
        if lastLogged.reopensTimer {
            event.endedAt = nil
            event.updatedAt = .now
        } else {
            context.delete(event)
        }
        guard persistence.save(context) else {
            reload()
            return false
        }
        self.lastLogged = nil
        undoTask?.cancel()
        reload()
        return true
    }

    func dismissUndo() {
        lastLogged = nil
        undoTask?.cancel()
    }

    // MARK: - Relay from the Watch

    /// Applies a log made on the wrist. Idempotent on the event id so a
    /// redelivered transfer never doubles a diaper.
    @discardableResult
    func apply(_ payload: WatchLogPayload) -> Bool {
        apply(payload, forChildID: nil)
    }

    /// Applies a Watch action to the profile that was active when it was
    /// created. Older payloads have no profile ID and continue to use the
    /// current profile. A payload that names a missing profile is dropped
    /// rather than silently written to a different baby's log.
    @discardableResult
    func apply(_ payload: WatchLogPayload, forChildID childID: UUID?) -> Bool {
        var applied = AppGroup.defaults.stringArray(forKey: AppGroup.Key.appliedWatchActions) ?? []
        if applied.contains(payload.id.uuidString) { return true }
        let targetID = childID ?? payload.childID
        let target: Child?
        if let targetID {
            target = persistence.allChildren(in: context).first { $0.id == targetID }
        } else {
            target = child
        }
        guard let target else {
            logger.error("Watch payload \(payload.id) ignored because its baby profile is unavailable")
            return false
        }
        let targetEvents = persistence.events(for: target, in: context)
        if let existing = targetEvents.first(where: { $0.id == payload.id }) {
            logger.info("Watch payload \(payload.id) already applied to \(existing.objectID)")
            return true
        }
        switch payload.action {
        case .log:
            let event = persistence.insert(kind: payload.kind, at: payload.at, side: payload.side, ended: payload.kind == .feed ? payload.at : nil, for: target, in: context)
            event.id = payload.id
        case .startSleep:
            if targetEvents.first(where: { $0.eventKind == .sleep && $0.isRunning }) == nil {
                let event = persistence.insert(kind: .sleep, at: payload.at, side: nil, ended: nil, for: target, in: context)
                event.id = payload.id
            }
        case .stopSleep:
            if let running = targetEvents.first(where: { $0.eventKind == .sleep && $0.isRunning }),
               payload.at >= running.start {
                running.endedAt = max(payload.at, running.start)
                running.updatedAt = .now
            }
        }
        guard persistence.save(context) else {
            reload()
            return false
        }
        // A transport receipt does not prove a save. Remember successfully
        // applied actions, including timer stops that have no event of their own.
        applied.append(payload.id.uuidString)
        AppGroup.defaults.set(Array(applied.suffix(NowSummary.knownEventLimit)), forKey: AppGroup.Key.appliedWatchActions)
        reload()
        return true
    }
}
