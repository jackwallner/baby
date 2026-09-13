import Combine
import Foundation
import WidgetKit

/// The Watch's view of the log: the phone's last summary plus the taps made on
/// the wrist that the phone has not confirmed yet. Logging never waits for
/// the phone; the summary is updated on the spot and the transfer queues.
@MainActor
final class WatchStore: ObservableObject {
    static let shared = WatchStore()

    @Published private(set) var summary: NowSummary
    @Published private(set) var pending: [WatchLogPayload]
    @Published private(set) var lastAction: String?

    /// Set by the Watch app at launch. The complication extension shares this
    /// file but has no session, so it never sends.
    var sender: ((WatchLogPayload) -> Void)?

    private let defaults = AppGroup.defaults
    private var toastTask: Task<Void, Never>?

    private init() {
        summary = NowSummary.load()
        if let data = defaults.data(forKey: AppGroup.Key.pendingWatchEvents),
           let stored = try? JSONDecoder().decode([WatchLogPayload].self, from: data) {
            pending = stored
        } else {
            pending = []
        }
    }

    /// The phone's summary wins, then the taps it has not seen yet are
    /// replayed on top, so the wrist never shows an older state than its own.
    func receive(_ phoneSummary: NowSummary) {
        summary = phoneSummary.applyingPending(pending)
        summary.store()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func log(_ kind: EventKind, side: FeedSide? = nil) {
        let resolvedSide = kind == .feed ? (side ?? summary.suggestedSide) : nil
        send(WatchLogPayload(action: .log, kind: kind, side: resolvedSide))
        lastAction = kind == .feed ? "Logged feed · \(resolvedSide?.label ?? "")" : "Logged \(kind.label.lowercased())"
    }

    func toggleSleep() {
        if summary.isSleeping {
            send(WatchLogPayload(action: .stopSleep, kind: .sleep))
            lastAction = "Sleep ended"
        } else {
            send(WatchLogPayload(action: .startSleep, kind: .sleep))
            lastAction = "Sleep started"
        }
    }

    func markDelivered(_ id: UUID) {
        pending.removeAll { $0.id == id }
        persistPending()
        // A confirmed sleep toggle releases the one queued behind it.
        retryPending()
    }

    /// Retries unacknowledged actions when the Watch is active again. The
    /// sender deduplicates transfers already queued by WatchConnectivity.
    func retryPending() {
        for payload in WatchLogPayload.sendable(from: pending) { sender?(payload) }
    }

    private func send(_ payload: WatchLogPayload) {
        var payload = payload
        payload.childID = summary.childID
        pending.append(payload)
        persistPending()
        summary = summary.applying(payload)
        summary.store()
        WidgetCenter.shared.reloadAllTimelines()
        if WatchLogPayload.sendable(from: pending).contains(payload) { sender?(payload) }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.lastAction = nil
        }
    }

    private func persistPending() {
        defaults.set(try? JSONEncoder().encode(pending), forKey: AppGroup.Key.pendingWatchEvents)
    }
}
