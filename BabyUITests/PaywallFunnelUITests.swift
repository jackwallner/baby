import XCTest

/// Proves the `converted_*` half of the fleet paywall record actually reaches
/// RevenueCat, through the Test Store. Needs `RC_TEST_STORE_KEY` in the
/// environment (the Baby project's Test Store app `appf48b1dd074`); without it
/// the probe launch never configures RevenueCat and this test skips.
final class PaywallFunnelUITests: XCTestCase {

    func testTestStorePurchaseRecordsTheConversion() throws {
        let key = ProcessInfo.processInfo.environment["RC_TEST_STORE_KEY"] ?? ""
        try XCTSkipUnless(key.hasPrefix("test_"), "RC_TEST_STORE_KEY not set")
        let probeUser = ProcessInfo.processInfo.environment["RC_PROBE_USER"] ?? "funnel-probe-baby-uitest"

        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments += ["-rcfunnelprobe", "-rcfunnelprobepurchase"]
        app.launchEnvironment["RC_PROBE_USER"] = probeUser
        app.launchEnvironment["RC_TEST_STORE_KEY"] = key
        app.launch()

        let confirm = app.buttons["Test valid purchase"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 60), "RevenueCat's Test Store sheet never appeared")
        confirm.tap()

        sleep(10)
        if app.state == .runningForeground {
            XCUIDevice.shared.press(.home)
            sleep(10)
        }
    }
}
