import SwiftData
import SwiftUI
import WatchKit

@main
struct CaffeineWatchApp: App {
    @StateObject private var settings = CaffeineSettings.shared

    init() {
        WatchSyncService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchCaffeineView() }
                .environmentObject(settings)
                .task {
                    await HealthKitService.shared.synchronizeAuthorization()
                    await CaffeineLogService.shared.retryPendingLocalEntries()
                    await HealthKitService.shared.refreshCache()
                }
        }
        .modelContainer(DataService.sharedModelContainer)
        .backgroundTask(.appRefresh("caffeine.refresh")) {
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
