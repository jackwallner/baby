#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity payload for a running practice/walk session: the countdown
/// target plus the current alignment, rendered in the Dynamic Island and on
/// the lock screen while the user switches apps.
struct PracticeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the session will finish - the widget renders a live countdown
        /// off this, so no per-second updates are needed.
        var endDate: Date
        /// PostureQuality rawValue ("good" / "borderline" / "bad").
        var quality: String
        /// Weighted aligned % so far.
        var alignedPercent: Int
        var paused: Bool
    }

    /// PostureSessionKind rawValue ("practice" / "walk").
    var kind: String
}
#endif
