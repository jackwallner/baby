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
        guard session.activationState == .activated, session.isPaired,
              let data = try? JSONEncoder().encode(summary) else { return }
        do {
            try session.updateApplicationContext([Self.summaryKey: data, Self.diaperWordsKey: DiaperWords.current.rawValue])
        } catch {
            watchSyncLogger.error("Summary push failed: \(String(describing: error), privacy: .public)")
        }
    }
    #endif

    #if os(watchOS)
    func send(_ payload: WatchLogPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard !session.outstandingUserInfoTransfers.contains(where: {
            WatchLogPayload(userInfo: $0.userInfo)?.id == payload.id
        }) else { return }
        session.transferUserInfo(payload.dictionary)
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
        guard var payload = WatchLogPayload(userInfo: userInfo) else { return }
        // Accept the temporary top-level envelope used by pre-release builds,
        // while new transfers carry the profile ID in the Codable payload.
        if payload.childID == nil,
           let childID = (userInfo["childID"] as? String).flatMap(UUID.init) {
            payload.childID = childID
        }
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
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
