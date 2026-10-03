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
        // Bar titles are UIKit; give them the theme ink so Night light has no
        // stray pure-white title.
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: AppTheme.inkUIColor]
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: AppTheme.inkUIColor]
        UINavigationBar.appearance().tintColor = AppTheme.accentUIColor
        if let chevron = UIImage(systemName: "chevron.backward")?.withTintColor(AppTheme.accentUIColor, renderingMode: .alwaysOriginal) {
            UINavigationBar.appearance().backIndicatorImage = chevron
            UINavigationBar.appearance().backIndicatorTransitionMaskImage = chevron
        }
        // UIKit controls default to cool greys and pure white, which break
        // Night light's warm palette. Every colour here is dynamic.
        UISwitch.appearance().onTintColor = AppTheme.accentUIColor
        UISwitch.appearance().thumbTintColor = AppTheme.thumbUIColor
        let segments = UISegmentedControl.appearance()
        segments.backgroundColor = AppTheme.cardUIColor
        segments.selectedSegmentTintColor = AppTheme.actionFillUIColor
        segments.setTitleTextAttributes([.foregroundColor: AppTheme.inkUIColor], for: .normal)
        segments.setTitleTextAttributes([.foregroundColor: AppTheme.buttonInkUIColor], for: .selected)
        UIBarButtonItem.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).tintColor = AppTheme.accentUIColor

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
                .environment(\.nightLight, settings.appearance.isNightLight)
                .onAppear { NightLight.apply(settings.appearance.isNightLight) }
                .onChange(of: settings.appearance) { _, appearance in NightLight.apply(appearance.isNightLight) }
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
                    NightLight.apply(settings.appearance.isNightLight)
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

/// Sheets are presented from the window, not from the SwiftUI view that set
/// the environment, so the trait is also set on every window. Presented
/// controllers inherit it and SwiftUI reads it back through the bridge.
@MainActor
enum NightLight {
    static func apply(_ isOn: Bool) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.tintColor = AppTheme.accentUIColor
                let isSet = window.traitOverrides.contains(NightLightTrait.self)
                if isOn, !isSet {
                    window.traitOverrides[NightLightTrait.self] = true
                } else if !isOn, isSet {
                    window.traitOverrides.remove(NightLightTrait.self)
                }
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
    @EnvironmentObject private var sharing: SharingService

    var body: some View {
        Group {
            if Self.paywallSnapshot {
                BabyPaywallView(displayCloseButton: false)
            } else if let startTab = Self.startTab {
                BabyHomeView(initialScreen: startTab)
            } else if isJoiningFirstLog {
                JoiningSharedLogView()
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
        .alert(
            "Bring your entries into the shared log?",
            isPresented: Binding(
                get: { separateLogCount > 0 },
                set: { if !$0 { events.arrivedSharedChild = nil } }
            )
        ) {
            Button("Move \(Format.count(separateLogCount, "entry", "entries"))") {
                if let shared = events.arrivedSharedChild {
                    for separate in events.separateLogs(besides: shared) {
                        events.moveEvents(from: separate, into: shared)
                    }
                }
                events.arrivedSharedChild = nil
            }
            Button("Keep them separate", role: .cancel) { events.arrivedSharedChild = nil }
        } message: {
            Text("You logged on this phone before joining \(events.arrivedSharedChild?.displayName ?? "the shared")'s log. Moving them lets everyone see them, and removes your separate copy.")
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

    /// Someone opened an invite before setting anything up: wait for that
    /// baby instead of offering onboarding, which would make a duplicate.
    private var isJoiningFirstLog: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PreviewJoining") { return true }
        #endif
        guard !hasSharedChild, sharing.isAcceptingInvitation || events.isAwaitingSharedBaby else { return false }
        return !settings.hasCompletedSetup || events.child == nil
    }

    private var separateLogCount: Int {
        guard let shared = events.arrivedSharedChild else { return 0 }
        return events.separateLogs(besides: shared).reduce(0) { $0 + $1.eventCount }
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

/// Keep each visited screen alive, with one compact capsule for navigation.
struct BabyHomeView: View {
    @EnvironmentObject private var store: StoreService
    @State private var selected: HomeTab
    @State private var visited: Set<HomeTab>
    @State private var settingsPath: [SettingsDestination]
    private let showsReportSnapshot: Bool

    init(initialScreen: Int = 0) {
        // Capture routes predate the tabs: 1 is First Weeks, 2 History, 3 Reports.
        let tab: HomeTab = switch initialScreen {
        case 1: .settings
        case 2: .history
        case 3: .reports
        default: .log
        }
        _selected = State(initialValue: tab)
        _visited = State(initialValue: [tab])
        _settingsPath = State(initialValue: initialScreen == 1 ? [.firstWeeks] : [])
        showsReportSnapshot = initialScreen == 3
    }

    var body: some View {
        TabView(selection: $selected) {
            ForEach(HomeTab.allCases) { tab in
                Group {
                    if visited.contains(tab) { screen(tab) }
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(tab)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .clipped()
        .background(AppTheme.paper)
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            navigationCapsule
                .padding(.top, AppTheme.hairSpacing)
                .padding(.bottom, AppTheme.hairSpacing)
                .padding(.horizontal, AppTheme.margin)
        }
        .undoToast()
        .tint(AppTheme.accent)
    }

    @ViewBuilder
    private func screen(_ tab: HomeTab) -> some View {
        switch tab {
        case .log:
            NavigationStack { NowView(isVisible: selected == .log) }
        case .history:
            NavigationStack { HistoryView() }
        case .reports:
            ReportsTabView(isVisible: selected == .reports, showsSnapshot: showsReportSnapshot)
        case .settings:
            NavigationStack(path: $settingsPath) {
                SettingsView()
                    .navigationDestination(for: SettingsDestination.self) { _ in FirstWeeksView() }
            }
        }
    }

    private var navigationCapsule: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases) { tab in
                HomeTabButton(
                    icon: tab.icon(isPro: store.isPro),
                    label: tab.label(isPro: store.isPro),
                    identifier: "tab.\(tab.rawValue)",
                    isSelected: selected == tab
                ) {
                    guard selected != tab else { return }
                    Haptics.selected()
                    visited.insert(tab)
                    selected = tab
                }
            }
        }
        .padding(AppTheme.hairSpacing)
        .background { NavigationCapsuleBackground() }
        .overlay(Capsule().strokeBorder(AppTheme.separator, lineWidth: AppTheme.hairlineWidth))
    }

    private enum SettingsDestination: Hashable {
        case firstWeeks
    }
}

private enum HomeTab: String, CaseIterable, Identifiable {
    case log, history, reports, settings

    var id: Self { self }

    func label(isPro: Bool) -> String {
        switch self {
        case .log: "Log"
        case .history: "History"
        case .reports: isPro ? "Reports" : "Upgrade"
        case .settings: "Settings"
        }
    }

    func icon(isPro: Bool) -> String {
        switch self {
        case .log: "heart"
        case .history: "clock.arrow.circlepath"
        case .reports: isPro ? "chart.bar.doc.horizontal" : "lock"
        case .settings: "gearshape"
        }
    }
}

private struct NavigationCapsuleBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.nightLight) private var nightLight

    var body: some View {
        if reduceTransparency || nightLight {
            Capsule().fill(AppTheme.card)
        } else {
            Capsule().fill(.regularMaterial)
        }
    }
}

private struct HomeTabButton: View {
    let icon: String
    let label: String
    let identifier: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.hairSpacing) {
                Image(systemName: icon)
                    .font(.system(size: AppTheme.tabIconSize, weight: .medium))
                Text(label)
                    .font(.system(size: AppTheme.tabLabelSize, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.ink2)
            .frame(width: AppTheme.tabWidth, height: AppTheme.tabHeight)
            .background(isSelected ? AppTheme.accent.opacity(0.12) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(HomeTabButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct HomeTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
