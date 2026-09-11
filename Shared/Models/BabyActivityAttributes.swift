#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The Live Activity for a running feed or sleep: the lock screen shows how
/// long it has been going and offers one Stop button.
struct BabyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
    }

    /// `EventKind` raw value: "feed" or "sleep".
    var kind: String
    /// `FeedSide` raw value for a feed, nil for sleep.
    var side: String?
    var childName: String
}
#endif
