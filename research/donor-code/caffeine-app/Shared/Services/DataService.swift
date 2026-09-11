import Foundation
import os
import SwiftData

let caffeineAppGroupID = "group.com.jackwallner.caffeine"
let caffeineCachedProKey = "isPro"
let caffeinePresetsKey = "quickAddPresets"
let caffeineDrinkPresetsKey = "quickAddDrinks"
let caffeineBodyInsightsKey = "bodyInsightsEnabled"
let caffeineExcludedSourcesKey = "excludedSourceBundleIDs"
let caffeineExcludedSourceNamesKey = "excludedSourceNames"
let caffeineHasCompletedSetupKey = "hasCompletedSetup"
let caffeineBedtimeMinutesKey = "bedtimeMinutes"
let caffeineHalfLifeKey = "halfLifeHours"
let caffeineThresholdKey = "bedtimeThreshold"
let caffeineOwnSourceBundleID = "com.jackwallner.caffeine"
let caffeineOwnSourceBundleIDs: Set<String> = [
    "com.jackwallner.caffeine",
    "com.jackwallner.caffeine.watch",
]

@MainActor
enum DataService {
    static let appGroupID = caffeineAppGroupID

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CachedCaffeineDose.self,
            DailyCaffeineRecord.self,
            LocalCaffeineEntry.self,
        ])
        let storeURL = containerURL.appendingPathComponent("Caffeine.store")
        let configuration = ModelConfiguration(
            "Caffeine",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Logger(subsystem: "com.jackwallner.caffeine", category: "Data")
                .error("Persistent store failed: \(String(describing: error), privacy: .public)")
            let fallback = ModelConfiguration(
                "CaffeineFallback",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Unable to initialize Caffeine data store: \(error)")
            }
        }
    }()

    private static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}

enum ProAccess {
    static var isPro: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DemoPro") { return true }
        #endif
        return (UserDefaults(suiteName: caffeineAppGroupID) ?? .standard)
            .bool(forKey: caffeineCachedProKey)
    }
}
