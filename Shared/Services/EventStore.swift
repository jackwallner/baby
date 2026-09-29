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
        /// When the entry happened (or the timer ended), so a backdated tap
        /// can say which time it was logged at.
        var eventAt: Date?
        var reopensTimer = false
        /// Timers this action ended on the way, reopened again by Undo.
        var closedTimers: [NSManagedObjectID] = []
        /// Set when the action was a delete; Undo puts the entry back.
        var deleted: DeletedEvent?
    }

    /// Everything needed to put a deleted entry back as it was.
    struct DeletedEvent: Equatable {
        let childID: NSManagedObjectID
        let values: [String: AnyHashable]
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
        // The log was shut when the process started (a push woke the app on a
        // phone that had not been unlocked yet) and is open now.
        observers.append(center.addObserver(
            forName: Persistence.storesDidReopen,
            object: persistence,
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
            // A removed or not-yet-imported selection can fall back to a
            // stored baby. Keep the widget's identity in step with that choice.
            if let id = child.id?.uuidString,
               AppGroup.defaults.string(forKey: AppGroup.Key.activeChildID) != id {
                AppGroup.defaults.set(id, forKey: AppGroup.Key.activeChildID)
            }
            // A turned-off button's entries stay stored but leave every
            // surface that reads the log, until it is turned back on.
            let tracked = TrackedKinds.current
            events = persistence.events(for: child, in: context).filter { tracked.contains($0.eventKind) }
        } else {
            events = []
        }
        runningSleep = events.first { $0.eventKind == .sleep && $0.isRunning }
        runningFeed = events.first { $0.eventKind == .feed && $0.isRunning }
        summary = NowSummary.make(child: child, events: events)
        revision += 1
        summary.store()
        publish()
    }

    /// The diaper words changed: redraw this process and every other surface.
    func republishLabels() {
        objectWillChange.send()
        publish()
    }

    /// Pushes the fresh summary to every other surface.
    private func publish() {
        WidgetCenter.shared.reloadAllTimelines()
        WatchSyncService.shared.push(summary: summary)
        LiveActivityService.shared.sync(summary: summary)
    }

    /// Found once per reload rather than on every read: the log buttons ask
    /// on each render, and with nothing running each ask walked every entry.
    private(set) var runningSleep: LogEvent?
    private(set) var runningFeed: LogEvent?

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

    /// One tap. A feed's side is optional: nil logs a feed with no side, and
    /// `configure` can set several.
    @discardableResult
    func log(
        _ kind: EventKind,
        side: FeedSide? = nil,
        at date: Date = .now,
        configure: ((LogEvent) -> Void)? = nil
    ) -> LogEvent? {
        guard let child else { return nil }
        // A completed feed logged during a running one means the running feed
        // is over, otherwise Now would keep saying "Feeding" for the older row.
        let closed = kind == .feed ? closeRunning(.feed, at: date) : []
        let event = persistence.insert(kind: kind, at: date, side: kind == .feed ? side : nil, ended: kind == .feed ? date : nil, for: child, in: context)
        configure?(event)
        guard persistence.save(context) else {
            reload()
            return nil
        }
        rememberForUndo(event, closedTimers: closed)
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
        let closed = closeRunning(kind, at: date, onlyStartedBefore: false)
        let event = persistence.insert(kind: kind, at: date, side: kind == .feed ? side : nil, ended: nil, for: child, in: context)
        configure?(event)
        guard persistence.save(context) else {
            reload()
            return nil
        }
        rememberForUndo(event, closedTimers: closed)
        reload()
        return event
    }

    /// Ends the running feed or sleep. Returns false if nothing was running.
    /// Two parents who each started the same sleep before their phones synced
    /// leave two open rows; one Wake ends both, and Undo reopens both.
    @discardableResult
    func stopRunning(_ kind: EventKind, at date: Date = .now, remember: Bool = true) -> Bool {
        let running = events.filter { $0.eventKind == kind && $0.isRunning }
        guard let newest = running.first else { return false }
        for event in running {
            event.endedAt = max(date, event.start)
            event.updatedAt = .now
        }
        guard persistence.save(context) else {
            reload()
            return false
        }
        if remember { rememberForUndo(newest, reopensTimer: true, closedTimers: running.dropFirst().map(\.objectID)) }
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

    /// Ends running rows of `kind` in the context without saving, and returns
    /// them so Undo can reopen them. A backdated entry from before a timer
    /// started leaves that timer alone.
    private func closeRunning(_ kind: EventKind, at date: Date, onlyStartedBefore: Bool = true) -> [NSManagedObjectID] {
        let running = events.filter { $0.eventKind == kind && $0.isRunning && (!onlyStartedBefore || $0.start <= date) }
        for event in running {
            event.endedAt = max(date, event.start)
            event.updatedAt = .now
        }
        return running.map(\.objectID)
    }

    /// Deletes an entry and offers Undo, so a stray swipe never loses a feed.
    @discardableResult
    func delete(_ event: LogEvent) -> Bool {
        let childID = event.child?.objectID
        let values = event.entity.attributesByName.keys.reduce(into: [String: AnyHashable]()) { values, name in
            if let value = event.value(forKey: name) as? AnyHashable { values[name] = value }
        }
        let kind = event.eventKind
        let detail = event.detailText
        let objectID = event.objectID
        context.delete(event)
        guard persistence.save(context) else {
            reload()
            return false
        }
        if let childID {
            remember(LoggedEvent(objectID: objectID, kind: kind, detail: detail, at: .now, deleted: DeletedEvent(childID: childID, values: values)))
        } else if lastLogged?.objectID == objectID {
            dismissUndo()
        }
        reload()
        return true
    }

    @discardableResult
    func save() -> Bool {
        for case let event as LogEvent in context.updatedObjects {
            event.updatedAt = .now
        }
        let saved = persistence.save(context)
        reload()
        return saved
    }

    // MARK: - Undo

    private func rememberForUndo(_ event: LogEvent, reopensTimer: Bool = false, closedTimers: [NSManagedObjectID] = []) {
        let when = reopensTimer ? (event.endedAt ?? .now) : event.start
        remember(LoggedEvent(objectID: event.objectID, kind: event.eventKind, detail: event.detailText, at: .now, eventAt: when, reopensTimer: reopensTimer, closedTimers: closedTimers))
    }

    private func remember(_ logged: LoggedEvent) {
        lastLogged = logged
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            guard !Task.isCancelled else { return }
            self?.lastLogged = nil
        }
    }

    @discardableResult
    func undoLast() -> Bool {
        guard let lastLogged else { return false }
        let widgetUndo = WidgetUndo.load()
        let clearsWidgetUndo = widgetUndo.map { undo in
            persistence.events(ids: [undo.eventID], in: context).contains { $0.objectID == lastLogged.objectID }
        } ?? false
        if let deleted = lastLogged.deleted {
            guard restore(deleted) else {
                self.lastLogged = nil
                return false
            }
        } else {
            guard let event = try? context.existingObject(with: lastLogged.objectID) as? LogEvent else {
                self.lastLogged = nil
                return false
            }
            // Undoing a "stop" reopens the row; undoing a log removes it and
            // reopens any timer the log ended.
            if lastLogged.reopensTimer {
                event.endedAt = nil
                event.updatedAt = .now
            } else {
                context.delete(event)
            }
            for id in lastLogged.closedTimers {
                guard let closed = try? context.existingObject(with: id) as? LogEvent else { continue }
                closed.endedAt = nil
                closed.updatedAt = .now
            }
        }
        guard persistence.save(context) else {
            reload()
            return false
        }
        self.lastLogged = nil
        undoTask?.cancel()
        if clearsWidgetUndo {
            WidgetUndo.clear()
            AppGroup.defaults.removeObject(forKey: AppGroup.Key.widgetLogResult)
        }
        reload()
        return true
    }

    /// Recreates a deleted entry in its baby's store, with its original id.
    private func restore(_ deleted: DeletedEvent) -> Bool {
        guard let child = try? context.existingObject(with: deleted.childID) as? Child,
              let store = child.objectID.persistentStore else { return false }
        let event = LogEvent(context: context)
        for (name, value) in deleted.values {
            event.setValue(value, forKey: name)
        }
        event.child = child
        event.updatedAt = .now
        context.assign(event, to: store)
        return true
    }

    func dismissUndo() {
        lastLogged = nil
        undoTask?.cancel()
    }

    // MARK: - Undo outside the app

    /// A widget, control or Siri just logged `event`: offer it back on the
    /// one-button widgets for a few seconds.
    func offerWidgetUndo(for event: LogEvent) {
        guard let id = event.id else { return }
        let closed = lastLogged?.objectID == event.objectID ? lastLogged?.closedTimers ?? [] : []
        let closedIDs = closed.compactMap { (try? context.existingObject(with: $0) as? LogEvent)?.id }
        WidgetUndo(eventID: id, kind: event.eventKind, loggedAt: .now, closedIDs: closedIDs,
                   reopensTimer: lastLogged?.objectID == event.objectID && lastLogged?.reopensTimer == true,
                   childID: child?.id).store()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The widget's Undo: removes that one entry and reopens any feed timer
    /// it ended. False if the entry is already gone.
    @discardableResult
    func undoWidgetLog(_ undo: WidgetUndo) -> Bool {
        let found = persistence.events(ids: [undo.eventID] + undo.closedIDs, in: context)
        guard let event = found.first(where: { $0.id == undo.eventID }) else {
            reload()
            return false
        }
        guard event.child == child else { return false }
        let objectID = event.objectID
        if undo.reopensTimer {
            event.endedAt = nil
            event.updatedAt = .now
        } else {
            context.delete(event)
        }
        for closed in found where closed.id != undo.eventID {
            closed.endedAt = nil
            closed.updatedAt = .now
        }
        guard persistence.save(context) else {
            reload()
            return false
        }
        if lastLogged?.objectID == objectID { dismissUndo() }
        reload()
        return true
    }

    /// Keep the offered Undo after a failed save so the same tap can retry.
    func performWidgetUndo(eventID: String, at now: Date = .now) throws {
        guard let undo = WidgetUndo.load(), undo.eventID.uuidString == eventID else { return }
        guard undo.isAcceptable(at: now) else {
            WidgetUndo.clear()
            return
        }
        let exists = persistence.events(ids: [undo.eventID], in: context).contains { $0.child == child }
        if exists && !undoWidgetLog(undo) { throw WidgetSaveError() }
        WidgetUndo.clear()
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.widgetLogResult)
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
            if payload.kind == .feed {
                for running in targetEvents where running.eventKind == .feed && running.isRunning && running.start <= payload.at {
                    running.endedAt = payload.at
                    running.updatedAt = .now
                }
            }
            let event = persistence.insert(kind: payload.kind, at: payload.at, side: payload.side, ended: payload.kind == .feed ? payload.at : nil, for: target, in: context)
            event.id = payload.id
        case .startSleep:
            if targetEvents.first(where: { $0.eventKind == .sleep && $0.isRunning }) == nil {
                let event = persistence.insert(kind: .sleep, at: payload.at, side: nil, ended: nil, for: target, in: context)
                event.id = payload.id
            }
        case .stopSleep:
            for running in targetEvents where running.eventKind == .sleep && running.isRunning && payload.at >= running.start {
                running.endedAt = payload.at
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
