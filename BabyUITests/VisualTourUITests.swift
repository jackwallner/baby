import XCTest

/// Walks every screen and attaches a screenshot of each, for visual review.
/// The palette comes from `TEST_RUNNER_BABY_APPEARANCE` (system, light, dark,
/// night). It asserts only that each screen opened, so one run shows everything.
final class VisualTourUITests: XCTestCase {
    private var appearance: String {
        ProcessInfo.processInfo.environment["BABY_APPEARANCE"] ?? "system"
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(appearance)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-NoCloudKit", "-Appearance", appearance] + arguments
        app.launch()
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
    }

    func testTourSetup() {
        let app = launch(["-hasCompletedSetup", "NO", "-PreviewScannerButton"])
        XCTAssertTrue(app.buttons["onboarding.path.start"].waitForExistence(timeout: 10))
        attach(app, "01-onboarding-start")
        app.buttons["onboarding.path.join"].tap()
        attach(app, "02-onboarding-join")
    }

    func testTourJoining() {
        let app = launch(["-hasCompletedSetup", "NO", "-PreviewJoining", "-FastJoinTimeout"])
        XCTAssertTrue(app.buttons["joining.giveUp"].waitForExistence(timeout: 10))
        attach(app, "03-joining")
    }

    func testTourDailyUse() {
        let app = launch(["-SeedScreenshotData"])
        XCTAssertTrue(app.buttons["more"].waitForExistence(timeout: 15))
        attach(app, "10-home")

        app.buttons["log.wet"].tap()
        XCTAssertTrue(app.otherElements["undoToast"].waitForExistence(timeout: 5) || app.buttons["Undo"].waitForExistence(timeout: 2))
        sleep(1)
        attach(app, "11-home-undo")
        app.buttons["Undo"].tap()

        app.buttons["log.sleep"].tap()
        sleep(2)
        attach(app, "12-home-sleeping")
        app.buttons["log.sleep"].tap()

        app.buttons["log.dirty"].press(forDuration: 0.8)
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        attach(app, "13-editor-dirty")
        app.buttons["Cancel"].tap()

        app.buttons["log.feed.bottle"].press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        attach(app, "14-editor-feed")
        app.buttons["Cancel"].tap()

        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        attach(app, "15-history")
    }

    func testTourMore() {
        let app = launch(["-SeedScreenshotData"])
        XCTAssertTrue(app.buttons["more"].waitForExistence(timeout: 15))
        app.buttons["more"].tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 5))
        attach(app, "20-more-top")
        app.swipeUp()
        attach(app, "21-more-middle")
        app.swipeUp()
        app.swipeUp()
        attach(app, "22-more-bottom")
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()

        app.buttons["First Weeks"].tap()
        XCTAssertTrue(app.otherElements["tallyTable"].waitForExistence(timeout: 5) || app.navigationBars.count > 0)
        attach(app, "23-first-weeks")
        app.swipeUp()
        attach(app, "24-first-weeks-lower")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Pediatrician summary"].tap()
        sleep(1)
        attach(app, "25-summary")
        app.swipeUp()
        attach(app, "26-summary-lower")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Stain helper"].tap()
        sleep(1)
        attach(app, "27-stain-helper")
    }

    func testTourLogTogether() {
        let app = launch(["-SeedScreenshotData"])
        XCTAssertTrue(app.buttons["more"].waitForExistence(timeout: 15))
        app.buttons["more"].tap()
        let invite = app.buttons["settings.partner.share"]
        scrollTo(invite, in: app)
        invite.tap()
        XCTAssertTrue(app.buttons["sharing.invite"].waitForExistence(timeout: 5))
        attach(app, "30-log-together")
        app.buttons["sharing.close"].tap()

        let join = app.buttons["settings.partner.join"]
        scrollTo(join, in: app)
        join.tap()
        XCTAssertTrue(app.buttons["join.submit"].waitForExistence(timeout: 5))
        attach(app, "32-join-sheet")
    }

    func testTourInvite() {
        let app = launch(["-SeedScreenshotData", "-SharingPreview"])
        XCTAssertTrue(app.buttons["more"].waitForExistence(timeout: 15))
        app.buttons["more"].tap()
        let invite = app.buttons["settings.partner.share"]
        scrollTo(invite, in: app)
        invite.tap()
        XCTAssertTrue(app.images["sharing.code"].waitForExistence(timeout: 5))
        attach(app, "31-invite-code")
        app.swipeUp()
        attach(app, "31b-invite-lower")
    }

    func testTourPaywall() {
        let app = launch(["-PaywallSnapshot", "yearly"])
        sleep(4)
        attach(app, "40-paywall")
    }
}
