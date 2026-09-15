import AppIntents
import CoreData
import Foundation
import WidgetKit

private struct IntentSaveError: LocalizedError {
    var errorDescription: String? { "I couldn't save that change. Please try again." }
}

/// One-tap logging from the home screen, the lock screen, Siri, Shortcuts and
/// the Action button. Runs in whichever process hosts the widget, writes
/// straight into the shared store, and lets the app export it later.
struct LogEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a feed or diaper"
    static let description = IntentDescription("Logs a feed, a pee or poop diaper, or sleep right now.")
    static let openAppWhenRun = false

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
        let persistence = Persistence.shared
        let context = persistence.viewContext
        guard let child = persistence.activeChild(in: context) else {
            return .result(dialog: "Open Baby Tracker once to set up your baby first.")
        }
        let now = Date.now
        switch what {
        case .feed, .feedLeft, .feedRight, .bottle:
            let summary = NowSummary.make(child: child, events: persistence.events(for: child, in: context, limit: 50), now: now)
            let side: FeedSide = switch what {
            case .feedLeft: .left
            case .feedRight: .right
            case .bottle: .bottle
            default: summary.suggestedSide
            }
            // A completed feed ends any feed timer still running, as in the app.
            for running in persistence.runningEvents(.feed, for: child, in: context) {
                running.endedAt = max(now, running.start)
                running.updatedAt = now
            }
            persistence.insert(kind: .feed, at: now, side: side, ended: now, for: child, in: context)
            guard persistence.save(context) else {
                return .result(dialog: "I couldn't save that feed. Please try again.")
            }
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Logged a feed, \(side.label.lowercased()).")
        case .wet, .dirty:
            let kind: EventKind = what == .wet ? .wet : .dirty
            persistence.insert(kind: kind, at: now, side: nil, ended: nil, for: child, in: context)
            guard persistence.save(context) else {
                return .result(dialog: "I couldn't save that diaper. Please try again.")
            }
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Logged a \(kind.label.lowercased()) diaper.")
        case .sleep:
            let running = persistence.runningEvents(.sleep, for: child, in: context).first
            if let running {
                running.endedAt = now
                running.updatedAt = now
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

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Log")
    static let caseDisplayRepresentations: [LogChoice: DisplayRepresentation] = [
        .feed: "Feed (next side)",
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
        return .result()
    }
}
