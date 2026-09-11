import SwiftData
import SwiftUI
import WatchKit

@main
struct BabyWatchApp: App {
    @StateObject private var settings = BabySettings.shared

    init() {
        WatchSyncService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchBabyView() }
                .environmentObject(settings)
                .task {
                    await HealthKitService.shared.synchronizeAuthorization()
                    await BabyLogService.shared.retryPendingLocalEntries()
                    await HealthKitService.shared.refreshCache()
                }
        }
        .modelContainer(DataService.sharedModelContainer)
        .backgroundTask(.appRefresh("baby.refresh")) {
            await HealthKitService.shared.refreshCache()
            await MainActor.run { scheduleRefresh() }
        }
    }

    private func scheduleRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: 30 * 60),
            userInfo: nil
        ) { _ in }
    }
}
