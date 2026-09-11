import Foundation
import os
import WatchConnectivity

private let watchSyncLogger = Logger(subsystem: "com.jackwallner.caffeine", category: "WatchSync")

struct WatchSettingsPayload: Sendable, Equatable {
    var bedtimeMinutes: Int?
    var halfLifeHours: Double?
    var bedtimeThreshold: Double?
    var quickAddPresets: [Double]?
    var quickAddDrinks: [DrinkPreset]?
    var isPro: Bool?
    var hasCompletedSetup: Bool?
    var excludedSourceBundleIDs: [String]?
    var excludedSourceNames: [String: String]?

    init(
        bedtimeMinutes: Int? = nil,
        halfLifeHours: Double? = nil,
        bedtimeThreshold: Double? = nil,
        quickAddPresets: [Double]? = nil,
        quickAddDrinks: [DrinkPreset]? = nil,
        isPro: Bool? = nil,
        hasCompletedSetup: Bool? = nil,
        excludedSourceBundleIDs: [String]? = nil,
        excludedSourceNames: [String: String]? = nil
    ) {
        self.bedtimeMinutes = bedtimeMinutes
        self.halfLifeHours = halfLifeHours
        self.bedtimeThreshold = bedtimeThreshold
        self.quickAddPresets = quickAddPresets
        self.quickAddDrinks = quickAddDrinks
        self.isPro = isPro
        self.hasCompletedSetup = hasCompletedSetup
        self.excludedSourceBundleIDs = excludedSourceBundleIDs
        self.excludedSourceNames = excludedSourceNames
    }

    init?(context: [String: Any]) {
        bedtimeMinutes = context[caffeineBedtimeMinutesKey] as? Int
        halfLifeHours = context[caffeineHalfLifeKey] as? Double
        bedtimeThreshold = context[caffeineThresholdKey] as? Double
        quickAddPresets = context[caffeinePresetsKey] as? [Double]
        if let data = context[caffeineDrinkPresetsKey] as? Data {
            quickAddDrinks = try? JSONDecoder().decode([DrinkPreset].self, from: data)
        } else {
            quickAddDrinks = nil
        }
        isPro = context[caffeineCachedProKey] as? Bool
        hasCompletedSetup = context[caffeineHasCompletedSetupKey] as? Bool
        excludedSourceBundleIDs = context[caffeineExcludedSourcesKey] as? [String]
        excludedSourceNames = context[caffeineExcludedSourceNamesKey] as? [String: String]
        guard bedtimeMinutes != nil || halfLifeHours != nil || quickAddPresets != nil || isPro != nil else {
            return nil
        }
    }

    var dictionary: [String: Any] {
        var value: [String: Any] = [:]
        if let bedtimeMinutes { value[caffeineBedtimeMinutesKey] = bedtimeMinutes }
        if let halfLifeHours { value[caffeineHalfLifeKey] = halfLifeHours }
        if let bedtimeThreshold { value[caffeineThresholdKey] = bedtimeThreshold }
        if let quickAddPresets { value[caffeinePresetsKey] = quickAddPresets }
        if let quickAddDrinks, let data = try? JSONEncoder().encode(quickAddDrinks) {
            value[caffeineDrinkPresetsKey] = data
        }
        if let isPro { value[caffeineCachedProKey] = isPro }
        if let hasCompletedSetup { value[caffeineHasCompletedSetupKey] = hasCompletedSetup }
        if let excludedSourceBundleIDs { value[caffeineExcludedSourcesKey] = excludedSourceBundleIDs }
        if let excludedSourceNames { value[caffeineExcludedSourceNamesKey] = excludedSourceNames }
        return value
    }
}

final class WatchSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSyncService()

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    #if os(iOS)
    func push(settings: WatchSettingsPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }
        do {
            try session.updateApplicationContext(settings.dictionary)
        } catch {
            watchSyncLogger.error("Settings sync failed: \(String(describing: error), privacy: .public)")
        }
    }
    #endif

    private func apply(_ context: [String: Any]) {
        guard let payload = WatchSettingsPayload(context: context) else { return }
        Task { @MainActor in CaffeineSettings.shared.apply(payload) }
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
        apply(session.receivedApplicationContext)
        #else
        Task { @MainActor in self.push(settings: CaffeineSettings.shared.watchPayload) }
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
