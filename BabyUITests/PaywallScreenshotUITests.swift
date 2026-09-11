import XCTest

/// Renders the real paywall under StoreKit Testing, one plan at a time, and
/// attaches the screenshot App Store Connect wants for each product's review.
/// Extract with `xcrun xcresulttool export attachments`.
final class PaywallScreenshotUITests: XCTestCase {

    private func render(plan: String, expectedPrice: String) {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments += ["-PaywallSnapshot", plan, "-NoCloudKit"]
        app.launch()
        let price = app.staticTexts["paywall.billedAmount"]
        XCTAssertTrue(price.waitForExistence(timeout: 30), "billed amount never rendered for \(plan)")
        let label = price.label
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "paywall-\(plan)"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(label.contains(expectedPrice), "\(plan) shows \(label), expected \(expectedPrice)")
    }

    func testYearlyPaywallShowsTheRealPrice() { render(plan: "yearly", expectedPrice: "24.99") }
    func testMonthlyPaywallShowsTheRealPrice() { render(plan: "monthly", expectedPrice: "3.99") }
    func testLifetimePaywallShowsTheRealPrice() { render(plan: "lifetime", expectedPrice: "39.99") }
}
