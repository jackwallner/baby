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

    /// Now fits the phone it runs on: every control and both cards on one
    /// screen, before and after the side chips open, with no scrolling.
    func testNowFitsOneScreenWithoutScrolling() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit"]
        app.launch()
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 15))
        let screen = app.windows.firstMatch.frame
        let ids = ["nowCard", "logTime.earlier", "log.feed", "log.wet", "log.dirty", "log.sleep", "todayTotals", "addOlderEntry"]
        assertOnScreen(ids, in: app, screen: screen)
        let bottom = app.buttons["addOlderEntry"].frame
        attach(app, name: "now-fits")

        app.buttons["log.feed"].tap()
        XCTAssertTrue(app.buttons["feedSide.left"].waitForExistence(timeout: 3))
        // Let the spring settle before reading frames.
        _ = app.buttons["feedSide.bottle"].waitForExistence(timeout: 1)
        Thread.sleep(forTimeInterval: 1)
        assertOnScreen(ids + ["feedSide.left", "feedSide.bottle"], in: app, screen: screen)
        // The buttons gave the side row its room: nothing below them moved.
        XCTAssertEqual(app.buttons["addOlderEntry"].frame.minY, bottom.minY, accuracy: 1)
        attach(app, name: "now-fits-with-sides")
    }

    /// Reports read top to bottom: range, averages, charts, then the doctor.
    func testReportsReadTopToBottom() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit", "-DemoPro", "-StartTab", "3"]
        app.launch()
        let range = app.segmentedControls["reportRange"]
        XCTAssertTrue(range.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "summaryCard").firstMatch.exists)
        XCTAssertTrue(app.otherElements["Feeds a day"].exists || app.staticTexts["Feeds a day"].exists)
        attach(app, name: "reports-top")
        range.buttons["Custom"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 2), "Custom shows the From date")
        range.buttons["7 days"].tap()
        let export = app.buttons["Export CSV"]
        for _ in 0..<6 where !export.isHittable { app.swipeUp() }
        XCTAssertTrue(export.isHittable)
        XCTAssertTrue(app.buttons["Share PDF"].exists)
        attach(app, name: "reports-bottom")
    }

    private func assertOnScreen(_ ids: [String], in app: XCUIApplication, screen: CGRect) {
        for id in ids {
            let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            XCTAssertTrue(element.exists, "Missing: \(id)")
            XCTAssertTrue(screen.contains(element.frame), "Off screen: \(id) \(element.frame) in \(screen)")
        }
        for id in ["log.feed", "log.wet", "log.dirty", "log.sleep"] {
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44, "Too small to hit: \(id)")
        }
    }

    func testLargestTextKeepsLoggingAndUndoReachable() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = [
            "-SeedScreenshotData", "-NoCloudKit",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 15))
        for identifier in ["logTime.earlier", "log.feed", "log.wet", "log.dirty", "log.sleep"] {
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
