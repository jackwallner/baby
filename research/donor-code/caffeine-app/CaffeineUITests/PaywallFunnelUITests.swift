import XCTest

/// Proves the `converted_*` half of the fleet paywall record actually reaches
/// RevenueCat, not just the impression half.
///
/// `rc-funnel-probe` drives an impression and reads the `pitch_views_*`
/// attributes back, but it cannot buy anything: RevenueCat's Test Store puts up
/// its own confirmation sheet and `simctl` has no way to tap it. This does.
///
/// Test Store purchases are simulated. No StoreKit, no App Store, no revenue,
/// no real transaction, and the customer it creates cannot appear in App Store
/// charts. A Test Store subscription expires five minutes after purchase, so
/// read the attributes promptly:
///
///     rc-funnel-attributes caffeine --user <the id this run used>
final class PaywallFunnelUITests: XCTestCase {

    func testTestStorePurchaseRecordsTheConversion() {
        let probeUser = ProcessInfo.processInfo.environment["RC_PROBE_USER"]
            ?? "funnel-probe-caffeine-uitest"

        // Addressed by bundle id rather than by the implicit initialiser: several
        // apps in this fleet have a PRODUCT_NAME that differs from the target
        // name, and XCUIApplication() cannot resolve those, failing with "pid 0".
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.caffeine")
        app.launchArguments += ["-rcfunnelprobe", "-rcfunnelprobepurchase"]
        app.launchEnvironment["RC_PROBE_USER"] = probeUser
        app.launch()

        // Offerings have to load before the sheet can appear, so this waits
        // rather than checking once.
        let confirm = app.buttons["Test valid purchase"]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 60),
            "RevenueCat's Test Store sheet never appeared, so no purchase was attempted"
        )
        confirm.tap()

        // `setAttributes` only queues. A purchase flushes it on its own, because
        // RevenueCat folds pending attributes into the receipt POST, but
        // backgrounding is the guaranteed trigger so it is done too when the app
        // is still alive. It is not always: some apps finish the purchase and the
        // runner has already let go of them, which is not a failure of what this
        // test checks.
        sleep(10)
        if app.state == .runningForeground {
            XCUIDevice.shared.press(.home)
            sleep(10)
        }
    }
}
