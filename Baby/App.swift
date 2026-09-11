import SwiftData
import SwiftUI

@main
struct BabyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = BabySettings.shared
    @StateObject private var store = StoreService.shared

    init() {
        WatchSyncService.shared.start()
        ConversionDiagnostics.recordAppOpen()
        #if DEBUG
        if RevenueCatProbe.isEnabled {
            // The impression hook needs a configured SDK, and configure happens
            // in `start()`, so the probe does that first. After it, this is the
            // same entry point the real paywall screens call.
            StoreService.shared.start()
            StoreService.shared.trackPaywallImpression(id: RevenueCatProbe.impressionID)
            if RevenueCatProbe.wantsPurchase {
                Task { await StoreService.shared.runProbePurchase() }
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .preferredColorScheme(settings.appearance.colorScheme)
                .task {
                    store.start()
                    #if DEBUG
                    if ScreenshotConfig.isEnabled {
                        settings.hasCompletedSetup = true
                        settings.bedtimeMinutes = 22 * 60 + 30
                        settings.halfLifeHours = 5
                        settings.bedtimeThreshold = 25
                        settings.bodyInsightsEnabled = true
                    }
                    #endif
                    await HealthKitService.shared.synchronizeAuthorization()
                    await HealthKitService.shared.refreshCache()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await BabyLogService.shared.retryPendingLocalEntries()
                        await HealthKitService.shared.refreshCache()
                        if settings.bodyInsightsEnabled {
                            await HealthInsightsService.shared.refresh()
                        }
                    }
                }
        }
        .modelContainer(DataService.sharedModelContainer)
    }
}

private struct RootView: View {
    @EnvironmentObject private var settings: BabySettings

    var body: some View {
        if Self.paywallSnapshot {
            BabyPaywallView()
        } else if let startTab = Self.startTab {
            BabyTabView(initialTab: startTab)
        } else if !settings.hasCompletedSetup && !ScreenshotConfig.isEnabled {
            BabyOnboardingView()
        } else {
            BabyTabView(initialTab: Self.screenshotTab ?? 0)
        }
    }

    /// Opens straight onto a tab without entering screenshot mode, so a headless
    /// run can inspect a live surface (the Upgrade tab in particular, which
    /// screenshot mode empties of products) rather than a fixture of one.
    static var startTab: Int? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-StartTab"), index + 1 < arguments.count else {
            return nil
        }
        return Int(arguments[index + 1])
        #else
        return nil
        #endif
    }

    static var paywallSnapshot: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PaywallSnapshot")
        #else
        false
        #endif
    }

    static var screenshotTab: Int? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ScreenshotTab"), index + 1 < arguments.count else {
            return nil
        }
        return Int(arguments[index + 1])
        #else
        return nil
        #endif
    }
}

/// Four tabs. Settings moved to a gear on Now, matching the rest of the fleet,
/// and the old Planner tab folded into the drink preview, which was already
/// doing the same job from the Now screen.
///
/// Upgrade is a tab rather than only a sheet so the purchase surface is always
/// one tap away and a subscriber has a permanent place to manage what they
/// bought. The tab bar stays visible over it, so nothing traps the user on a
/// purchase screen.
struct BabyTabView: View {
    @EnvironmentObject private var store: StoreService
    let initialTab: Int
    @State private var selection: Int

    init(initialTab: Int = 0) {
        self.initialTab = initialTab
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { BabyNowView() }
                .tabItem { Label("Now", systemImage: "waveform.path.ecg") }
                .tag(0)
            NavigationStack { BodyInsightsView() }
                .tabItem { Label("Cutoff", systemImage: "moon.stars.fill") }
                .tag(1)
            NavigationStack { BabyTimelineView() }
                .tabItem { Label("Timeline", systemImage: "clock.arrow.circlepath") }
                .tag(2)
            NavigationStack {
                BabyPaywallView(
                    displayCloseButton: false,
                    paywallImpressionID: "baby_upgrade_tab"
                )
                .navigationTitle(store.isPro ? "Baby+" : "Upgrade")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(
                    store.isPro ? "Baby+" : "Upgrade",
                    systemImage: store.isPro ? "sparkles" : "lock.fill"
                )
            }
            .tag(3)
        }
        .tint(Theme.violet)
    }
}
