import CloudKit
import SwiftUI
import UIKit

@main
struct BabyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = BabySettings.shared
    @StateObject private var store = StoreService.shared
    @StateObject private var events = EventStore.shared
    @StateObject private var sharing = SharingService.shared

    init() {
        WatchSyncService.shared.start()
        ConversionDiagnostics.recordAppOpen()
        #if DEBUG
        if RevenueCatProbe.isEnabled {
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
                .environmentObject(events)
                .environmentObject(sharing)
                .preferredColorScheme(settings.appearance.colorScheme)
                .task {
                    store.start()
                    #if DEBUG
                    if ScreenshotConfig.isEnabled {
                        settings.hasCompletedSetup = true
                        ScreenshotFixtures.seed(into: events)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema") {
                        // Run once from Xcode on a device signed in to iCloud,
                        // then deploy the schema to Production in the CloudKit
                        // Console. TestFlight and App Store builds use Production.
                        try? events.persistence.container.initializeCloudKitSchema(options: [])
                    }
                    #endif
                    await sharing.refresh(for: events.child)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    events.reload()
                    Task { await sharing.refresh(for: events.child) }
                }
                .onChange(of: events.child) { _, child in
                    Task { await sharing.refresh(for: child) }
                }
        }
    }
}

/// Routes the CloudKit share acceptance to a scene delegate, which is where
/// iOS delivers it for a SwiftUI app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in SharingService.shared.accept(cloudKitShareMetadata) }
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in SharingService.shared.accept(cloudKitShareMetadata) }
    }
}

private struct RootView: View {
    @EnvironmentObject private var settings: BabySettings
    @EnvironmentObject private var events: EventStore

    var body: some View {
        if Self.paywallSnapshot {
            BabyPaywallView(displayCloseButton: false)
        } else if let startTab = Self.startTab {
            BabyTabView(initialTab: startTab)
        } else if !settings.hasCompletedSetup && !ScreenshotConfig.isEnabled {
            BabyOnboardingView()
        } else if events.child == nil && !ScreenshotConfig.isEnabled {
            // Setup finished but the baby is gone (a stopped share, a restore
            // from a backup): ask for the baby again rather than logging into
            // nothing.
            BabyOnboardingView(startAtBabyStep: true)
        } else {
            BabyTabView(initialTab: Self.screenshotTab ?? 0)
        }
    }

    static var startTab: Int? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-StartTab"), index + 1 < arguments.count else { return nil }
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
        guard let index = arguments.firstIndex(of: "-ScreenshotTab"), index + 1 < arguments.count else { return nil }
        return Int(arguments[index + 1])
        #else
        return nil
        #endif
    }
}

/// Four tabs. The first-weeks tally and the pediatrician summary are tabs
/// rather than cards so the two things this app does that the category does
/// not are in every screenshot and one tap from a reviewer on a fresh install,
/// with no purchase and no days of data (4.3).
struct BabyTabView: View {
    @State private var selection: Int

    init(initialTab: Int = 0) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { NowView() }
                .tabItem { Label("Now", systemImage: "clock.fill") }
                .tag(0)
            NavigationStack { FirstWeeksView() }
                .tabItem { Label("First Weeks", systemImage: "checklist") }
                .tag(1)
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "list.bullet") }
                .tag(2)
            NavigationStack { SummaryView() }
                .tabItem { Label("Summary", systemImage: "doc.text") }
                .tag(3)
        }
        .tint(AppTheme.accent)
    }
}
