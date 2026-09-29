import AppIntents
import CoreData
import Foundation
import WidgetKit

private struct IntentSaveError: LocalizedError {
    var errorDescription: String? { "I couldn't save that change. Please try again." }
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
    /// like the flashlight. It only ever adds an entry.
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "What", default: .wet)
    var what: LogChoice

    init() {}

    init(what: LogChoice) {
        self.what = what
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$what)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // A button turned off in Settings shows nowhere, so a control, the
        // Action button or Siri says so rather than log something invisible.
        let kind = what.loggedKind ?? .sleep
        if !TrackedKinds.current.contains(kind) {
            return .result(dialog: "\(kind.label) is turned off in Baby Tracker's Settings, so nothing was logged.")
        }
#if BABY_WIDGET
        // Keep the extension build self-contained. iOS executes the app-target
        // implementation of a LiveActivityIntent in the app process.
        let persistence = Persistence.shared
        let context = persistence.viewContext
        guard let child = persistence.activeChild(in: context) else {
            return .result(dialog: "Open Baby Tracker once to set up your baby first.")
        }
        let now = Date.now
        if what.isDoubleTap(at: now) {
            return .result(dialog: IntentDialog(stringLiteral: what.loggedDialog))
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
                return .result(dialog: "I couldn't save that feed. Please try again.")
            }
            if let id = event.id { WidgetUndo(eventID: id, kind: .feed, loggedAt: now, closedIDs: closed).store() }
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: IntentDialog(stringLiteral: what.feedDialog))
        case .wet, .dirty:
            let kind: EventKind = what == .wet ? .wet : .dirty
            let event = persistence.insert(kind: kind, at: now, side: nil, ended: nil, for: child, in: context)
            guard persistence.save(context) else {
                return .result(dialog: "I couldn't save that diaper. Please try again.")
            }
            if let id = event.id { WidgetUndo(eventID: id, kind: kind, loggedAt: now).store() }
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Logged a \(kind.label.lowercased()) diaper.")
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
                    return .result(dialog: "I couldn't save that wake. Please try again.")
                }
                WidgetCenter.shared.reloadAllTimelines()
                return .result(dialog: "Sleep ended.")
            }
            persistence.insert(kind: .sleep, at: now, side: nil, ended: nil, for: child, in: context)
            guard persistence.save(context) else {
                return .result(dialog: "I couldn't save that sleep. Please try again.")
            }
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Sleep started.")
        }
#else
        let store = EventStore.shared
        guard store.child != nil else {
            return .result(dialog: "Open Baby Tracker once to set up your baby first.")
        }
        let now = Date.now
        if what.isDoubleTap(at: now) {
            return .result(dialog: IntentDialog(stringLiteral: what.loggedDialog))
        }
        switch what {
        case .feed, .feedLeft, .feedRight, .bottle:
            guard let event = store.log(.feed, side: what.feedSide, at: now) else {
                return .result(dialog: "I couldn't save that feed. Please try again.")
            }
            store.offerWidgetUndo(for: event)
            return .result(dialog: IntentDialog(stringLiteral: what.feedDialog))
        case .wet, .dirty:
            let eventKind: EventKind = what == .wet ? .wet : .dirty
            guard let event = store.log(eventKind, at: now) else {
                return .result(dialog: "I couldn't save that diaper. Please try again.")
            }
            store.offerWidgetUndo(for: event)
            return .result(dialog: "Logged a \(eventKind.label.lowercased()) diaper.")
        case .sleep:
            if store.runningSleep != nil {
                guard store.stopRunning(.sleep, at: now, remember: false) else {
                    return .result(dialog: "I couldn't save that wake. Please try again.")
                }
                return .result(dialog: "Sleep ended.")
            }
            guard store.startTimed(.sleep, at: now) != nil else {
                return .result(dialog: "I couldn't save that sleep. Please try again.")
            }
            return .result(dialog: "Sleep started.")
        }
#endif
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

    /// The kind a log choice writes; nil for the sleep toggle.
    var loggedKind: EventKind? {
        switch self {
        case .feed, .feedLeft, .feedRight, .bottle: .feed
        case .wet: .wet
        case .dirty: .dirty
        case .sleep: nil
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
        WidgetUndo.clear()
        guard undo.isAcceptable(at: .now) else {
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
#if BABY_WIDGET
        let persistence = Persistence.shared
        let context = persistence.viewContext
        let found = persistence.events(ids: [undo.eventID] + undo.closedIDs, in: context)
        for event in found {
            if event.id == undo.eventID {
                context.delete(event)
            } else {
                event.endedAt = nil
                event.updatedAt = .now
            }
        }
        guard persistence.save(context) else { throw IntentSaveError() }
#else
        EventStore.shared.undoWidgetLog(undo)
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

    @Parameter(title: "Kind")
    var kind: String

    init() {
        kind = EventKind.sleep.rawValue
    }

    init(kind: String) {
        self.kind = kind
    }

    @MainActor
    func perform() async throws -> some IntentResult {
#if BABY_WIDGET
        let persistence = Persistence.shared
        let context = persistence.viewContext
        guard let child = persistence.activeChild(in: context),
              let eventKind = EventKind(rawValue: kind) else { return .result() }
        let now = Date.now
        for event in persistence.runningEvents(eventKind, for: child, in: context) {
            event.endedAt = now
            event.updatedAt = now
        }
        guard persistence.save(context) else { throw IntentSaveError() }
        WidgetCenter.shared.reloadAllTimelines()
#else
        guard let eventKind = EventKind(rawValue: kind) else { return .result() }
        let store = EventStore.shared
        let isRunning: Bool = switch eventKind {
        case .feed: store.runningFeed != nil
        case .sleep: store.runningSleep != nil
        default: false
        }
        guard isRunning else { return .result() }
        guard store.stopRunning(eventKind, at: .now, remember: false) else { throw IntentSaveError() }
#endif
        return .result()
    }
}
