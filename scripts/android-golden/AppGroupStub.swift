import Foundation

/// The exporter's stand-in for the App Group: plain defaults in a private
/// suite, so running it never touches the app's real settings.
enum AppGroup {
    static let subsystem = "com.jackwallner.baby.golden"
    static let defaults = UserDefaults(suiteName: "com.jackwallner.baby.golden") ?? .standard

    enum Key {
        static let hiddenKinds = "hiddenKinds"
        static let diaperWords = "diaperWords"
        static let totalsWindow = "totalsWindow"
        static let nowSummary = "nowSummary"
    }
}
