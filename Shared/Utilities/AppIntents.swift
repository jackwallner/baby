import AppIntents
import CoreData
import Foundation
import os
import WidgetKit

struct WidgetSaveError: LocalizedError {
    var message = "I couldn't save that change. Please try again."
    var errorDescription: String? { message }
}

/// One-tap logging from the home screen, the lock screen, Siri, Shortcuts and
/// the Action button. A `LiveActivityIntent` runs in the app's own process,
/// where the CloudKit-mirrored stores live. CloudKit delivers the change to a
/// partner asynchronously, with no fixed timing. It also starts and ends the
/// sleep and feed timers the Live Activity shows.
struct LogEventIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log a feed or diaper"
    static let description = IntentDescription("Logs a feed, a pee or poop diaper, or sleep right now.")
    static let openAppWhenRun = false
    /// A tap on a Lock Screen widget or control logs without unlocking,
    /// like the flashlight. Sleep also ends its running timer.
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "What", default: .wet)
    var what: LogChoice

    /// Only the hidden widget intent supplies this, so Shortcuts never asks
    /// a parent to enter an internal baby identifier.
    var childID: String?

    init() {}

    init(what: LogChoice, childID: UUID? = nil) {
        self.what = what
        self.childID = childID?.uuidString
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$what)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try recordLog()))
    }

    @MainActor
    func recordLog() throws -> String {
        let kind = what.loggedKind ?? .sleep
        do {
            let dialog = try log()
            WidgetLogResult(kind: kind, message: dialog, succeeded: true).store()
            return dialog
        } catch {
            WidgetLogResult(kind: kind, message: error.localizedDescription, succeeded: false).store()
            throw error
        }
    }

    @MainActor
    private func log() throws -> String {
        // A button turned off in Settings shows nowhere, so a control, the
        // Action button or Siri says so rather than log something invisible.
        let kind = what.loggedKind ?? .sleep
        if !TrackedKinds.current.contains(kind) {
            throw WidgetSaveError(message: "\(kind.label) is turned off in Baby Tracker's Settings, so nothing was logged.")
        }
#if BABY_WIDGET
        // Keep the extension build self-contained. iOS executes the app-target
        // implementation of a LiveActivityIntent in the app process.
        let persistence = Persistence.shared
        let context = persistence.viewContext
        guard let child = persistence.activeChild(in: context) else {
            throw WidgetSaveError(message: "Open Baby Tracker once to set up your baby first.")
        }
        if let childID, child.id?.uuidString != childID {
            throw WidgetSaveError(message: "The selected baby changed. Open Baby Tracker to refresh this widget.")
        }
        let now = Date.now
        if what.isDoubleTap(at: now) {
            return what.loggedDialog
        }
        switch what {
        case .feed, .feedLeft, .feedRight, .bottle:
            let side = what.feedSide
            // A completed feed ends any feed timer still running, as in the app.
            let running = persistence.runningEvents(.feed, for: child, in: context)
            for event in running {
                event.endedAt = max(now, event.start)
                event.updatedAt = now
            }
            let closed = running.compactMap(\.id)
            let event = persistence.insert(kind: .feed, at: now, side: side, ended: now, for: child, in: context)
            guard persistence.save(context) else {
                throw WidgetSaveError(message: "I couldn't save that feed. Please try again.")
            }
            if let id = event.id { WidgetUndo(eventID: id, kind: .feed, loggedAt: now, closedIDs: closed, childID: child.id).store() }
            WidgetCenter.shared.reloadAllTimelines()
            return what.feedDialog
        case .wet, .dirty:
            let kind: EventKind = what == .wet ? .wet : .dirty
            let event = persistence.insert(kind: kind, at: now, side: nil, ended: nil, for: child, in: context)
            guard persistence.save(context) else {
                throw WidgetSaveError(message: "I couldn't save that diaper. Please try again.")
            }
            if let id = event.id { WidgetUndo(eventID: id, kind: kind, loggedAt: now, childID: child.id).store() }
            WidgetCenter.shared.reloadAllTimelines()
            return "Logged a \(kind.label.lowercased()) diaper."
        case .sleep:
            let running = persistence.runningEvents(.sleep, for: child, in: context)
            if !running.isEmpty {
                // Every open sleep, including one a partner started before
                // the two phones synced.
                for event in running {
                    event.endedAt = max(now, event.start)
                    event.updatedAt = now
                }
                guard persistence.save(context) else {
                    throw WidgetSaveError(message: "I couldn't save that wake. Please try again.")
                }
                if let first = running.first, let id = first.id {
                    WidgetUndo(eventID: id, kind: .sleep, loggedAt: now,
                               closedIDs: running.dropFirst().compactMap(\.id),
                               reopensTimer: true, childID: child.id).store()
                }
                WidgetCenter.shared.reloadAllTimelines()
                return "Sleep ended."
            }
            let sleep = persistence.insert(kind: .sleep, at: now, side: nil, ended: nil, for: child, in: context)
            guard persistence.save(context) else {
                throw WidgetSaveError(message: "I couldn't save that sleep. Please try again.")
            }
            if let id = sleep.id { WidgetUndo(eventID: id, kind: .sleep, loggedAt: now, childID: child.id).store() }
            WidgetCenter.shared.reloadAllTimelines()
            return "Sleep started."
        }
#else
        return try log(in: EventStore.shared, at: .now)
#endif
    }
#if !BABY_WIDGET
    @MainActor
    func log(in store: EventStore, at now: Date) throws -> String {
        let kind = what.loggedKind ?? .sleep
        guard TrackedKinds.current.contains(kind) else {
            throw WidgetSaveError(message: "\(kind.label) is turned off in Baby Tracker's Settings, so nothing was logged.")
        }
        guard store.child != nil else {
            throw WidgetSaveError(message: "Open Baby Tracker once to set up your baby first.")
        }
        if let childID, store.child?.id?.uuidString != childID {
            throw WidgetSaveError(message: "The selected baby changed. Open Baby Tracker to refresh this widget.")
        }
        if what.isDoubleTap(at: now) {
            return what.loggedDialog
        }
        switch what {
        case .feed, .feedLeft, .feedRight, .bottle:
            guard let event = store.log(.feed, side: what.feedSide, at: now) else {
                throw WidgetSaveError(message: "I couldn't save that feed. Please try again.")
            }
            store.offerWidgetUndo(for: event)
            return what.feedDialog
        case .wet, .dirty:
            let eventKind: EventKind = what == .wet ? .wet : .dirty
            guard let event = store.log(eventKind, at: now) else {
                throw WidgetSaveError(message: "I couldn't save that diaper. Please try again.")
            }
            store.offerWidgetUndo(for: event)
            return "Logged a \(eventKind.label.lowercased()) diaper."
        case .sleep:
            if let sleep = store.runningSleep {
                guard store.stopRunning(.sleep, at: now) else {
                    throw WidgetSaveError(message: "I couldn't save that wake. Please try again.")
                }
                store.offerWidgetUndo(for: sleep)
                return "Sleep ended."
            }
            guard let sleep = store.startTimed(.sleep, at: now) else {
                throw WidgetSaveError(message: "I couldn't save that sleep. Please try again.")
            }
            store.offerWidgetUndo(for: sleep)
            return "Sleep started."
        }
    }
#endif
}

/// Keep the public Siri action's parameters stable. Widgets carry their
/// displayed baby's identity in an action that is hidden from Shortcuts.
struct WidgetLogEventIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log an event"
    static let openAppWhenRun = false
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "What", default: "wet")
    var what: String

    @Parameter(title: "Baby", default: "")
    var childID: String

    init() {}

    init(what: LogChoice, childID: UUID?) {
        self.what = what.rawValue
        self.childID = childID?.uuidString ?? ""
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let logger = Logger(subsystem: "com.jackwallner.baby", category: "WidgetIntents")
        logger.info("Widget log started")
        guard let choice = LogChoice(rawValue: what) else { throw WidgetSaveError() }
        _ = try LogEventIntent(what: choice, childID: UUID(uuidString: childID)).recordLog()
        logger.info("Widget log saved")
        return .result()
    }
}

enum LogChoice: String, AppEnum {
    case feed
    case feedLeft
    case feedRight
    case bottle
    case wet
    case dirty
    case sleep

    /// The explicit choice for a side, so a button labelled "Feed L" saves
    /// Left even if its timeline is a few minutes old.
    static func feed(_ side: FeedSide) -> LogChoice {
        switch side {
        case .left: .feedLeft
        case .right: .feedRight
        case .bottle: .bottle
        }
    }

    /// Plain Feed has no side, as on the phone's Feed button.
    var feedSide: FeedSide? {
        switch self {
        case .feedLeft: .left
        case .feedRight: .right
        case .bottle: .bottle
        default: nil
        }
    }

    /// The kind a log choice writes, including either sleep action.
    var loggedKind: EventKind? {
        switch self {
        case .feed, .feedLeft, .feedRight, .bottle: .feed
        case .wet: .wet
        case .dirty: .dirty
        case .sleep: .sleep
        }
    }

    /// A second tap on the same tile before it could redraw as Undo: the
    /// first tap already logged it, so this one logs nothing.
    func isDoubleTap(at now: Date) -> Bool {
        guard let loggedKind, let recent = WidgetUndo.load() else { return false }
        return recent.kind == loggedKind && now >= recent.loggedAt && now.timeIntervalSince(recent.loggedAt) < WidgetUndo.doubleTapWindow
    }

    var loggedDialog: String {
        switch self {
        case .wet, .dirty: "Logged a \(loggedKind?.label.lowercased() ?? "") diaper."
        case .sleep: WidgetUndo.load()?.reopensTimer == true ? "Sleep ended." : "Sleep started."
        default: feedDialog
        }
    }

    var feedDialog: String {
        guard let feedSide else { return "Logged a feed." }
        return "Logged a feed, \(feedSide.label.lowercased())."
    }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Log")
    static let caseDisplayRepresentations: [LogChoice: DisplayRepresentation] = [
        .feed: "Feed",
        .feedLeft: "Feed, left",
        .feedRight: "Feed, right",
        .bottle: "Bottle",
        .wet: DisplayRepresentation(title: "Pee diaper", synonyms: ["Wet diaper"]),
        .dirty: DisplayRepresentation(title: "Poop diaper", synonyms: ["Dirty diaper"]),
        .sleep: "Sleep (start or end)",
    ]
}

/// "Hey Siri, log a pee diaper in Baby Tracker." Also what the Action button
/// picks from.
struct BabyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogEventIntent(what: .wet),
            phrases: ["Log a pee diaper in \(.applicationName)", "Log a wet diaper in \(.applicationName)"],
            shortTitle: "Pee diaper",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogEventIntent(what: .dirty),
            phrases: ["Log a poop diaper in \(.applicationName)", "Log a dirty diaper in \(.applicationName)"],
            shortTitle: "Poop diaper",
            systemImageName: "drop.triangle.fill"
        )
        AppShortcut(
            intent: LogEventIntent(what: .feed),
            phrases: ["Log a feed in \(.applicationName)"],
            shortTitle: "Feed",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogEventIntent(what: .sleep),
            phrases: ["Start sleep in \(.applicationName)", "End sleep in \(.applicationName)"],
            shortTitle: "Sleep",
            systemImageName: "moon.fill"
        )
    }
}

/// Undo on a one-button widget, a few seconds after its tap. Removes exactly
/// the entry that tap logged, and nothing once its short window has passed.
struct UndoWidgetLogIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Undo a widget log"
    static let openAppWhenRun = false
    static let isDiscoverable = false
    /// Only ever takes back what a locked-phone tap just added.
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Entry")
    var eventID: String

    init() {
        eventID = ""
    }

    init(eventID: UUID) {
        self.eventID = eventID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // A stale tile's Undo must not cost a newer tap its own Undo.
        guard let undo = WidgetUndo.load(), undo.eventID.uuidString == eventID else {
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
        guard undo.isAcceptable(at: .now) else {
            WidgetUndo.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
#if BABY_WIDGET
        let persistence = Persistence.shared
        let context = persistence.viewContext
        let found = persistence.events(ids: [undo.eventID] + undo.closedIDs, in: context)
        for event in found {
            if event.id == undo.eventID && !undo.reopensTimer {
                context.delete(event)
            } else {
                event.endedAt = nil
                event.updatedAt = .now
            }
        }
        guard persistence.save(context) else { throw WidgetSaveError() }
        WidgetUndo.clear()
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.widgetLogResult)
#else
        try EventStore.shared.performWidgetUndo(eventID: eventID)
#endif
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// The Stop button on the Live Activity. A `LiveActivityIntent` runs in the
/// app's own process, which is the only place the activity can be ended.
@available(iOS 17.2, *)
struct StopRunningIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop"
    static let description = IntentDescription("Ends the running feed or sleep.")
    static let openAppWhenRun = false
    static let isDiscoverable = false
    /// Stop on the Lock Screen works without unlocking, like the log buttons.
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Kind")
    var kind: String

    // A string preserves every fraction of a second across intent transport.
    @Parameter(title: "Timer", default: "")
    var timerStart: String

    private var startedAt: Date? {
        Double(timerStart).map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    init() {
        kind = EventKind.sleep.rawValue
    }

    init(kind: String, startedAt: Date? = nil) {
        self.kind = kind
        self.timerStart = startedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? ""
    }

    @MainActor
    func perform() async throws -> some IntentResult {
#if BABY_WIDGET
        let persistence = Persistence.shared
        let context = persistence.viewContext
        guard let child = persistence.activeChild(in: context),
              let eventKind = EventKind(rawValue: kind) else { return .result() }
        let now = Date.now
        let running = persistence.runningEvents(eventKind, for: child, in: context)
        if let startedAt, !running.contains(where: { $0.start == startedAt }) { return .result() }
        for event in running {
            event.endedAt = max(now, event.start)
            event.updatedAt = now
        }
        guard persistence.save(context) else { throw WidgetSaveError() }
        WidgetCenter.shared.reloadAllTimelines()
#else
        try stop(in: EventStore.shared)
#endif
        return .result()
    }

#if !BABY_WIDGET
    @MainActor
    func stop(in store: EventStore) throws {
        guard let eventKind = EventKind(rawValue: kind) else { return }
        let isRunning: Bool = switch eventKind {
        case .feed: store.runningFeed != nil
        case .sleep: store.runningSleep != nil
        default: false
        }
        guard isRunning else { return }
        let currentStart = eventKind == .sleep ? store.runningSleep?.start : store.runningFeed?.start
        if let startedAt, currentStart != startedAt { return }
        guard store.stopRunning(eventKind, at: .now, remember: false) else { throw WidgetSaveError() }
    }
#endif
}
