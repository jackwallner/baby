import SwiftUI
import WatchKit

@main
struct BabyWatchApp: App {
    @StateObject private var store = WatchStore.shared

    init() {
        WatchSyncService.shared.start()
        WatchStore.shared.sender = { WatchSyncService.shared.send($0) }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchNowView() }
                .environmentObject(store)
        }
    }
}
