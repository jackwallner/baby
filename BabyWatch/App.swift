import SwiftUI
import WatchKit

@main
struct BabyWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = WatchStore.shared

    init() {
        WatchSyncService.shared.start()
        WatchStore.shared.sender = { WatchSyncService.shared.send($0) }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchNowView() }
                .environmentObject(store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.retryPending() }
                }
        }
    }
}
