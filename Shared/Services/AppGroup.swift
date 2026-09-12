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
        /// The Watch's copy of the phone's summary, and the phone's last push.
        static let nowSummary = "nowSummary"
        /// Watch-only: log events that have not yet reached the phone.
        static let pendingWatchEvents = "pendingWatchEvents"
        /// Widget and complication kinds, for `reloadTimelines(ofKind:)`.
        static let feedingPreference = "feedingPreference"
    }

    enum WidgetKind {
        static let now = "BabyNowWidget"
        static let log = "BabyLogWidget"
        static let complication = "BabyWatchComplication"
    }
}
