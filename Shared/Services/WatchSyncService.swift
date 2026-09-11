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
            try session.updateApplicationContext([Self.summaryKey: data])
        } catch {
            watchSyncLogger.error("Summary push failed: \(String(describing: error), privacy: .public)")
        }
    }
    #endif

    #if os(watchOS)
    func send(_ payload: WatchLogPayload) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(payload.dictionary)
    }
    #endif

    private func applyContext(_ context: [String: Any]) {
        #if os(watchOS)
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
        #else
        Task { @MainActor in self.push(summary: EventStore.shared.summary) }
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        #if os(iOS)
        guard let payload = WatchLogPayload(userInfo: userInfo) else { return }
        Task { @MainActor in EventStore.shared.apply(payload) }
        #endif
    }

    #if os(watchOS)
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error == nil, let payload = WatchLogPayload(userInfo: userInfoTransfer.userInfo) else { return }
        Task { @MainActor in WatchStore.shared.markDelivered(payload.id) }
    }
    #endif

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
