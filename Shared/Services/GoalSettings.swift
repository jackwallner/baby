import Combine
import SwiftUI
import WidgetKit

enum AppAppearance: Int, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class BabySettings: ObservableObject {
    static let shared = BabySettings()

    @Published var hasCompletedSetup: Bool { didSet { persistAndSync() } }
    @Published var bedtimeMinutes: Int { didSet { persistAndSync() } }
    @Published var halfLifeHours: Double { didSet { persistAndSync() } }
    @Published var bedtimeThreshold: Double { didSet { persistAndSync() } }
    @Published var quickAddDrinks: [DrinkPreset] { didSet { persistAndSync() } }
    @Published var excludedSourceBundleIDs: Set<String> { didSet { persistAndSync() } }
    @Published private(set) var excludedSourceNames: [String: String]
    @Published var appearance: AppAppearance { didSet { persistAndSync() } }
    @Published var reminderEnabled: Bool { didSet { persistAndSync() } }
    /// Opt-in for the extra Apple Health categories the Body tab reads. Kept
    /// separate from the baby permission so someone can log and forecast
    /// without ever handing over sleep or heart data.
    @Published var bodyInsightsEnabled: Bool { didSet { persistAndSync() } }
    @Published var cachedIsPro: Bool

    private let defaults: UserDefaults
    private var isInitializing = true

    private init() {
        defaults = UserDefaults(suiteName: babyAppGroupID) ?? .standard
        hasCompletedSetup = defaults.bool(forKey: babyHasCompletedSetupKey)
        bedtimeMinutes = defaults.object(forKey: babyBedtimeMinutesKey) as? Int ?? 22 * 60 + 30
        halfLifeHours = defaults.object(forKey: babyHalfLifeKey) as? Double ?? 5
        bedtimeThreshold = defaults.object(forKey: babyThresholdKey) as? Double ?? 25
        quickAddDrinks = Self.loadPresets(from: defaults)
        excludedSourceBundleIDs = Set(defaults.stringArray(forKey: babyExcludedSourcesKey) ?? [])
        excludedSourceNames = defaults.dictionary(forKey: babyExcludedSourceNamesKey) as? [String: String] ?? [:]
        appearance = AppAppearance(rawValue: defaults.integer(forKey: "appearance")) ?? .system
        reminderEnabled = defaults.bool(forKey: "reminderEnabled")
        bodyInsightsEnabled = defaults.bool(forKey: babyBodyInsightsKey)
        cachedIsPro = ProAccess.isPro
        isInitializing = false
    }

    /// Presets used to be three bare milligram figures. Anything saved in that
    /// shape is migrated to named drinks on first read so an existing install
    /// keeps its numbers and gains the labels.
    private static func loadPresets(from defaults: UserDefaults) -> [DrinkPreset] {
        if let data = defaults.data(forKey: babyDrinkPresetsKey),
           let decoded = try? JSONDecoder().decode([DrinkPreset].self, from: data),
           decoded.count == 3 {
            return decoded
        }
        if let legacy = defaults.array(forKey: babyPresetsKey) as? [Double], legacy.count == 3 {
            return legacy.map { DrinkCatalog.closestName(to: $0) }
        }
        return DrinkCatalog.defaultPresets
    }

    var quickAddPresets: [Double] { quickAddDrinks.map(\.milligrams) }

    var sourceSelection: BabySourceSelection {
        BabySourceSelection(excludedBundleIDs: excludedSourceBundleIDs)
    }

    var bedtimeDate: Date {
        bedtime(onOrAfter: .now)
    }

    func bedtime(onOrAfter date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let candidate = calendar.date(byAdding: .minute, value: bedtimeMinutes, to: start) ?? date
        if candidate > date { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
    }

    func setSourceIncluded(_ included: Bool, bundleID: String, name: String) {
        if included {
            excludedSourceBundleIDs.remove(bundleID)
            excludedSourceNames.removeValue(forKey: bundleID)
        } else {
            excludedSourceBundleIDs.insert(bundleID)
            excludedSourceNames[bundleID] = name
        }
        defaults.set(excludedSourceNames, forKey: babyExcludedSourceNamesKey)
    }

    func apply(_ payload: WatchSettingsPayload) {
        if let value = payload.bedtimeMinutes { bedtimeMinutes = value }
        if let value = payload.halfLifeHours { halfLifeHours = value }
        if let value = payload.bedtimeThreshold { bedtimeThreshold = value }
        if let value = payload.quickAddDrinks, value.count == 3 {
            quickAddDrinks = value
        } else if let value = payload.quickAddPresets, value.count == 3 {
            quickAddDrinks = value.map { DrinkCatalog.closestName(to: $0) }
        }
        if let value = payload.excludedSourceBundleIDs { excludedSourceBundleIDs = Set(value) }
        if let value = payload.excludedSourceNames {
            excludedSourceNames = value
            defaults.set(value, forKey: babyExcludedSourceNamesKey)
        }
        if let value = payload.isPro {
            defaults.set(value, forKey: babyCachedProKey)
            cachedIsPro = value
        }
        if payload.hasCompletedSetup == true { hasCompletedSetup = true }
        WidgetCenter.shared.reloadAllTimelines()
    }

    var watchPayload: WatchSettingsPayload {
        WatchSettingsPayload(
            bedtimeMinutes: bedtimeMinutes,
            halfLifeHours: halfLifeHours,
            bedtimeThreshold: bedtimeThreshold,
            quickAddPresets: quickAddPresets,
            quickAddDrinks: quickAddDrinks,
            isPro: ProAccess.isPro,
            hasCompletedSetup: hasCompletedSetup,
            excludedSourceBundleIDs: Array(excludedSourceBundleIDs),
            excludedSourceNames: excludedSourceNames
        )
    }

    private func persistAndSync() {
        guard !isInitializing else { return }
        defaults.set(hasCompletedSetup, forKey: babyHasCompletedSetupKey)
        defaults.set(bedtimeMinutes, forKey: babyBedtimeMinutesKey)
        defaults.set(halfLifeHours, forKey: babyHalfLifeKey)
        defaults.set(bedtimeThreshold, forKey: babyThresholdKey)
        defaults.set(quickAddPresets, forKey: babyPresetsKey)
        if let encoded = try? JSONEncoder().encode(quickAddDrinks) {
            defaults.set(encoded, forKey: babyDrinkPresetsKey)
        }
        defaults.set(Array(excludedSourceBundleIDs), forKey: babyExcludedSourcesKey)
        defaults.set(appearance.rawValue, forKey: "appearance")
        defaults.set(reminderEnabled, forKey: "reminderEnabled")
        defaults.set(bodyInsightsEnabled, forKey: babyBodyInsightsKey)
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        WatchSyncService.shared.push(settings: watchPayload)
        #endif
    }
}
