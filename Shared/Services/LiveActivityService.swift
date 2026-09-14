#if canImport(ActivityKit)
import ActivityKit
import Foundation
import os

/// Keeps exactly one Live Activity alive while a feed or sleep runs, and none
/// otherwise. Driven from the summary so the Watch, the widgets and the app all
/// converge on the same answer.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private let logger = Logger(subsystem: AppGroup.subsystem, category: "LiveActivity")

    private init() {}

    /// `Activity` is not Sendable, and ending one is async. It is only ever
    /// touched from the main actor here, so the box is honest.
    private struct ActivityBox: @unchecked Sendable {
        let activity: Activity<BabyActivityAttributes>
    }

    private func end(_ activity: Activity<BabyActivityAttributes>) {
        let box = ActivityBox(activity: activity)
        Task { @MainActor in await box.activity.end(nil, dismissalPolicy: .immediate) }
    }

    func sync(summary: NowSummary) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let wanted: (kind: EventKind, start: Date, side: FeedSide?)?
        if let start = summary.runningSleepStart {
            wanted = (.sleep, start, nil)
        } else if let start = summary.runningFeedStart {
            wanted = (.feed, start, summary.runningFeedSide)
        } else {
            wanted = nil
        }
        let existing = Activity<BabyActivityAttributes>.activities
        guard let wanted else {
            for activity in existing {
                end(activity)
            }
            return
        }
        // Name and side are fixed attributes, so a rename or a side change
        // needs a fresh activity rather than a silent stale one.
        let matching = existing.first {
            $0.attributes.kind == wanted.kind.rawValue
                && $0.content.state.startedAt == wanted.start
                && $0.attributes.side == wanted.side?.rawValue
                && $0.attributes.childName == summary.childName
        }
        if matching != nil {
            for activity in existing where activity.id != matching?.id {
                end(activity)
            }
            return
        }
        for activity in existing {
            end(activity)
        }
        do {
            _ = try Activity.request(
                attributes: BabyActivityAttributes(kind: wanted.kind.rawValue, side: wanted.side?.rawValue, childName: summary.childName),
                content: .init(state: .init(startedAt: wanted.start), staleDate: nil)
            )
        } catch {
            logger.error("Live Activity request failed: \(String(describing: error), privacy: .public)")
        }
    }
}
#endif
