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

        #if DEBUG
        if RevenueCatProbe.isEnabled && RevenueCatProbe.wantsPurchase {
            // A probe launch must not inherit a prior run's local conversion
            // record. The restore launch deliberately leaves this record in
            // place so it can prove that restore did not create a conversion.
            ConversionDiagnostics.reset()
        }
        #endif
        ConversionDiagnostics.recordAppOpen()
        #if DEBUG
        if RevenueCatProbe.isEnabled {
            StoreService.shared.start()
            StoreService.shared.trackPaywallImpression(id: RevenueCatProbe.impressionID)
            if RevenueCatProbe.wantsPurchase {
                Task { await StoreService.shared.runProbePurchase() }
            } else if RevenueCatProbe.wantsRestore {
                Task { await StoreService.shared.runProbeRestore() }
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
                .alert("Couldn't join this baby's log", isPresented: Binding(
                    get: { sharing.invitationError != nil },
                    set: { if !$0 { sharing.invitationError = nil } }
                )) {
                    Button("OK", role: .cancel) { sharing.invitationError = nil }
                } message: {
                    Text(sharing.invitationError ?? "")
                }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema") {
                        // This setup-only launch must not create purchase SDK
                        // customers or silently swallow a failed cloud setup.
                        do {
                            guard try await sharing.ckContainer.accountStatus() == .available else {
                                print("BABY_SCHEMA_INITIALIZATION_FAILED: Sign in to iCloud on this device.")
                                return
                            }
                            try events.persistence.container.initializeCloudKitSchema(options: [.printSchema])
                            print("BABY_SCHEMA_INITIALIZATION_SUCCEEDED")
                        } catch {
                            print("BABY_SCHEMA_INITIALIZATION_FAILED: \(error)")
                        }
                        return
                    }
                    #endif
                    store.start()
                    #if DEBUG
                    if ScreenshotConfig.isEnabled {
                        settings.hasCompletedSetup = true
                        ScreenshotFixtures.seed(into: events)
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
                    if let child, events.persistence.isShared(child) {
                        settings.hasCompletedSetup = true
                    }
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
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        Task { @MainActor in SharingService.shared.accept(metadata) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in SharingService.shared.accept(cloudKitShareMetadata) }
    }
}

private struct RootView: View {
    @EnvironmentObject private var settings: BabySettings
    @EnvironmentObject private var events: EventStore

    var body: some View {
        Group {
            if Self.paywallSnapshot {
                BabyPaywallView(displayCloseButton: false)
            } else if let startTab = Self.startTab {
                BabyHomeView(initialScreen: startTab)
            } else if !settings.hasCompletedSetup && !hasSharedChild && !ScreenshotConfig.isEnabled {
                BabyOnboardingView()
            } else if events.child == nil && !ScreenshotConfig.isEnabled {
                // Setup finished but the baby is gone (a stopped share, a restore
                // from a backup): ask for the baby again rather than logging into
                // nothing.
                BabyOnboardingView()
            } else {
                BabyHomeView(initialScreen: Self.screenshotTab ?? 0)
            }
        }
        #if DEBUG
        .overlay(alignment: .top) {
            if RevenueCatProbe.isEnabled {
                RevenueCatProbeStatusView()
            }
        }
        #endif
    }

    private var hasSharedChild: Bool {
        events.child.map { events.persistence.isShared($0) } ?? false
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

#if DEBUG
private struct RevenueCatProbeStatusView: View {
    @EnvironmentObject private var store: StoreService

    var body: some View {
        Text(store.probeStatus.accessibleDescription)
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("rcProbe.status")
            .accessibilityLabel(store.probeStatus.accessibleDescription)
            .allowsHitTesting(false)
    }
}
#endif

/// One home screen. The alternate entry points are for existing capture flows.
struct BabyHomeView: View {
    var initialScreen = 0

    var body: some View {
        NavigationStack {
            switch initialScreen {
            case 1: FirstWeeksView()
            case 2: HistoryView()
            case 3: SummaryView()
            default: NowView()
            }
        }
        .tint(AppTheme.accent)
    }
}
