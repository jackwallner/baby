import XCTest

final class LayoutUITests: XCTestCase {
    func testSetupDisclaimerCanScrollAboveTheFixedButton() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-NoCloudKit", "-hasCompletedSetup", "NO"]
        app.launch()
        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 15))
        let disclaimer = app.staticTexts["onboarding.disclaimer"]
        for _ in 0..<8 {
            if disclaimer.exists && disclaimer.frame.maxY <= primary.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(disclaimer.isHittable)
        XCTAssertLessThanOrEqual(disclaimer.frame.maxY, primary.frame.minY)
        XCTAssertTrue(primary.isHittable)
        attach(app, name: "setup-disclaimer-reachable")
    }

    func testLargestTextKeepsLoggingAndUndoReachable() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = [
            "-SeedScreenshotData", "-NoCloudKit",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["log.feed.left"].waitForExistence(timeout: 15))
        for identifier in ["log.feed.left", "log.feed.right", "log.feed.bottle", "log.wet", "log.dirty", "log.sleep"] {
            let button = app.buttons[identifier]
            reveal(button, in: app)
            XCTAssertTrue(button.isHittable, "Unreachable control: \(identifier)")
        }
        app.buttons["log.sleep"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Undo"].isHittable)
        app.buttons["Undo"].tap()
        XCTAssertEqual(app.buttons["log.sleep"].label, "Sleep")
        attach(app, name: "largest-text-logging")
    }

    func testLargestTextPaywallKeepsPricesAndLegalLinksReachable() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = [
            "-PaywallSnapshot", "yearly", "-NoCloudKit",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        let billedAmount = app.staticTexts["paywall.billedAmount"]
        XCTAssertTrue(billedAmount.waitForExistence(timeout: 30))
        reveal(billedAmount, in: app)
        XCTAssertTrue(billedAmount.isHittable)
        XCTAssertTrue(billedAmount.label.contains("24.99"))
        let restore = app.buttons["Restore purchases"]
        reveal(restore, in: app)
        XCTAssertTrue(restore.isHittable)
        for label in ["Terms of Use", "Privacy Policy"] {
            let link = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            reveal(link, in: app)
            XCTAssertTrue(link.isHittable, "Unreachable legal link: \(label)")
        }
        attach(app, name: "largest-text-paywall")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
