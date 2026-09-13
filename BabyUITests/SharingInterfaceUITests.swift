import XCTest

final class SharingInterfaceUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit"]
        app.launch()
        XCTAssertTrue(app.buttons["more"].waitForExistence(timeout: 15))
        return app
    }

    func testSharingExplainsOneLogBeforeInvite() {
        let app = launch()
        app.buttons["more"].tap()

        let trigger = app.buttons["settings.partner.share"]
        for _ in 0..<6 where !trigger.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(trigger.waitForExistence(timeout: 5))
        XCTAssertEqual(trigger.label, "Share with your partner")
        trigger.tap()

        XCTAssertTrue(app.staticTexts["One shared log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Who can see it"].exists)
        XCTAssertTrue(app.staticTexts["Who can edit it"].exists)
        XCTAssertTrue(app.staticTexts["iCloud sync"].exists)
        XCTAssertTrue(app.buttons["sharing.invite"].exists)
        XCTAssertFalse(app.buttons["sharing.invite"].label.contains("Preparing"))
        let close = app.buttons["sharing.close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertLessThanOrEqual(close.frame.maxY, app.frame.maxY, "Not now must fit inside the screen")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "sharing-explanation"
        attachment.lifetime = .keepAlways
        add(attachment)
        close.tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 5))
    }
}
