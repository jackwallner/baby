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
    /// How long the undo stays offered after a tap.
    static let undoWindow: TimeInterval = 8

    var context: NSManagedObjectContext { persistence.viewContext }

    init(persistence: Persistence) {
        self.persistence = persistence
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

    func createChild(name: String?, birthDate: Date?) {
        let child = Child.make(in: context, name: name, birthDate: birthDate)
        context.assign(child, to: persistence.privateStore)
        persistence.save(context)
        setActive(child)
    }

    func setActive(_ child: Child) {
        AppGroup.defaults.set(child.id?.uuidString, forKey: AppGroup.Key.activeChildID)
        reload()
    }

    func update(child: Child, name: String?, birthDate: Date?) {
        child.name = name
        child.birthDate = birthDate
        persistence.save(context)
        reload()
    }

    /// After accepting a share: the shared baby becomes active, and the empty
    /// placeholder from onboarding goes away so there is never a second "Baby".
    func adoptSharedChildIfNeeded() {
        let children = persistence.allChildren(in: context)
        guard let shared = children.first(where: { persistence.isShared($0) }) else { return }
        for local in children where !persistence.isShared(local) && local.eventCount == 0 {
            context.delete(local)
        }
        persistence.save(context)
        setActive(shared)
    }

    // MARK: - Logging

    /// One tap. Feeds get a side; a nil side takes the suggested one.
    @discardableResult
    func log(_ kind: EventKind, side: FeedSide? = nil, at date: Date = .now) -> LogEvent? {
        guard let child else { return nil }
        let resolvedSide = kind == .feed ? (side ?? summary.suggestedSide) : nil
        let event = persistence.insert(kind: kind, at: date, side: resolvedSide, ended: kind == .feed ? date : nil, for: child, in: context)
        persistence.save(context)
        rememberForUndo(event)
        reload()
        return event
    }

    /// Starts a timed feed or sleep. A running one of the same kind ends first,
    /// so two taps never leave two open rows.
    @discardableResult
    func startTimed(_ kind: EventKind, side: FeedSide? = nil, at date: Date = .now) -> LogEvent? {
        guard kind.canRun, let child else { return nil }
        stopRunning(kind, at: date, remember: false)
        let event = persistence.insert(kind: kind, at: date, side: kind == .feed ? (side ?? summary.suggestedSide) : nil, ended: nil, for: child, in: context)
        persistence.save(context)
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
        persistence.save(context)
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

    func delete(_ event: LogEvent) {
        context.delete(event)
        persistence.save(context)
        if lastLogged?.objectID == event.objectID { lastLogged = nil }
        reload()
    }

    func save() {
        for event in events where context.updatedObjects.contains(event) {
            event.updatedAt = .now
        }
        persistence.save(context)
        reload()
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

    func undoLast() {
        guard let lastLogged, let event = try? context.existingObject(with: lastLogged.objectID) as? LogEvent else {
            self.lastLogged = nil
            return
        }
        // Undoing a "stop" reopens the row; undoing a log removes it.
        if lastLogged.reopensTimer {
            event.endedAt = nil
            event.updatedAt = .now
            persistence.save(context)
        } else {
            context.delete(event)
            persistence.save(context)
        }
        self.lastLogged = nil
        undoTask?.cancel()
        reload()
    }

    func dismissUndo() {
        lastLogged = nil
        undoTask?.cancel()
    }

    // MARK: - Relay from the Watch

    /// Applies a log made on the wrist. Idempotent on the event id so a
    /// redelivered transfer never doubles a diaper.
    func apply(_ payload: WatchLogPayload) {
        guard let child else { return }
        if let existing = events.first(where: { $0.id == payload.id }) {
            logger.info("Watch payload \(payload.id) already applied to \(existing.objectID)")
            return
        }
        switch payload.action {
        case .log:
            let event = persistence.insert(kind: payload.kind, at: payload.at, side: payload.side, ended: payload.kind == .feed ? payload.at : nil, for: child, in: context)
            event.id = payload.id
        case .startSleep:
            if runningSleep == nil {
                let event = persistence.insert(kind: .sleep, at: payload.at, side: nil, ended: nil, for: child, in: context)
                event.id = payload.id
            }
        case .stopSleep:
            if let running = runningSleep {
                running.endedAt = max(payload.at, running.start)
                running.updatedAt = .now
            }
        }
        persistence.save(context)
        reload()
    }
}
