import Combine
import Foundation
import WidgetKit

/// The Watch's view of the log: the phone's last summary plus the taps made on
/// the wrist that the phone has not confirmed yet. Logging never waits for
/// the phone; the summary is updated on the spot and the transfer queues.
@MainActor
final class WatchStore: ObservableObject {
    static let shared = WatchStore()

    /// How long a wrist tap offers Undo, the same as the phone's widgets.
    static let undoWindow: TimeInterval = 10
    /// A second complication tap for the same kind inside this is the same tap.
    static let duplicateLinkWindow: TimeInterval = 3

    /// What the wrist just did, shown with Undo for a few seconds.
    struct Confirmation: Equatable, Identifiable {
        let id: UUID
        let kind: EventKind
        let title: String
        let canUndo: Bool
    }

    @Published private(set) var summary: NowSummary
    @Published private(set) var pending: [WatchLogPayload]
    @Published private(set) var confirmation: Confirmation?
    /// False until the phone has sent a summary: the Watch then asks for
    /// the iPhone app to be set up, and taps still queue.
    @Published private(set) var hasHeardFromPhone: Bool

    /// Set by the Watch app at launch. The complication extension shares this
    /// file but has no session, so it never sends.
    var sender: ((WatchLogPayload) -> Void)?

    private let defaults = AppGroup.defaults
    /// The phone's summary as sent. `summary` is this with `pending` replayed.
    private var phone: NowSummary
    private var lastTap: WatchLogPayload?
    private var lastLink: (kind: EventKind, at: Date)?
    private var confirmationTask: Task<Void, Never>?

    private init() {
        let stored = defaults.data(forKey: AppGroup.Key.phoneSummary).flatMap { try? JSONDecoder().decode(NowSummary.self, from: $0) }
        phone = stored ?? NowSummary.load()
        hasHeardFromPhone = stored != nil
        let queued = defaults.data(forKey: AppGroup.Key.pendingWatchEvents)
            .flatMap { try? JSONDecoder().decode([WatchLogPayload].self, from: $0) } ?? []
        pending = queued
        summary = (stored ?? NowSummary.load()).applyingPending(queued)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-WatchDemo") { seedDemo() }
        #endif
    }

    /// Taps the phone has not confirmed, not counting a tap and its Undo.
    var waitingCount: Int {
        let undone = Set(pending.compactMap(\.targetID))
        return pending.filter { $0.action != .undo && !undone.contains($0.id) }.count
    }

    /// The phone's summary wins, then the taps it has not seen yet are
    /// replayed on top, so the wrist never shows an older state than its own.
    func receive(_ phoneSummary: NowSummary) {
        // A reply and a pushed context can cross; the older one never wins.
        if hasHeardFromPhone, phoneSummary.generatedAt < phone.generatedAt { return }
        phone = phoneSummary
        hasHeardFromPhone = true
        defaults.set(try? JSONEncoder().encode(phoneSummary), forKey: AppGroup.Key.phoneSummary)
        refresh()
    }

    func log(_ kind: EventKind, side: FeedSide? = nil, at date: Date = .now) {
        guard summary.tracked.contains(kind) else { return }
        let payload = WatchLogPayload(action: .log, kind: kind, side: kind == .feed ? side : nil, at: date)
        send(payload)
        let what = kind == .feed ? (side.map { "Feed · \($0.label)" } ?? "Feed") : kind.label
        confirm(payload, title: "\(what) logged")
    }

    /// Sleep if nothing is running, otherwise Wake. A backdated Wake never
    /// lands before the sleep it ends.
    func toggleSleep(at date: Date = .now) {
        guard summary.tracked.contains(.sleep) else { return }
        if let start = summary.runningSleepStart {
            let payload = WatchLogPayload(action: .stopSleep, kind: .sleep, at: max(date, start))
            send(payload)
            confirm(payload, title: "Woke up")
        } else {
            let payload = WatchLogPayload(action: .startSleep, kind: .sleep, at: date)
            send(payload)
            confirm(payload, title: "Sleep started")
        }
    }

    /// A complication tap: `babywatch://log/wet` logs a pee, `/sleep` toggles.
    /// The same kind again within a few seconds is one tap delivered twice.
    func handle(_ url: URL, now: Date = .now) {
        guard let kind = AppGroup.WatchLink.kind(in: url), summary.tracked.contains(kind) else { return }
        if let lastLink, lastLink.kind == kind, now.timeIntervalSince(lastLink.at) < Self.duplicateLinkWindow { return }
        lastLink = (kind, now)
        switch kind {
        case .sleep: toggleSleep()
        case .wet, .dirty: log(kind)
        default: break
        }
    }

    /// Takes back the tap on show. The Undo travels like any tap, so it
    /// reaches the phone even if the tap it cancels is still on its way.
    func undo() {
        guard let confirmation, confirmation.canUndo, let target = lastTap, target.id == confirmation.id else { return }
        lastTap = nil
        send(target.undo)
        show(Confirmation(id: UUID(), kind: target.kind, title: "Removed", canUndo: false), for: 2)
    }

    func dismissConfirmation() {
        confirmationTask?.cancel()
        confirmation = nil
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

    // MARK: - Private

    private func send(_ payload: WatchLogPayload) {
        var payload = payload
        payload.childID = payload.childID ?? summary.childID
        pending.append(payload)
        persistPending()
        refresh()
        if payload.action != .undo { lastTap = payload }
        if WatchLogPayload.sendable(from: pending).contains(payload) { sender?(payload) }
    }

    private func refresh() {
        summary = phone.applyingPending(pending)
        summary.store()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func confirm(_ payload: WatchLogPayload, title: String) {
        show(Confirmation(id: payload.id, kind: payload.kind, title: title, canUndo: true), for: Self.undoWindow)
    }

    private func show(_ confirmation: Confirmation, for seconds: TimeInterval) {
        self.confirmation = confirmation
        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.confirmation = nil
        }
    }

    private func persistPending() {
        defaults.set(try? JSONEncoder().encode(pending), forKey: AppGroup.Key.pendingWatchEvents)
    }

    #if DEBUG
    /// `-WatchDemo`: a night three log, for looking at the Watch without a phone.
    private func seedDemo() {
        let now = Date.now
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        var demo = NowSummary()
        demo.childName = "Nora"
        demo.childID = UUID()
        demo.dayOfLife = 3
        demo.recent = [
            RecentEntry(id: UUID(), kind: .wet, at: ago(48), endedAt: nil, sides: nil),
            RecentEntry(id: UUID(), kind: .feed, at: ago(134), endedAt: ago(134), sides: [.left]),
            RecentEntry(id: UUID(), kind: .sleep, at: ago(310), endedAt: ago(150), sides: nil),
            RecentEntry(id: UUID(), kind: .dirty, at: ago(320), endedAt: nil, sides: nil),
            RecentEntry(id: UUID(), kind: .feed, at: ago(335), endedAt: ago(335), sides: [.right, .left]),
            RecentEntry(id: UUID(), kind: .wet, at: ago(400), endedAt: nil, sides: nil),
        ]
        demo.knownEventIDs = demo.recent?.map(\.id)
        demo.lastFeedAt = ago(134)
        demo.setLastFeedSides([.left])
        demo.lastDiaperAt = ago(48)
        demo.lastDiaperKind = .wet
        demo.lastWokeAt = ago(150)
        demo.todayFeeds = 7
        demo.todayWet = 5
        demo.todayDirty = 2
        demo.generatedAt = now
        pending = []
        persistPending()
        receive(demo)
    }
    #endif
}
