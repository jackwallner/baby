import Foundation
import XCTest

/// Proves the Test Store purchase and restore path through the app's
/// RevenueCat service. The purchase and restore use the same explicit app user
/// so restore can be checked without creating a second conversion.
///
/// Set `RC_PROBE_REQUIRED=1` for the targeted verification command. In that
/// mode a missing or non-Test-Store key fails immediately instead of producing
/// a green skipped result. The default skip keeps ordinary UI layout runs
/// independent of external Test Store credentials.
final class PaywallFunnelUITests: XCTestCase {

    func testTestStorePurchaseRecordsTheConversion() throws {
        let environment = ProcessInfo.processInfo.environment
        let key = environment["RC_TEST_STORE_KEY"]
            ?? environment["TEST_RUNNER_RC_TEST_STORE_KEY"]
            ?? ""
        let probeRequired = environment["RC_PROBE_REQUIRED"] == "1"
            || environment["TEST_RUNNER_RC_PROBE_REQUIRED"] == "1"
        guard key.hasPrefix("test_") else {
            if probeRequired {
                XCTFail("RC Test Store key is required for this targeted verification")
                return
            }
            throw XCTSkip("RC Test Store key not set")
        }

        let probeUser = environment["RC_PROBE_USER"]
            ?? "funnel-probe-baby-uitest-\(UUID().uuidString.lowercased())"

        let purchaseApp = configuredApp(
            key: key,
            probeUser: probeUser,
            arguments: ["-rcfunnelprobe", "-rcfunnelprobepurchase"]
        )
        purchaseApp.launch()
        let confirm = purchaseApp.buttons["Test valid purchase"]
        guard confirm.waitForExistence(timeout: 60) else {
            XCTFail("RevenueCat's Test Store sheet never appeared")
            return
        }
        confirm.tap()
        waitForStatus(
            "phase=purchase_succeeded packages=3 purchase=purchased baby_entitlement=active conversion_attributes=present",
            in: purchaseApp
        )

        if purchaseApp.state == .runningForeground {
            XCUIDevice.shared.press(.home)
        }
        purchaseApp.terminate()

        let restoreApp = configuredApp(
            key: key,
            probeUser: probeUser,
            arguments: ["-rcfunnelprobe", "-rcfunnelproberestore"]
        )
        restoreApp.launch()
        waitForStatus("phase=restore_succeeded", in: restoreApp)
        waitForStatus(
            "restore=restored restore_baby_entitlement=active conversion_after_restore=unchanged",
            in: restoreApp
        )
    }

    private func configuredApp(key: String, probeUser: String, arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = arguments + ["-NoCloudKit"]
        app.launchEnvironment["RC_PROBE_USER"] = probeUser
        app.launchEnvironment["RC_TEST_STORE_KEY"] = key
        return app
    }

    private func waitForStatus(
        _ fragment: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 60
    ) {
        let status = app.descendants(matching: .any)["rcProbe.status"]
        guard status.waitForExistence(timeout: timeout) else {
            XCTFail("RevenueCat probe status never appeared")
            return
        }
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", fragment)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "RevenueCat probe status did not reach: \(fragment)")
    }
}
