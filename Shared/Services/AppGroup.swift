import Foundation

/// The shared container every process reads: app, widgets, Watch app, and the
/// Watch complication. Keys live here so the four targets cannot drift.
enum AppGroup {
    static let id = "group.com.jackwallner.baby"
    static let cloudKitContainerID = "iCloud.com.jackwallner.baby"
    static let bundleID = "com.jackwallner.baby"
    static let subsystem = "com.jackwallner.baby"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    enum Key {
        static let cachedPro = "isPro"
        static let hasCompletedSetup = "hasCompletedSetup"
        static let activeChildID = "activeChildID"
        static let pendingSharedZone = "pendingSharedZone"
        static let appearance = "appearance"
        static let diaperWords = "diaperWords"
        /// `TrackedKinds`: the buttons this family turned off.
        static let hiddenKinds = "hiddenKinds"
        /// `TotalsWindow.storedValue`: the hour the totals day starts, or -1.
        static let totalsWindow = "totalsWindow"
        /// The Watch's copy of the phone's summary, and the phone's last push.
        static let nowSummary = "nowSummary"
        /// Watch-only: log events that have not yet reached the phone.
        static let pendingWatchEvents = "pendingWatchEvents"
        /// Watch-only: the phone's last summary as sent, before the wrist's
        /// own unconfirmed taps are replayed over it.
        static let phoneSummary = "phoneSummary"
        static let appliedWatchActions = "appliedWatchActions"
        /// `WidgetUndo`: the last entry logged outside the app, for the
        /// one-button widgets' Undo.
        static let widgetUndo = "widgetUndo"
        static let widgetLogResult = "widgetLogResult"
        /// Widget and complication kinds, for `reloadTimelines(ofKind:)`.
        static let feedingPreference = "feedingPreference"
    }

    /// Complications open the Watch app with `babywatch://log/<kind>` to log
    /// in one tap. `babywatch://open` just opens it.
    enum WatchLink {
        static let scheme = "babywatch"

        static func log(_ kind: EventKind) -> URL {
            URL(string: "\(scheme)://log/\(kind.rawValue)")!
        }

        static let open = URL(string: "\(scheme)://open")!

        /// The kind a link logs, or nil for any other link.
        static func kind(in url: URL) -> EventKind? {
            guard url.scheme == scheme, url.host == "log" else { return nil }
            return EventKind(rawValue: url.lastPathComponent)
        }
    }

    enum WidgetKind {
        static let now = "BabyNowWidget"
        static let log = "BabyLogWidget"
        static let complication = "BabyWatchComplication"
        static let watchDiaper = "BabyWatchDiaper"
        static let watchLogWet = "BabyWatchLogWet"
        static let watchLogDirty = "BabyWatchLogDirty"
        static let watchSleep = "BabyWatchSleep"
        static let quickFeed = "BabyQuickFeedWidget"
        static let quickWet = "BabyQuickWetWidget"
        static let quickDirty = "BabyQuickDirtyWidget"
        static let feedControl = "com.jackwallner.baby.control.feed"
        static let wetControl = "com.jackwallner.baby.control.wet"
        static let dirtyControl = "com.jackwallner.baby.control.dirty"
    }
}
