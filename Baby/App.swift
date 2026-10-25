import CloudKit
import SwiftUI
import UIKit
import UserNotifications

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
                    if ProcessInfo.processInfo.arguments.contains("-SimRelay") {
                        settings.hasCompletedSetup = true
                        SimPartnerRelay.startIfAsked(events: events)
                    }
                    #endif
                    await sharing.refresh(for: events.child)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    NightLight.apply(settings.appearance.isNightLight)
                    Reminders.forgetLastSchedule()
                    events.reload()
                    // A sleep started from the Watch or a partner while this
                    // app was in the background could not start its Live
                    // Activity then (iOS refuses), and an unchanged summary
                    // does not publish again.
                    LiveActivityService.shared.sync(summary: events.summary)
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
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set before launch finishes, so a tap that cold-starts the app is routed.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        return true
    }

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
    @StateObject private var onboardingJoin = JoinLogModel()
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
                BabyOnboardingView(joinModel: onboardingJoin)
            } else if events.child == nil && !ScreenshotConfig.isEnabled {
                // Setup finished but the baby is gone (a stopped share, a restore
                // from a backup): ask for the baby again rather than logging into
                // nothing.
                BabyOnboardingView(joinModel: onboardingJoin)
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
                if let shared = events.arrivedSharedChild, let separateLog {
                    events.moveEvents(from: separateLog, into: shared)
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

    /// The one log started on this phone before joining. With more than one
    /// (twins, say) none is offered: merging would fold a second baby into
    /// the shared one.
    private var separateLog: Child? {
        guard let shared = events.arrivedSharedChild else { return nil }
        let logs = events.separateLogs(besides: shared)
        return logs.count == 1 ? logs[0] : nil
    }

    private var separateLogCount: Int { separateLog?.eventCount ?? 0 }

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
/// Unfolded on iPhone Duo, History takes its own pane beside the open tab.
struct BabyHomeView: View {
    @EnvironmentObject private var store: StoreService
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selected: HomeTab
    @State private var visited: Set<HomeTab>
    @State private var settingsPath: [SettingsDestination]
    /// The container's width and fold, measured so the unfolded iPhone Duo
    /// can put the open tab and History on opposite sides of the fold.
    @State private var paneGeometry = PaneGeometry(width: 0, fold: nil)
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

    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(
            width: paneGeometry.width,
            isRegularWidth: horizontalSizeClass == .regular,
            fold: paneGeometry.fold
        )
    }

    /// Unfolded, History has its own pane, so it is never a tab.
    private var tabs: [HomeTab] {
        split == nil ? HomeTab.allCases : HomeTab.allCases.filter { $0 != .history }
    }

    private func isShown(_ tab: HomeTab) -> Bool {
        selected == tab || (tab == .history && split != nil)
    }

    var body: some View {
        // One tree for both poses: folding only moves frames, so every
        // screen keeps its scroll position, path and History layout.
        ZStack(alignment: .topLeading) {
            ForEach(HomeTab.allCases) { tab in
                if visited.contains(tab) || isShown(tab) { pane(tab) }
            }
        }
        // Clip only the top, so scrolling stays below the status bar.
        .clipShape(TopEdgeClip())
        .background { AppTheme.paper.ignoresSafeArea() }
        // Unfolded, the capsule heads the open tab's pane, so both panes
        // run to the display's bottom edge alike. Docked at the bottom
        // there, the open tab ended above it on a cut card while History
        // ran on beside it (review 2026-10-24).
        .overlay(alignment: split == nil ? .bottomLeading : .topLeading) {
            navigationCapsule
                .padding(.top, AppTheme.hairSpacing)
                .padding(.bottom, AppTheme.hairSpacing)
                .padding(.horizontal, AppTheme.margin)
                .frame(height: AppTheme.bottomNavigationReservedHeight)
                .frame(maxWidth: split?.primaryWidth ?? .infinity)
        }
        .overlay(alignment: .topLeading) {
            // The toast belongs to the pane that logs, never across the fold.
            Color.clear
                .allowsHitTesting(false)
                .frame(maxWidth: split?.primaryWidth ?? .infinity)
                .undoToast(clearsBarButtons: selected != .log)
                .padding(.top, split == nil ? 0 : AppTheme.bottomNavigationReservedHeight)
        }
        .tint(AppTheme.accent)
        .onGeometryChange(for: PaneGeometry.self) { proxy in
            PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
        } action: { paneGeometry = $0 }
        .onChange(of: split != nil) { _, isSplit in
            guard isSplit else { return }
            visited.insert(.history)
            if selected == .history { selected = .log }
        }
        .onReceive(router.$checkupRequests) { count in
            guard count > 0 else { return }
            visited.insert(.reports)
            selected = .reports
        }
        .onChange(of: selected) { _, tab in
            if tab != .reports { router.showsCheckupPitch = false }
        }
        #if DEBUG
        .task { await runDuoTour() }
        #endif
    }

    /// Unfolded, History is already beside every tab, so it opens Log.
    private func show(_ requested: HomeTab) {
        let tab: HomeTab = requested == .history && split != nil ? .log : requested
        visited.insert(tab)
        selected = tab
    }

    /// Every screen is a phone layout, and each unfolded pane is phone-width.
    /// The size class stays compact before the split is measured too: a pane
    /// that launched regular could keep it, and Log then drew iPad-style, its
    /// title leading and its page 84 pt short of the fold.
    private func pane(_ tab: HomeTab) -> some View {
        let isHistoryPane = tab == .history && split != nil
        let headsCapsule = split != nil && !isHistoryPane
        return screen(tab)
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.reservesBottomCapsule, split == nil)
            .padding(.top, headsCapsule ? AppTheme.bottomNavigationReservedHeight : 0)
            .frame(
                maxWidth: (isHistoryPane ? split?.secondaryWidth : split?.primaryWidth) ?? .infinity,
                maxHeight: .infinity
            )
            .padding(.leading, isHistoryPane ? split?.secondaryX ?? 0 : 0)
            .opacity(isShown(tab) ? 1 : 0)
            .allowsHitTesting(isShown(tab))
            .accessibilityHidden(!isShown(tab))
    }

    @ViewBuilder
    private func screen(_ tab: HomeTab) -> some View {
        switch tab {
        case .log:
            NavigationStack { NowView(isVisible: selected == .log).reservesNavigationCapsule() }
        case .history:
            // Its own pane has no capsule under it.
            NavigationStack { HistoryView().reservesNavigationCapsule(split == nil) }
        case .reports:
            ReportsTabView(isVisible: selected == .reports, showsSnapshot: showsReportSnapshot, fromCheckup: router.showsCheckupPitch)
        case .settings:
            NavigationStack(path: $settingsPath) {
                SettingsView()
                    .reservesNavigationCapsule()
                    .navigationDestination(for: SettingsDestination.self) { _ in
                        FirstWeeksView().reservesNavigationCapsule()
                    }
            }
        }
    }

    private var navigationCapsule: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
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

#if DEBUG
/// `-DuoStop <stop>` opens one iPhone Duo capture: gh-sim screenshots the
/// launch on the folded and the unfolded display (a custom-scheme link from
/// simctl only raises iOS's "Open in" prompt, so each surface is its own
/// launch). Each page shows from its top; the docked pane fades into the
/// capsule rather than cutting a card. A wet diaper is logged 10 s in, so each recording shows one real tap reach both panes, and the
/// toast is gone well before gh-sim's 25 s screenshot.
@MainActor
enum DuoTour {
    enum Stop: String {
        case log, history, reports, firstWeeks = "firstweeks", settings, night
    }

    static func stop(in arguments: [String]) -> Stop? {
        guard let index = arguments.firstIndex(of: "-DuoStop"), index + 1 < arguments.count else { return nil }
        return Stop(rawValue: arguments[index + 1])
    }

    static let wetDelay: Duration = .seconds(10)
    static var hasRun = false
}

extension BabyHomeView {
    fileprivate func runDuoTour() async {
        guard !DuoTour.hasRun, let stop = DuoTour.stop(in: ProcessInfo.processInfo.arguments) else { return }
        DuoTour.hasRun = true
        let appearance: AppAppearance = stop == .night ? .night : .system
        if BabySettings.shared.appearance != appearance { BabySettings.shared.appearance = appearance }
        let layout: HistoryView.HistoryLayout = stop == .firstWeeks ? .calendar : .list
        if UserDefaults.standard.string(forKey: "historyLayout") != layout.rawValue {
            UserDefaults.standard.set(layout.rawValue, forKey: "historyLayout")
        }
        let tab: HomeTab = switch stop {
        case .log, .night: .log
        case .history: .history
        case .reports: .reports
        case .firstWeeks, .settings: .settings
        }
        show(tab)
        if stop == .firstWeeks { settingsPath = [.firstWeeks] }
        try? await Task.sleep(for: DuoTour.wetDelay)
        withAnimation(AppTheme.feedbackAnimation) { _ = EventStore.shared.log(.wet) }
    }
}
#endif

extension View {
    /// Reserve the floating capsule in this screen's safe area, inside its
    /// NavigationStack, so lists end above it yet scroll on beneath it.
    /// Unfolded, the capsule heads the pane instead and nothing is reserved.
    func reservesNavigationCapsule(_ isReserved: Bool = true) -> some View {
        modifier(NavigationCapsuleReservation(isReserved: isReserved))
    }
}

extension EnvironmentValues {
    /// False while the capsule heads the unfolded pane rather than its foot.
    @Entry var reservesBottomCapsule = true
}

private struct NavigationCapsuleReservation: ViewModifier {
    @Environment(\.reservesBottomCapsule) private var atBottom
    let isReserved: Bool

    func body(content: Content) -> some View {
        content.safeAreaPadding(.bottom, isReserved && atBottom ? AppTheme.bottomNavigationReservedHeight : 0)
    }
}

/// Clips the top edge only; the bottom stays open below the frame.
private struct TopEdgeClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 2))
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
