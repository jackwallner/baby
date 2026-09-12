import XCTest

final class LoggingUITests: XCTestCase {
    private func tally(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(identifier: "todayTotals").firstMatch.label
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit"]
        app.launch()
        XCTAssertTrue(app.buttons["log.feed.left"].waitForExistence(timeout: 15))
        return app
    }

    func testFeedAndDiaperTapsCanBeUndone() {
        let app = launch()
        let originalTally = tally(app)
        app.buttons["log.feed.right"].tap()
        XCTAssertTrue(app.staticTexts["just now"].waitForExistence(timeout: 3))
        XCTAssertNotEqual(tally(app), originalTally)
        app.buttons["Undo"].tap()
        XCTAssertEqual(tally(app), originalTally)

        for kind in ["wet", "dirty"] {
            app.buttons["log.\(kind)"].tap()
            XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 3))
            XCTAssertNotEqual(tally(app), originalTally)
            app.buttons["Undo"].tap()
            XCTAssertEqual(tally(app), originalTally)
        }
    }

    func testHoldingAButtonDoesNotLogUntilSaved() {
        let app = launch()
        let originalTally = tally(app)
        for identifier in ["log.feed.left", "log.wet", "log.dirty", "log.sleep"] {
            app.buttons[identifier].press(forDuration: 0.7)
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
            app.buttons["Cancel"].tap()
            XCTAssertEqual(tally(app), originalTally)
            XCTAssertEqual(app.buttons["log.sleep"].label, "Sleep")
            XCTAssertFalse(app.buttons["Undo"].exists)
        }

        app.buttons["log.wet"].press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Log"].waitForExistence(timeout: 3))
        app.buttons["Log"].tap()
        XCTAssertNotEqual(tally(app), originalTally)
    }

    func testSleepWakeAndUndoPreserveTheTimer() {
        let app = launch()
        let sleep = app.buttons["log.sleep"]
        sleep.tap()
        XCTAssertEqual(sleep.label, "Wake")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Asleep '")).firstMatch.waitForExistence(timeout: 3))
        sleep.tap()
        XCTAssertEqual(sleep.label, "Sleep")
        app.buttons["Undo"].tap()
        XCTAssertEqual(sleep.label, "Wake")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "sleep-running"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSecondaryToolsStayInMoreAndRemainFree() {
        let app = launch()
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["Stain helper"].exists)
        XCTAssertFalse(app.buttons["See Baby+"].exists)

        app.buttons["more"].tap()
        app.buttons["First Weeks"].tap()
        XCTAssertTrue(app.navigationBars["First Weeks"].waitForExistence(timeout: 3))
        app.navigationBars["First Weeks"].buttons["More"].tap()
        app.buttons["Pediatrician summary"].tap()
        XCTAssertTrue(app.navigationBars["Summary"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Preview of the pediatrician summary"].waitForExistence(timeout: 10))
    }

    func testOptionalSetupGoesStraightToLogging() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-NoCloudKit", "-hasCompletedSetup", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))
        app.buttons["onboarding.primary"].tap()
        XCTAssertTrue(app.buttons["log.feed.left"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["paywall.billedAmount"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }
}
