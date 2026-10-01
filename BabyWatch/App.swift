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
            root
                .environmentObject(store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.retryPending() }
                }
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ComplicationGallery") {
            ComplicationGallery()
        } else {
            WatchRootView()
        }
        #else
        WatchRootView()
        #endif
    }
}

/// Two pages on the crown: Now, then Today. A complication's link logs and
/// lands on Now, with the confirmation and Undo over the top.
struct WatchRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: WatchStore
    @State private var page = WatchRootView.startPage

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                WatchNowView().tag(0)
                WatchTodayView().tag(1)
            }
            .tabViewStyle(.verticalPage)
            .overlay(alignment: .top) {
                if let confirmation = store.confirmation {
                    WatchConfirmationBanner(confirmation: confirmation)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .id(confirmation.id)
                }
            }
        }
        .animation(reduceMotion ? nil : AppTheme.feedbackAnimation, value: store.confirmation)
        .onChange(of: store.confirmation) { _, confirmation in
            guard let confirmation else { return }
            WKInterfaceDevice.current().play(confirmation.canUndo ? .success : .directionDown)
        }
        .onOpenURL { url in
            page = 0
            store.handle(url)
        }
    }

    private static var startPage: Int {
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-WatchPage"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
            return Int(ProcessInfo.processInfo.arguments[index + 1]) ?? 0
        }
        #endif
        return 0
    }
}
