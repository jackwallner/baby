import Foundation
import os
import SwiftData

let babyAppGroupID = "group.com.jackwallner.baby"
let babyCachedProKey = "isPro"
let babyPresetsKey = "quickAddPresets"
let babyDrinkPresetsKey = "quickAddDrinks"
let babyBodyInsightsKey = "bodyInsightsEnabled"
let babyExcludedSourcesKey = "excludedSourceBundleIDs"
let babyExcludedSourceNamesKey = "excludedSourceNames"
let babyHasCompletedSetupKey = "hasCompletedSetup"
let babyBedtimeMinutesKey = "bedtimeMinutes"
let babyHalfLifeKey = "halfLifeHours"
let babyThresholdKey = "bedtimeThreshold"
let babyOwnSourceBundleID = "com.jackwallner.baby"
let babyOwnSourceBundleIDs: Set<String> = [
    "com.jackwallner.baby",
    "com.jackwallner.baby.watch",
]

@MainActor
enum DataService {
    static let appGroupID = babyAppGroupID

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CachedBabyDose.self,
            DailyBabyRecord.self,
            LocalBabyEntry.self,
        ])
        let storeURL = containerURL.appendingPathComponent("Baby.store")
        let configuration = ModelConfiguration(
            "Baby",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Logger(subsystem: "com.jackwallner.baby", category: "Data")
                .error("Persistent store failed: \(String(describing: error), privacy: .public)")
            let fallback = ModelConfiguration(
                "BabyFallback",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Unable to initialize Baby data store: \(error)")
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
        return (UserDefaults(suiteName: babyAppGroupID) ?? .standard)
            .bool(forKey: babyCachedProKey)
    }
}
