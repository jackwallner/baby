#if canImport(ActivityKit)
import ActivityKit
import Foundation
import os

struct LiveActivityState: Equatable, Sendable {
    var kind: String
    var start: Date
    var side: String?
    var childName: String
    var childID: UUID?

    init?(summary: NowSummary) {
        if let start = summary.runningSleepStart {
            kind = EventKind.sleep.rawValue
            self.start = start
            side = nil
        } else if let start = summary.runningFeedStart {
            kind = EventKind.feed.rawValue
            self.start = start
            side = FeedSide.encode(summary.runningSides)
        } else {
            return nil
        }
        childName = summary.childName
        childID = summary.childID
    }
}

struct LiveActivitySnapshot: Sendable {
    var id: String
    var state: LiveActivityState
}

@MainActor
protocol LiveActivityClient {
    var areActivitiesEnabled: Bool { get }
    var activities: [LiveActivitySnapshot] { get }
    func end(_ id: String) async
    func update(_ id: String, to state: LiveActivityState) async
    func request(_ state: LiveActivityState) throws
}

@MainActor
private struct SystemLiveActivityClient: LiveActivityClient {
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    var activities: [LiveActivitySnapshot] {
        Activity<BabyActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }.map { activity in
            let content = activity.content.state
            var summary = NowSummary()
            summary.childID = activity.attributes.childID
            summary.childName = content.childName ?? activity.attributes.childName
            let kind = content.kind ?? activity.attributes.kind
            if kind == EventKind.sleep.rawValue {
                summary.runningSleepStart = activity.content.state.startedAt
            } else {
                summary.runningFeedStart = activity.content.state.startedAt
                summary.setRunningFeedSides(FeedSide.decode(content.kind == nil ? activity.attributes.side : content.side))
            }
            return LiveActivitySnapshot(id: activity.id, state: LiveActivityState(summary: summary)!)
        }
    }

    // ActivityKit's non-Sendable handle stays on the main actor.
    private struct ActivityBox: @unchecked Sendable {
        let activity: Activity<BabyActivityAttributes>
    }

    func end(_ id: String) async {
        guard let activity = Activity<BabyActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await ActivityBox(activity: activity).activity.end(nil, dismissalPolicy: .immediate)
    }

    private func content(_ state: LiveActivityState) -> ActivityContent<BabyActivityAttributes.ContentState> {
        .init(state: .init(startedAt: state.start, kind: state.kind, side: state.side, childName: state.childName), staleDate: nil)
    }

    func update(_ id: String, to state: LiveActivityState) async {
        guard let activity = Activity<BabyActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await ActivityBox(activity: activity).activity.update(content(state))
    }

    func request(_ state: LiveActivityState) throws {
        _ = try Activity.request(
            attributes: BabyActivityAttributes(kind: state.kind, side: state.side, childName: state.childName, childID: state.childID),
            content: content(state)
        )
    }
}

/// Reconciles the lock screen with the latest local or imported summary.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService(client: SystemLiveActivityClient())
    private let client: any LiveActivityClient
    private let logger = Logger(subsystem: AppGroup.subsystem, category: "LiveActivity")
    private var desired: LiveActivityState?
    private var revision = 0
    private var task: Task<Void, Never>?

    init(client: any LiveActivityClient) { self.client = client }

    func waitForUpdates() async { await task?.value }

    func sync(summary: NowSummary) {
        desired = LiveActivityState(summary: summary)
        revision += 1
        guard task == nil else { return }
        task = Task { await reconcile() }
    }

    private func reconcile() async {
        while true {
            let generation = revision
            let wanted = client.areActivitiesEnabled ? desired : nil
            let existing = client.activities
            let matching = wanted.flatMap { wanted in
                existing.first { $0.state.childID == wanted.childID }
            }
            for activity in existing where activity.id != matching?.id {
                await client.end(activity.id)
            }
            // An end may suspend while a partner edit or Undo changes the log.
            guard generation == revision else { continue }
            if let wanted {
                if let matching {
                    if matching.state != wanted { await client.update(matching.id, to: wanted) }
                } else {
                    do { try client.request(wanted) }
                    catch { logger.error("Live Activity request failed: \(String(describing: error), privacy: .public)") }
                }
            }
            guard generation == revision else { continue }
            task = nil
            return
        }
    }
}
#endif
