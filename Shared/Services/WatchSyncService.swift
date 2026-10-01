import Foundation
import os
import WatchConnectivity

private let watchSyncLogger = Logger(subsystem: AppGroup.subsystem, category: "WatchSync")

/// Phone to Watch: the current `NowSummary` as application context, replaced
/// on every change. Watch to phone: each tap as a queued `transferUserInfo`,
/// which survives the Watch being out of range and wakes the iPhone app in the
/// background to apply it.
final class WatchSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSyncService()

    private static let summaryKey = "summary"
    private static let diaperWordsKey = "diaperWords"
    private static let savedActionKey = "savedWatchAction"
    /// The Watch has no summary yet (installed after the phone last pushed).
    private static let needsSummaryKey = "needsSummary"
    /// Makes every push a new context, so a resend is never dropped as a duplicate.
    private static let pushedAtKey = "pushedAt"

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    #if os(iOS)
    func push(summary: NowSummary) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let context = Self.context(for: summary) else { return }
        do {
            try session.updateApplicationContext(context)
        } catch {
            watchSyncLogger.error("Summary push failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func context(for summary: NowSummary) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(summary) else { return nil }
        return [
            summaryKey: data,
            diaperWordsKey: DiaperWords.current.rawValue,
            pushedAtKey: Date.now.timeIntervalSinceReferenceDate,
        ]
    }

    /// A live message from an open Watch app: a request for the summary, or a
    /// tap, answered with its receipt once saved. Application context and
    /// queued transfers can take minutes to arrive; a reply does not.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = UncheckedReply(send: replyHandler)
        if message[Self.needsSummaryKey] != nil {
            Task { @MainActor in reply.send(Self.context(for: EventStore.shared.summary) ?? [:]) }
            return
        }
        guard let payload = Self.payload(from: message) else {
            reply.send([:])
            return
        }
        Task { @MainActor in
            let saved = EventStore.shared.apply(payload, forChildID: payload.childID)
            reply.send(saved ? [Self.savedActionKey: payload.id.uuidString] : [:])
        }
    }

    private static func payload(from userInfo: [String: Any]) -> WatchLogPayload? {
        guard var payload = WatchLogPayload(userInfo: userInfo) else { return nil }
        // Accept the temporary top-level envelope used by pre-release builds,
        // while new transfers carry the profile ID in the Codable payload.
        if payload.childID == nil,
           let childID = (userInfo["childID"] as? String).flatMap(UUID.init) {
            payload.childID = childID
        }
        return payload
    }

    /// WatchConnectivity calls the reply handler from any thread.
    private struct UncheckedReply: @unchecked Sendable {
        let send: ([String: Any]) -> Void
    }
    #endif

    #if os(watchOS)
    /// With the phone in reach, the tap goes as a message and the reply is
    /// its receipt, so the wrist hears back in a moment. Otherwise, or if the
    /// message fails, it queues as a transfer that survives being out of range.
    /// The phone applies each tap once, whichever way it arrives.
    func send(_ payload: WatchLogPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isReachable else {
            queue(payload, on: session)
            return
        }
        session.sendMessage(payload.dictionary, replyHandler: { [weak self] reply in
            guard let id = (reply[Self.savedActionKey] as? String).flatMap(UUID.init) else {
                self?.queue(payload, on: .default)
                return
            }
            Task { @MainActor in WatchStore.shared.markDelivered(id) }
        }, errorHandler: { [weak self] _ in
            self?.queue(payload, on: .default)
        })
    }

    private func queue(_ payload: WatchLogPayload, on session: WCSession) {
        guard !session.outstandingUserInfoTransfers.contains(where: {
            WatchLogPayload(userInfo: $0.userInfo)?.id == payload.id
        }) else { return }
        session.transferUserInfo(payload.dictionary)
    }

    /// Asks the phone for its latest summary while it is reachable, when the
    /// Watch app opens. The reply lands in a moment; application context can
    /// lag by minutes, and has nothing at all for a freshly installed Watch app.
    func requestSummary() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        requestSummaryIfNeeded(session)
        guard session.isReachable else { return }
        session.sendMessage([Self.needsSummaryKey: true], replyHandler: { [weak self] reply in
            self?.applyContext(reply)
        }, errorHandler: { error in
            watchSyncLogger.info("Summary request failed: \(String(describing: error), privacy: .public)")
        })
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { requestSummary() }
    }

    /// With no summary at all, also queue the request, which reaches the
    /// phone (and wakes the app) even when it is out of range right now.
    private func requestSummaryIfNeeded(_ session: WCSession) {
        guard session.receivedApplicationContext[Self.summaryKey] == nil,
              !session.outstandingUserInfoTransfers.contains(where: { $0.userInfo[Self.needsSummaryKey] != nil })
        else { return }
        session.transferUserInfo([Self.needsSummaryKey: true])
    }
    #endif

    private func applyContext(_ context: [String: Any]) {
        #if os(watchOS)
        if let words = context[Self.diaperWordsKey] as? String {
            AppGroup.defaults.set(words, forKey: AppGroup.Key.diaperWords)
        }
        guard let data = context[Self.summaryKey] as? Data,
              let summary = try? JSONDecoder().decode(NowSummary.self, from: data) else { return }
        Task { @MainActor in WatchStore.shared.receive(summary) }
        #endif
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            watchSyncLogger.error("Session activation failed: \(String(describing: error), privacy: .public)")
            return
        }
        #if os(watchOS)
        applyContext(session.receivedApplicationContext)
        requestSummary()
        Task { @MainActor in WatchStore.shared.retryPending() }
        #else
        Task { @MainActor in self.push(summary: EventStore.shared.summary) }
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        #if os(iOS)
        if userInfo[Self.needsSummaryKey] != nil {
            Task { @MainActor in self.push(summary: EventStore.shared.summary) }
            return
        }
        guard let payload = Self.payload(from: userInfo) else { return }
        Task { @MainActor in
            guard EventStore.shared.apply(payload, forChildID: payload.childID) else { return }
            WCSession.default.transferUserInfo([Self.savedActionKey: payload.id.uuidString])
        }
        #else
        guard let rawID = userInfo[Self.savedActionKey] as? String,
              let id = UUID(uuidString: rawID) else { return }
        Task { @MainActor in WatchStore.shared.markDelivered(id) }
        #endif
    }

    #if os(iOS)
    /// The Watch app was just installed (or the paired Watch changed): send it
    /// the summary now rather than at the next tap.
    func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }
        Task { @MainActor in self.push(summary: EventStore.shared.summary) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
