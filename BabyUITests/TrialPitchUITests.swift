import XCTest

/// The passive Baby+ sheet: shown after a log stands (its 8 s Undo window
/// ran out) once the log has entries, never to a subscriber, and not again
/// inside 14 days.
final class TrialPitchUITests: XCTestCase {
    /// Undo window plus the sheet's short delay, with room for a slow runner.
    private let sheetWait: TimeInterval = 16

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit", "-TrialPitchTest"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["log.wet"].waitForExistence(timeout: 15))
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSheetShowsAfterALogAndRespectsItsCooldown() {
        let app = launch(["-TrialPitchShownDaysAgo", "15"])
        app.buttons["log.wet"].tap()
        let cta = app.buttons["trialPitch.cta"]
        XCTAssertTrue(cta.waitForExistence(timeout: sheetWait), "the sheet never appeared after a log")
        XCTAssertTrue(app.staticTexts["trialPitch.billedAmount"].exists)
        XCTAssertTrue(app.staticTexts["Reports for the pediatrician"].exists)
        sleep(1)
        attach(app, "trial-pitch-sheet")

        app.buttons["trialPitch.decline"].tap()
        XCTAssertTrue(cta.waitForNonExistence(timeout: 5))

        // Just shown, so the next log stays quiet.
        app.buttons["log.wet"].tap()
        XCTAssertFalse(cta.waitForExistence(timeout: sheetWait), "the sheet came back inside its cooldown")
    }

    func testCooldownHoldsTheSheet() {
        let app = launch(["-TrialPitchShownDaysAgo", "13"])
        app.buttons["log.wet"].tap()
        XCTAssertFalse(app.buttons["trialPitch.cta"].waitForExistence(timeout: sheetWait))
    }

    func testSubscriberNeverSeesTheSheet() {
        let app = launch(["-DemoPro", "-TrialPitchShownDaysAgo", "30"])
        app.buttons["log.wet"].tap()
        XCTAssertFalse(app.buttons["trialPitch.cta"].waitForExistence(timeout: sheetWait))
    }
}
