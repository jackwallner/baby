import Combine
import Foundation
import os
import StoreKit
import WidgetKit
@preconcurrency import RevenueCat

enum RevenueCatConfig {
    /// Public iOS SDK key. Secret `sk_` keys must never ship in an app binary.
    static let publicSDKKey = "appl_qiLuKnhdneTEYzRYOtaovXNgZRa"
    /// Entitlement lookup key in RevenueCat (display name `Baby+`). `isPro`
    /// gates on any active entitlement, so a mismatch here would go unnoticed
    /// until someone reads this constant.
    static let proEntitlement = "baby"
}

/// Product identifiers, which must match `Baby.storekit` and the App Store
/// Connect subscription group exactly.
enum BabyProduct {
    static let monthly = "com.jackwallner.baby.monthly"
    static let yearly = "com.jackwallner.baby.yearly"
    static let lifetime = "com.jackwallner.baby.pro.lifetime"
}

enum PurchaseState {
    case purchased
    case cancelled
    case pending
}

/// Also the paywall's display order. Yearly leads because it is the plan the
/// CTA defaults to, and a recommended plan buried under two others reads as an
/// afterthought.
enum BabyPackageKind: Int {
    case yearly = 0
    case monthly = 1
    case lifetime = 2
    case other = 3
}

extension BabyPackageKind {
    init(package: Package) {
        switch package.packageType {
        case .lifetime:
            self = .lifetime
        case .annual:
            self = .yearly
        case .monthly:
            self = .monthly
        default:
            let identifiers = [package.identifier, package.storeProduct.productIdentifier].map { $0.lowercased() }
            if identifiers.contains(where: { $0.contains("lifetime") }) {
                self = .lifetime
            } else if identifiers.contains(where: { $0.contains("yearly") || $0.contains("annual") }) {
                self = .yearly
            } else if identifiers.contains(where: { $0.contains("monthly") }) {
                self = .monthly
            } else {
                self = .other
            }
        }
    }
}

extension Package {
    var babyPackageKind: BabyPackageKind {
        BabyPackageKind(package: self)
    }

    var babyDisplayName: String {
        switch babyPackageKind {
        case .lifetime: "Lifetime"
        case .yearly: "Yearly"
        case .monthly: "Monthly"
        case .other: storeProduct.localizedTitle
        }
    }

    var babyPriceLabel: String {
        guard let period = storeProduct.subscriptionPeriod else { return storeProduct.localizedPriceString }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.value == 1 {
            return "\(storeProduct.localizedPriceString) / \(unit)"
        }
        return "\(storeProduct.localizedPriceString) / \(period.value) \(unit)"
    }

    /// Per-week equivalent of the recurring price, shown on the annual card so
    /// the headline yearly figure feels small.
    var babyPricePerWeekLabel: String? {
        guard storeProduct.subscriptionPeriod != nil else { return nil }
        return storeProduct.localizedPricePerWeek
    }

    var babyIntroOfferLabel: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day: return "\(period.value)-day free trial"
        case .week: return "\(period.value * 7)-day free trial"
        case .month: return period.value == 1 ? "1-month free trial" : "\(period.value)-month free trial"
        case .year: return period.value == 1 ? "1-year free trial" : "\(period.value)-year free trial"
        @unknown default: return nil
        }
    }
}

extension Offering {
    var babySortedPackages: [Package] {
        availablePackages.sorted {
            let lhsKind = $0.babyPackageKind
            let rhsKind = $1.babyPackageKind
            if lhsKind.rawValue != rhsKind.rawValue {
                return lhsKind.rawValue < rhsKind.rawValue
            }
            return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
        }
    }
}

@MainActor
final class StoreService: NSObject, ObservableObject, PurchasesDelegate {
    static let shared = StoreService()

    /// App Group key mirroring the live `isPro` entitlement for widget and watch
    /// gating.
    static let cachedProKey = AppGroup.Key.cachedPro

    @Published private(set) var isPro = false {
        didSet {
            guard oldValue != isPro else { return }
            defaults.set(isPro, forKey: Self.cachedProKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    @Published private(set) var packages: [Package] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var errorMessage: String?

    /// Per-product free-trial eligibility, resolved after products load. Trial
    /// copy stays hidden until resolved so a used-trial user is never promised a
    /// free week StoreKit will not grant (Apple 3.1.2).
    @Published private(set) var introEligibility: [String: Bool] = [:]
    @Published private(set) var introEligibilityResolved = false

    #if DEBUG
    /// Observable, non-sensitive state for the Test Store purchase probe.
    /// Keeping this DEBUG-only prevents the probe contract from becoming part
    /// of the release app's UI or purchase surface.
    @Published private(set) var probeStatus = RevenueCatProbeStatus()
    #endif

    private let logger = Logger(subsystem: AppGroup.subsystem, category: "Store")
    private let defaults = UserDefaults(suiteName: AppGroup.id) ?? .standard
    private var isConfigured = false
    /// Dedupes session-scoped paywall impressions.
    private var paywallImpressionsThisSession: Set<String> = []

    private override init() {
        super.init()
        isPro = defaults.bool(forKey: Self.cachedProKey)
    }

    func start(forceRefresh: Bool = false) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DemoPro") {
            isPro = true
            return
        }
        if ScreenshotConfig.isEnabled {
            // `-DemoPro` persists `isPro` into the shared defaults, so a later
            // capture flow without it would otherwise inherit Pro from the
            // previous launch and shoot the subscriber screen instead of the
            // paywall. Each screenshot launch starts from what its own arguments
            // say.
            isPro = false
            #if targetEnvironment(simulator)
            // The paywall review screenshot is taken in exactly this mode, so
            // the plan cards and the billed amount still have to load. Without
            // this the render is the "Couldn't load plans" state, which is the
            // one App Review rejects.
            Task { await loadStoreKitTestingProducts() }
            #endif
            return
        }
        #endif

        #if DEBUG
        if RevenueCatProbe.isEnabled {
            // The probe owns its offering and customer-info calls. Avoid a
            // second background load from App/RootView racing the proof state.
            configureIfNeeded()
            return
        }
        #endif
        configureIfNeeded()
        guard isConfigured else {
            #if targetEnvironment(simulator)
            // StoreKit Testing serves the local .storekit catalog under the
            // Xcode scheme and under `xcodebuild test`, so the real paywall can
            // be rendered and verified without ever configuring RevenueCat on a
            // simulator (which would create fake customers in the prod project).
            Task { await loadStoreKitTestingProducts() }
            #endif
            return
        }
        Task {
            await refreshStatus()
            await loadOffering(forceRefresh: forceRefresh)
        }
    }

    var yearlyPackage: Package? { packages.first { $0.babyPackageKind == .yearly } }
    var lifetimePackage: Package? { packages.first { $0.babyPackageKind == .lifetime } }

    func isEligibleForIntroOffer(_ package: Package) -> Bool {
        guard package.babyIntroOfferLabel != nil else { return false }
        guard introEligibilityResolved else { return false }
        return introEligibility[package.storeProduct.productIdentifier] ?? false
    }

    func eligibleIntroLabel(for package: Package) -> String? {
        guard isEligibleForIntroOffer(package) else { return nil }
        return package.babyIntroOfferLabel
    }

    /// True when the yearly plan can honestly be pitched as a free trial.
    var canPitchFreeTrial: Bool {
        guard let yearly = yearlyPackage else { return false }
        return isEligibleForIntroOffer(yearly)
    }

    /// Short CTA for locked capsule surfaces.
    var shortConversionCTALabel: String {
        ConversionCopy.shortCTALabel(eligibleForTrial: canPitchFreeTrial)
    }

    #if DEBUG
    /// The probe's Test Store purchase: load the offering, buy the first
    /// package, and verify the resulting entitlement and local funnel record.
    ///
    /// This lives in the service rather than in the App entry point because
    /// `loadOffering` is private, and the probe has to go through the same load
    /// the paywall uses. The status is exposed through the DEBUG probe overlay
    /// so the UI test can wait for a real result instead of sleeping.
    func runProbePurchase() async {
        probeStatus = RevenueCatProbeStatus()
        guard isConfigured else {
            updateProbeStatus { status in
                status.phase = .failed
                status.failureReason = "not_configured"
            }
            return
        }
        updateProbeStatus { status in
            status.phase = .loadingPackages
        }
        await loadOffering(forceRefresh: true)
        updateProbeStatus { status in
            status.phase = .waitingForPurchase
            status.packageCount = packages.count
        }
        guard let package = packages.first else {
            updateProbeStatus { status in
                status.phase = .failed
                status.failureReason = "no_packages"
            }
            return
        }

        let state = await purchase(package)
        let customerInfo = await probeCustomerInfo()
        let babyEntitlementActive = customerInfo?.entitlements.active[RevenueCatConfig.proEntitlement] != nil
        let conversionAttributesPresent = Self.probeConversionSignature() != nil
        let purchaseOutcome = state?.probeLabel ?? "no_result"
        let succeeded = purchaseOutcome == "purchased"
            && babyEntitlementActive
            && conversionAttributesPresent

        updateProbeStatus { status in
            status.phase = succeeded ? .purchaseSucceeded : .failed
            status.purchaseOutcome = purchaseOutcome
            status.babyEntitlementActive = babyEntitlementActive
            status.conversionAttributesPresent = conversionAttributesPresent
            if !succeeded {
                if purchaseOutcome != "purchased" {
                    status.failureReason = "purchase_\(purchaseOutcome)"
                } else if !babyEntitlementActive {
                    status.failureReason = "baby_entitlement_inactive"
                } else {
                    status.failureReason = "conversion_attributes_missing"
                }
            }
        }
    }

    /// Restores the same explicit Test Store app user used by the purchase
    /// launch. The conversion signature is captured before the restore and
    /// compared afterward so a restore cannot silently count as a new sale.
    func runProbeRestore() async {
        probeStatus = RevenueCatProbeStatus()
        guard isConfigured else {
            updateProbeStatus { status in
                status.phase = .failed
                status.failureReason = "not_configured"
            }
            return
        }
        let before = Self.probeConversionSignature()
        updateProbeStatus { status in
            status.phase = .restoring
            status.conversionAttributesPresent = before != nil
        }

        errorMessage = nil
        await restore()
        let restoreSucceeded = errorMessage == nil
        let customerInfo = await probeCustomerInfo()
        let babyEntitlementActive = customerInfo?.entitlements.active[RevenueCatConfig.proEntitlement] != nil
        let after = Self.probeConversionSignature()
        let conversionCheck: String
        if before == nil {
            conversionCheck = "missing_before"
        } else if before == after {
            conversionCheck = "unchanged"
        } else {
            conversionCheck = "changed"
        }
        let succeeded = restoreSucceeded
            && babyEntitlementActive
            && conversionCheck == "unchanged"

        updateProbeStatus { status in
            status.phase = succeeded ? .restoreSucceeded : .failed
            status.restoreOutcome = succeeded ? "restored" : "not_restored"
            status.restoreBabyEntitlementActive = babyEntitlementActive
            status.conversionAttributesPresent = after != nil
            status.conversionAfterRestore = conversionCheck
            if !succeeded {
                if !babyEntitlementActive {
                    status.failureReason = "baby_entitlement_inactive_after_restore"
                } else {
                    status.failureReason = "conversion_\(conversionCheck)"
                }
            }
        }
    }

    private static let probeConversionKeys = [
        "converted_surface",
        "converted_plan",
        "converted_with_trial",
        "converted_offering",
        "pitch_views_at_convert",
    ]

    private static func probeConversionSignature() -> String? {
        let attributes = ConversionDiagnostics.subscriberAttributes
        guard probeConversionKeys.allSatisfy({ attributes[$0] != nil }) else { return nil }
        return probeConversionKeys.sorted().compactMap { key in
            guard let value = attributes[key] else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: "|")
    }

    private func probeCustomerInfo() async -> CustomerInfo? {
        try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
    }

    private func updateProbeStatus(_ update: (inout RevenueCatProbeStatus) -> Void) {
        var next = probeStatus
        update(&next)
        probeStatus = next
    }
    #endif

    @discardableResult
    func purchase(_ package: Package) async -> PurchaseState? {
        guard isConfigured else { return nil }
        isLoading = true
        defer { isLoading = false }
        let startedTrial = isEligibleForIntroOffer(package)
        do {
            let result = try await Purchases.shared.purchase(package: package)
            update(customerInfo: result.customerInfo)
            if result.userCancelled {
                errorMessage = ConversionCopy.purchaseCancelledMessage(
                    eligibleForTrial: isEligibleForIntroOffer(package)
                )
                return .cancelled
            }
            if isPro {
                ConversionDiagnostics.recordConversion(
                    plan: package.storeProduct.productIdentifier,
                    startedTrial: startedTrial,
                    offeringID: package.presentedOfferingContext.offeringIdentifier
                )
                syncConversionAttributes()
                return .purchased
            }
            return .pending
        } catch {
            let nsError = error as NSError
            if nsError.code == ErrorCode.purchaseCancelledError.rawValue {
                errorMessage = ConversionCopy.purchaseCancelledMessage(
                    eligibleForTrial: isEligibleForIntroOffer(package)
                )
                return .cancelled
            }
            await refreshIntroEligibility()
            errorMessage = ConversionCopy.purchaseFailedMessage(
                eligibleForTrial: isEligibleForIntroOffer(package)
            )
            return nil
        }
    }

    func restore() async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            update(customerInfo: try await Purchases.shared.restorePurchases())
            errorMessage = isPro ? nil : "No active Baby+ purchase was found for this Apple ID."
        } catch {
            errorMessage = "Restore failed. Please try again."
        }
    }

    /// Reports a custom-paywall impression to RevenueCat so the native paywall
    /// feeds RC's impression count and conversion %. `id` distinguishes entry
    /// points; `oncePerSession` dedupes surfaces the user can revisit.
    func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
        guard isConfigured else { return }
        if oncePerSession {
            guard !paywallImpressionsThisSession.contains(id) else { return }
            paywallImpressionsThisSession.insert(id)
        }
        ConversionDiagnostics.recordPitchView(impressionID: id)
        syncConversionAttributes()
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
    }

    /// Mirrors the on-device paywall record onto the RevenueCat customer.
    ///
    /// Attributes rather than extra impressions: RevenueCat treats every
    /// impression id as a paywall encounter, so funnel steps sent that way would
    /// drive the encounter rate to 100% and destroy the one server-side number
    /// that currently works.
    ///
    /// `isConfigured` is the load-bearing guard: `Purchases.shared` traps when
    /// RevenueCat was never configured, which is every simulator run.
    ///
    /// `setAttributes` only queues. RevenueCat uploads when the app backgrounds
    /// or folds the queue into the POST that creates a customer, so a probe run
    /// has to background the app before reading anything back.
    func syncConversionAttributes() {
        guard isConfigured else { return }
        let attributes = ConversionDiagnostics.subscriberAttributes
        guard !attributes.isEmpty else { return }
        Purchases.shared.attribution.setAttributes(attributes)
    }

    #if DEBUG
    func setLocalOverride(isPro: Bool) {
        self.isPro = isPro
        defaults.set(isPro, forKey: Self.cachedProKey)
    }
    #endif

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.update(customerInfo: customerInfo)
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        #if targetEnvironment(simulator)
        // Agent/sim runs must never hit the production RevenueCat project. A
        // configure call there creates a fake customer in the live charts. Use
        // StoreKit Testing plus the local Pro override instead.
        #if DEBUG
        // The one exception, behind a launch argument: the Test Store key is a
        // separate RevenueCat app inside the same project, so a probe run cannot
        // touch App Store customers, revenue or charts. See RevenueCatProbe.
        if RevenueCatProbe.isEnabled, RevenueCatProbe.testStoreKey.hasPrefix("test_") {
            Purchases.logLevel = .debug
            Purchases.configure(
                with: Configuration.Builder(withAPIKey: RevenueCatProbe.testStoreKey)
                    .with(appUserID: RevenueCatProbe.appUserID)
                    .build()
            )
            Purchases.shared.delegate = self
            isConfigured = true
        }
        #endif
        return
        #else
        guard RevenueCatConfig.publicSDKKey.hasPrefix("appl_") else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.publicSDKKey)
        Purchases.shared.delegate = self
        isConfigured = true
        #endif
    }

    private func refreshStatus() async {
        do {
            update(customerInfo: try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent))
        } catch {
            errorMessage = "Could not verify purchases."
        }
    }

    private func loadOffering(forceRefresh: Bool = false) async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let offerings: Offerings
            if forceRefresh,
               let refreshedOfferings = try await Purchases.shared.syncAttributesAndOfferingsIfNeeded() {
                offerings = refreshedOfferings
            } else {
                offerings = try await Purchases.shared.offerings()
            }
            let offering = offerings.offering(identifier: "default") ?? offerings.current
            packages = offering?.babySortedPackages ?? []
            errorMessage = nil
            await refreshIntroEligibility()
        } catch {
            logger.error("Product fetch failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't load purchase options. Check your connection and try again."
        }
    }

    /// Resolves StoreKit intro-offer eligibility for the loaded products. On any
    /// failure we mark resolved with an empty map so callers hide trial framing
    /// rather than over-promising.
    private func refreshIntroEligibility() async {
        let identifiers = packages
            .filter { $0.storeProduct.introductoryDiscount != nil }
            .map { $0.storeProduct.productIdentifier }
        guard !identifiers.isEmpty else {
            introEligibility = [:]
            introEligibilityResolved = true
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: identifiers)
        introEligibility = result.mapValues { $0.status == .eligible }
        introEligibilityResolved = true
    }

    private func update(customerInfo: CustomerInfo) {
        // Single premium tier: any active entitlement unlocks Baby+, which
        // survives entitlement renames or casing drift in the RC dashboard.
        isPro = !customerInfo.entitlements.active.isEmpty
        defaults.set(isPro, forKey: Self.cachedProKey)
    }

    #if targetEnvironment(simulator)
    /// Hydrates `packages` on the simulator so the real paywall, including its
    /// hero, plan cards, billed amount, disclosure, and footer, can be rendered
    /// and inspected
    /// headlessly. RevenueCat is never configured here, so the production
    /// project gains no fake customers.
    ///
    /// Under `xcodebuild test` (or the Xcode scheme) StoreKit Testing serves the
    /// local `Baby.storekit` catalog, and those genuine products are used.
    /// Under a plain `simctl launch` StoreKit has no catalog at all, so the
    /// fleet's `TestStoreProduct` fixtures stand in with the same prices. The
    /// layout under test is identical either way. Purchases stay disabled in
    /// both cases; this exists to make layout verifiable, not to fake a sale.
    private func loadStoreKitTestingProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        if ProcessInfo.processInfo.arguments.contains("-PaywallSnapshot") {
            apply(simulatorProducts: Self.fixtureProducts())
        } else if let live = await Self.storeKitTestingProducts(), !live.isEmpty {
            apply(simulatorProducts: live)
        } else {
            apply(simulatorProducts: Self.fixtureProducts())
        }
        introEligibility = Dictionary(uniqueKeysWithValues: packages.map { ($0.storeProduct.productIdentifier, true) })
        introEligibilityResolved = true
        errorMessage = nil
    }

    private func apply(simulatorProducts products: [StoreProduct]) {
        packages = products
            .map { product in
                Package(
                    identifier: product.productIdentifier,
                    packageType: Self.packageType(for: product.productIdentifier),
                    storeProduct: product,
                    offeringIdentifier: "default",
                    webCheckoutUrl: nil
                )
            }
            .sorted { BabyPackageKind(package: $0).rawValue < BabyPackageKind(package: $1).rawValue }
    }

    private static func storeKitTestingProducts() async -> [StoreProduct]? {
        let identifiers: Set<String> = [
            BabyProduct.monthly, BabyProduct.yearly, BabyProduct.lifetime,
        ]
        guard let sk2 = try? await StoreKit.Product.products(for: identifiers) else { return nil }
        return sk2.map { StoreProduct(sk2Product: $0) }
    }

    /// Same prices and trial as `Baby.storekit`, for when StoreKit Testing
    /// isn't active. Keep these in sync with that file.
    private static func fixtureProducts() -> [StoreProduct] {
        let locale = Locale(identifier: "en_US")
        func weekTrial() -> TestStoreProductDiscount {
            TestStoreProductDiscount(
                identifier: "free_trial", price: 0, localizedPriceString: "$0.00",
                paymentMode: .freeTrial, subscriptionPeriod: .init(value: 1, unit: .week),
                numberOfPeriods: 1, type: .introductory
            )
        }
        return [
            TestStoreProduct(
                localizedTitle: "Baby+ Monthly", price: 3.99, currencyCode: "USD",
                localizedPriceString: "$3.99", productIdentifier: BabyProduct.monthly,
                productType: .autoRenewableSubscription, localizedDescription: "Baby+, billed monthly.",
                subscriptionPeriod: .init(value: 1, unit: .month), introductoryDiscount: weekTrial(), locale: locale
            ).toStoreProduct(),
            TestStoreProduct(
                localizedTitle: "Baby+ Yearly", price: 24.99, currencyCode: "USD",
                localizedPriceString: "$24.99", productIdentifier: BabyProduct.yearly,
                productType: .autoRenewableSubscription, localizedDescription: "Baby+, billed yearly.",
                subscriptionPeriod: .init(value: 1, unit: .year), introductoryDiscount: weekTrial(), locale: locale
            ).toStoreProduct(),
            TestStoreProduct(
                localizedTitle: "Baby+ Lifetime", price: 39.99, currencyCode: "USD",
                localizedPriceString: "$39.99", productIdentifier: BabyProduct.lifetime,
                productType: .nonConsumable, localizedDescription: "Baby+, one-time purchase.",
                subscriptionPeriod: nil, introductoryDiscount: nil, locale: locale
            ).toStoreProduct(),
        ]
    }

    private static func packageType(for identifier: String) -> PackageType {
        if identifier.contains("lifetime") { return .lifetime }
        if identifier.contains("yearly") { return .annual }
        return .monthly
    }
    #endif
}

#if DEBUG
enum RevenueCatProbePhase: String {
    case idle
    case loadingPackages = "loading_packages"
    case waitingForPurchase = "waiting_for_purchase"
    case purchaseSucceeded = "purchase_succeeded"
    case restoring
    case restoreSucceeded = "restore_succeeded"
    case failed
}

struct RevenueCatProbeStatus: Equatable {
    var phase: RevenueCatProbePhase = .idle
    var packageCount = 0
    var purchaseOutcome = "not_started"
    var babyEntitlementActive = false
    var conversionAttributesPresent = false
    var restoreOutcome = "not_started"
    var restoreBabyEntitlementActive = false
    var conversionAfterRestore = "not_checked"
    var failureReason: String?

    var accessibleDescription: String {
        var description = [
            "phase=\(phase.rawValue)",
            "packages=\(packageCount)",
            "purchase=\(purchaseOutcome)",
            "baby_entitlement=\(babyEntitlementActive ? "active" : "inactive")",
            "conversion_attributes=\(conversionAttributesPresent ? "present" : "missing")",
            "restore=\(restoreOutcome)",
            "restore_baby_entitlement=\(restoreBabyEntitlementActive ? "active" : "inactive")",
            "conversion_after_restore=\(conversionAfterRestore)",
        ].joined(separator: " ")
        if let failureReason {
            description += " failure=\(failureReason)"
        }
        return description
    }
}

extension PurchaseState {
    var probeLabel: String {
        switch self {
        case .purchased: "purchased"
        case .cancelled: "cancelled"
        case .pending: "pending"
        }
    }
}

/// Simulator-only proof path for the fleet-wide funnel attributes.
///
/// Under the normal rules the attributes cannot be verified on a simulator: the
/// production key must never be configured there, so RevenueCat is never
/// configured, so nothing is ever sent, so a physical device is the only
/// witness. The Test Store key is a different RevenueCat app inside the same
/// project, so a probe run cannot touch App Store customers, revenue or charts.
///
/// DEBUG only, and only with the launch argument, so it cannot reach a Release
/// build or an ordinary simulator run.
enum RevenueCatProbe {
    static var isEnabled: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-rcfunnelprobe")
        #else
        false
        #endif
    }

    /// RevenueCat Test Store app `appf48b1dd074`. Read from the environment so
    /// the probe can run without the key living in a public repo.
    static var testStoreKey: String {
        let environment = ProcessInfo.processInfo.environment
        return environment["RC_TEST_STORE_KEY"]
            ?? environment["TEST_RUNNER_RC_TEST_STORE_KEY"]
            ?? ""
    }

    static var appUserID: String {
        ProcessInfo.processInfo.environment["RC_PROBE_USER"] ?? "funnel-probe-baby"
    }

    static var impressionID: String {
        ProcessInfo.processInfo.environment["RC_PROBE_SURFACE"] ?? "baby_paywall"
    }

    /// Drives a Test Store purchase after the impression, so the `converted_*`
    /// half of the funnel record is exercised and not just the impression half.
    static var wantsPurchase: Bool {
        ProcessInfo.processInfo.arguments.contains("-rcfunnelprobepurchase")
    }

    /// Drives a Test Store restore after a purchase launch has persisted the
    /// same explicit app user and its conversion record.
    static var wantsRestore: Bool {
        ProcessInfo.processInfo.arguments.contains("-rcfunnelproberestore")
    }
}
#endif
