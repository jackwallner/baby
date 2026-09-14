import XCTest

/// The second phone in a real two-account test. Run on a simulator signed in
/// to a different iCloud account than the Mac, while the Mac runs
/// `BabyCloudSchema --host-partner-test` (Development) and hands over the link
/// in `TEST_RUNNER_BABY_INVITE_URL`. Skipped otherwise.
final class TwoDeviceParticipantUITests: XCTestCase {
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "two-device-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits for `condition`, bringing the app back to the foreground between
    /// checks so CloudKit imports without relying on push, which simulators
    /// do not receive.
    private func eventually(_ app: XCUIApplication, timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            XCUIDevice.shared.press(.home)
            sleep(2)
            app.activate()
            sleep(8)
        }
        return condition()
    }

    func testJoinsLogsAndSeesTheOwnersEntries() throws {
        let invite = try XCTUnwrap(ProcessInfo.processInfo.environment["BABY_INVITE_URL"], "No invite link: run from the two-device script")
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-hasCompletedSetup", "NO", "-Appearance", "system"]
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.path.join"].waitForExistence(timeout: 20))
        app.buttons["onboarding.path.join"].tap()
        let field = app.textFields["join.link"].exists ? app.textFields["join.link"] : app.textViews["join.link"]
        field.tap()
        field.typeText("Join Two-device check's log in Baby Tracker \(invite)")
        app.buttons["join.submit"].tap()
        attach(app, "1-joining")

        let error = app.staticTexts["join.error"]
        let home = app.buttons["more"]
        let arrived = eventuallyWithoutLeaving(timeout: 240) { home.exists || error.exists }
        attach(app, "2-after-join")
        XCTAssertFalse(error.exists, "Join failed: \(error.label)")
        XCTAssertTrue(arrived && home.exists, "The shared baby never arrived")
        XCTAssertTrue(app.navigationBars["Two-device check"].exists || app.staticTexts["Two-device check"].exists, "Home is not showing the owner's baby")

        app.buttons["History"].tap()
        XCTAssertTrue(eventually(app, timeout: 120) { app.staticTexts["Feed"].exists && app.staticTexts["Wet"].exists }, "The owner's entries did not import")
        attach(app, "3-owner-history")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["log.dirty"].tap()
        sleep(3)
        app.buttons["log.feed.right"].tap()
        sleep(2)
        attach(app, "4-partner-logged")

        app.buttons["History"].tap()
        XCTAssertTrue(eventually(app, timeout: 300) { app.staticTexts["Sleep"].exists }, "The owner's reply entry never reached this phone")
        attach(app, "5-owner-reply-arrived")
    }

    private func eventuallyWithoutLeaving(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            sleep(2)
        }
        return condition()
    }
}
