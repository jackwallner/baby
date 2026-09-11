import Foundation

/// Lightweight screenshot-mode probe. App Store captures are driven through
/// launch arguments (`-ScreenshotTab`, `-PaywallSnapshot`, `-SeedScreenshotData`),
/// so surfaces that must stay out of marketing shots (the review funnel, What's
/// New) gate on this. Always false in Release.
enum ScreenshotConfig {
    #if DEBUG
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-ScreenshotTab")
            || args.contains("-PaywallSnapshot")
            || args.contains("-SeedScreenshotData")
            || args.contains("-BreakdownSnapshot")
            || args.contains("-SettingsSnapshot")
    }
    #else
    static let isEnabled = false
    #endif
}
