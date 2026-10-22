import Foundation
import XCTest

import RevenueCat

@testable import Baby
/// The fleet paywall record, checked in this app's own build.
///
/// The `rc-funnel-probe` run proves an impression reaches RevenueCat. These
/// prove what is underneath it: the counts, the conversion freeze, RevenueCat's
/// silent 40-character key limit, and the rule that nothing here may carry free
/// text or health data. Every assertion is a claim that will be read off a
/// customer record later, so a wrong value is worse than no value.

final class PaywallFunnelTests: XCTestCase {

    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        // A throwaway suite per test. These counters outlive a launch and would
        // otherwise carry between tests and into the real container.
        let name = "conv.tests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: name)!
        ConversionDiagnostics.defaultsOverride = suite
    }

    override func tearDown() {
        ConversionDiagnostics.defaultsOverride = nil
        suite = nil
        super.tearDown()
    }

    func testCountsPitchesPerSurfaceAndInTotal() {
        ConversionDiagnostics.recordPitchView(impressionID: "baby_paywall")
        ConversionDiagnostics.recordPitchView(impressionID: "baby_paywall")
        ConversionDiagnostics.recordPitchView(impressionID: "baby_onboarding_plus")

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["pitch_views_total"], "3")
        XCTAssertEqual(attributes["pitch_views_paywall"], "2")
        XCTAssertEqual(attributes["pitch_last"], "onboarding_plus")
    }

    func testNoAttributesBeforeAnyPitchIsSeen() {
        // Someone never shown a paywall has nothing to say about paywalls.
        // Zeros would make them look like a funnel failure.
        ConversionDiagnostics.recordAppOpen()
        XCTAssertTrue(ConversionDiagnostics.subscriberAttributes.isEmpty)
    }

    func testRecordsHowEarlyTheFirstPitchArrived() {
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "baby_paywall")

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["opens_before_first_pitch"], "2")
        XCTAssertEqual(attributes["days_since_install"], "0")
    }

    func testTheEarlinessPairIsFrozenOnTheFirstPitchOnly() {
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "baby_paywall")
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "baby_onboarding_plus")

        XCTAssertEqual(
            ConversionDiagnostics.subscriberAttributes["opens_before_first_pitch"],
            "1"
        )
    }

    func testAnInstallThatPredatesThisCodeReportsNoAge() {
        // No recorded app open, so no install stamp. Absent is the honest
        // answer; zero would claim they were asked on their first day.
        ConversionDiagnostics.recordPitchView(impressionID: "baby_paywall")
        XCTAssertNil(ConversionDiagnostics.subscriberAttributes["days_since_install"])
        XCTAssertNotNil(ConversionDiagnostics.subscriberAttributes["pitch_views_total"])
    }

    func testConversionFreezesTheSurfaceAndCountAtTheMomentOfSale() {
        ConversionDiagnostics.recordPitchView(impressionID: "baby_paywall")
        ConversionDiagnostics.recordPitchView(impressionID: "baby_onboarding_plus")
        ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: true, offeringID: "default")
        // A pitch after the sale must not rewrite how they converted.
        ConversionDiagnostics.recordPitchView(impressionID: "baby_paywall")

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_surface"], "onboarding_plus")
        XCTAssertEqual(attributes["pitch_views_at_convert"], "2")
        XCTAssertEqual(attributes["converted_plan"], "yearly")
        XCTAssertEqual(attributes["converted_with_trial"], "true")
        XCTAssertEqual(attributes["converted_offering"], "default")
    }

    func testOnlyTheFirstConversionIsRecorded() {
        ConversionDiagnostics.recordPitchView(impressionID: "baby_paywall")
        ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: true)
        // A renewal or plan change is not a new answer to what sold them.
        ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: false)

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_plan"], "monthly")
        XCTAssertEqual(attributes["converted_with_trial"], "true")
    }

    func testAttributeKeysStayInsideRevenueCatsLimit() {
        // RevenueCat drops a key over 40 characters, silently.
        let long = String(repeating: "a", count: 80)
        ConversionDiagnostics.recordPitchView(impressionID: "baby_\(long)")
        for key in ConversionDiagnostics.subscriberAttributes.keys {
            XCTAssertLessThanOrEqual(key.count, 40, "attribute key too long: \(key)")
        }
    }

    func testNoAttributeCarriesFreeTextOrHealthData() {
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "baby_paywall")
        ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: false)

        for (key, value) in ConversionDiagnostics.subscriberAttributes {
            XCTAssertFalse(value.contains(" "), "\(key) looks like free text: \(value)")
            XCTAssertLessThanOrEqual(value.count, 64, "\(key) is too long to be a label")
        }
    }
}

@MainActor
private final class MockPurchases: RevenueCatClient {
    var cachedCustomerInfo: CustomerInfo?
    var info = makeInfo(active: false)
    var fetchError: Error?
    var fetchHandler: ((CacheFetchPolicy) async throws -> CustomerInfo)?
    var purchaseCalls = 0
    var restoreCalls = 0
    var cancelPurchase = false
    var policies: [CacheFetchPolicy] = []
    var eligibility: [String: IntroEligibilityStatus] = [:]

    func customerInfo(fetchPolicy: CacheFetchPolicy) async throws -> CustomerInfo {
        policies.append(fetchPolicy)
        if let fetchHandler { return try await fetchHandler(fetchPolicy) }
        if let fetchError { throw fetchError }
        return info
    }
    var offering: Offering?
    func paywallOffering(forceRefresh: Bool) async throws -> Offering? {
        if let fetchError { throw fetchError }
        return offering
    }
    func purchase(package: Package) async throws -> PurchaseResultData {
        purchaseCalls += 1
        return (nil, info, cancelPurchase)
    }
    func restorePurchases() async throws -> CustomerInfo {
        restoreCalls += 1
        if let fetchError { throw fetchError }
        return info
    }
    func introEligibility(productIdentifiers: [String]) async -> [String: IntroEligibilityStatus] { eligibility }
    func setSubscriberAttributes(_ attributes: [String: String]) {}
    func recordImpression(_ params: CustomPaywallImpressionParams) {}
}

@MainActor
private func makeInfo(active: Bool, date: Date = .now, lifetime: Bool = false, identifier: String = RevenueCatConfig.proEntitlement) -> CustomerInfo {
    let entitlement = EntitlementInfo(
        identifier: identifier, isActive: active, willRenew: active && !lifetime,
        periodType: .normal, latestPurchaseDate: date, originalPurchaseDate: date,
        expirationDate: lifetime ? nil : date.addingTimeInterval(active ? 86_400 : -86_400),
        store: .appStore, productIdentifier: lifetime ? BabyProduct.lifetime : BabyProduct.monthly,
        isSandbox: true, ownershipType: .purchased
    )
    return CustomerInfo(entitlements: EntitlementInfos(entitlements: [identifier: entitlement]),
                        requestDate: date, firstSeen: date, originalAppUserId: "purchase-unit-test")
}

@MainActor
private func makePackage() -> Package {
    let product = TestStoreProduct(
        localizedTitle: "Monthly", price: 3.99, currencyCode: "USD",
        localizedPriceString: "$3.99", productIdentifier: BabyProduct.monthly,
        productType: .autoRenewableSubscription, localizedDescription: "Monthly access",
        subscriptionPeriod: .init(value: 1, unit: .month), locale: Locale(identifier: "en_US")
    ).toStoreProduct()
    return Package(identifier: "$rc_monthly", packageType: .monthly, storeProduct: product,
                   offeringIdentifier: "default", webCheckoutUrl: nil)
}

@MainActor
final class PurchaseEntitlementTests: XCTestCase {
    func testDebugAndSimulatorNeverSelectProductionKey() {
        for simulator in [true, false] {
            XCTAssertNil(RevenueCatEnvironment.key(production: "appl_prod", isDebug: true, isSimulator: simulator, testKey: nil))
            XCTAssertNil(RevenueCatEnvironment.key(production: "appl_prod", isDebug: true, isSimulator: simulator, testKey: "appl_prod"))
            XCTAssertEqual(RevenueCatEnvironment.key(production: "appl_prod", isDebug: true, isSimulator: simulator, testKey: "test_qa"), "test_qa")
        }
        XCTAssertNil(RevenueCatEnvironment.key(production: "appl_prod", isDebug: false, isSimulator: true, testKey: "test_qa"))
        XCTAssertEqual(RevenueCatEnvironment.key(production: "appl_prod", isDebug: false, isSimulator: false, testKey: "test_qa"), "appl_prod")
    }

    func testCachedPremiumUnlocksBeforeNetworkRespondsAndSurvivesOffline() async {
        let mock = MockPurchases()
        mock.cachedCustomerInfo = makeInfo(active: true)
        mock.fetchError = URLError(.notConnectedToInternet)
        let service = StoreService(client: mock, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        service.start()
        XCTAssertTrue(service.isPro)
        await service.refreshStatus()
        XCTAssertTrue(service.isPro)
    }

    func testUnresolvedMembershipCannotStartAnotherPurchase() async {
        let mock = MockPurchases()
        mock.fetchError = URLError(.notConnectedToInternet)
        let service = StoreService(client: mock)
        XCTAssertTrue(service.isCheckingEntitlements)
        _ = await service.purchase(makePackage())
        XCTAssertEqual(mock.purchaseCalls, 0)
        XCTAssertFalse(service.isCheckingEntitlements)
    }

    func testRestoreUnlocksLifetimeWithoutBuyingAgain() async throws {
        let mock = MockPurchases()
        mock.info = makeInfo(active: true, lifetime: true)
        let service = StoreService(client: mock, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await service.restore()
        XCTAssertTrue(service.isPro)
        XCTAssertEqual(mock.restoreCalls, 1)
        _ = await service.purchase(makePackage())
        XCTAssertEqual(mock.purchaseCalls, 0)
        XCTAssertTrue(service.isLifetime)
    }

    func testPurchaseAndCancellationUseRevenueCatResult() async throws {
        let mock = MockPurchases()
        mock.info = makeInfo(active: false)
        let service = StoreService(client: mock, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await service.refreshStatus()
        mock.cancelPurchase = true
        let cancelled = await service.purchase(makePackage())
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertFalse(service.isPro)
        mock.cancelPurchase = false
        mock.info = makeInfo(active: true)
        let purchased = await service.purchase(makePackage())
        XCTAssertEqual(purchased, .purchased)
        XCTAssertTrue(service.isPro)
        XCTAssertEqual(mock.purchaseCalls, 2)
    }

    func testDelayedFreeFetchCannotRelockACompletedRestore() async throws {
        let mock = MockPurchases()
        let old = makeInfo(active: false, date: Date(timeIntervalSinceNow: -60))
        mock.info = makeInfo(active: true)
        let service = StoreService(client: mock, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        var continuation: CheckedContinuation<CustomerInfo, Never>?
        mock.fetchHandler = { _ in await withCheckedContinuation { continuation = $0 } }
        let fetch = Task { await service.refreshStatus() }
        while continuation == nil { await Task.yield() }
        await service.restore()
        continuation?.resume(returning: old)
        await fetch.value
        XCTAssertTrue(service.isPro)
    }

    func testListenerUpdatesItsOwnServiceAndIgnoresOlderRecords() async throws {
        let mock = MockPurchases()
        let now = Date()
        let service = StoreService(client: mock, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await service.receive(makeInfo(active: true, date: now)).value
        XCTAssertTrue(service.isPro)
        await service.receive(makeInfo(active: false, date: now.addingTimeInterval(-60))).value
        XCTAssertTrue(service.isPro)
        await service.receive(makeInfo(active: false, date: now.addingTimeInterval(60))).value
        XCTAssertFalse(service.isPro)
    }
    func testPersistedProBooleanCannotOutliveRevenueCatEntitlement() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: StoreService.cachedProKey)
        let mock = MockPurchases()
        mock.fetchError = URLError(.notConnectedToInternet)
        let service = StoreService(client: mock, defaults: defaults)
        service.start()
        await service.refreshStatus()
        XCTAssertFalse(service.isPro)
        XCTAssertFalse(service.isLifetime)
    }

}
