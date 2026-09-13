import XCTest

final class SharingInterfaceUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["more"].waitForExistence(timeout: 15))
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSharingExplainsHowSomeoneElseJoins() {
        let app = launch()
        app.buttons["more"].tap()

        let trigger = app.buttons["settings.partner.share"]
        scrollTo(trigger, in: app)
        XCTAssertTrue(trigger.waitForExistence(timeout: 5))
        XCTAssertEqual(trigger.label, "Invite someone")
        XCTAssertTrue(app.buttons["settings.partner.join"].exists, "Joining must be reachable without an invite link in hand")
        trigger.tap()

        XCTAssertTrue(app.staticTexts["Log together"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["They install Baby Tracker"].exists)
        XCTAssertTrue(app.staticTexts["They scan your code"].exists)
        XCTAssertTrue(app.staticTexts["You both log"].exists)
        let invite = app.buttons["sharing.invite"]
        XCTAssertTrue(invite.isHittable)
        XCTAssertLessThanOrEqual(invite.frame.maxY, app.frame.maxY, "Create invite must fit inside the screen")
        attach(app, "sharing-explanation")
        app.buttons["sharing.close"].tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 5))
    }

    func testInviteShowsAScannableCodeAndALink() {
        let app = launch(["-SharingPreview"])
        app.buttons["more"].tap()
        let trigger = app.buttons["settings.partner.share"]
        scrollTo(trigger, in: app)
        trigger.tap()

        XCTAssertTrue(app.images["sharing.code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sharing.sendLink"].exists)
        XCTAssertTrue(app.buttons["sharing.manage"].exists)
        XCTAssertTrue(app.staticTexts["No one has joined yet. Once they scan the code, their name appears here."].exists)
        attach(app, "sharing-invite")
    }

    func testJoinRejectsAPastedLinkThatIsNotAnInvite() {
        let app = launch()
        app.buttons["more"].tap()
        let join = app.buttons["settings.partner.join"]
        scrollTo(join, in: app)
        join.tap()

        XCTAssertTrue(app.staticTexts["Join a shared log"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["join.submit"].isEnabled, "Join stays disabled until something is pasted")
        let field = app.textFields["join.link"].exists ? app.textFields["join.link"] : app.textViews["join.link"]
        field.tap()
        field.typeText("https://example.com/not-an-invite")
        app.buttons["join.submit"].tap()
        XCTAssertTrue(app.staticTexts["join.error"].waitForExistence(timeout: 5) || app.otherElements["join.error"].exists)
        attach(app, "join-error")
    }

    func testOnboardingOffersJoiningAnExistingLog() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-NoCloudKit", "-hasCompletedSetup", "NO"]
        app.launch()
        let join = app.buttons["onboarding.join"]
        XCTAssertTrue(join.waitForExistence(timeout: 10))
        attach(app, "onboarding-join-entry")
        join.tap()
        XCTAssertTrue(app.staticTexts["Join a shared log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Easiest: scan their code"].exists)
    }

    func testAppearanceOffersSystemLightDarkAndNightLight() {
        let app = launch()
        app.buttons["more"].tap()
        let night = app.buttons["Night light"]
        scrollTo(night, in: app)
        for label in ["System", "Light", "Dark", "Night light"] {
            XCTAssertTrue(app.buttons[label].exists, "Missing appearance option \(label)")
        }
        night.tap()
        attach(app, "appearance-night-light")
        let invite = app.buttons["settings.partner.share"]
        for _ in 0..<6 where !invite.isHittable {
            app.swipeDown()
        }
        attach(app, "more-night-light")
        invite.tap()
        XCTAssertTrue(app.staticTexts["Log together"].waitForExistence(timeout: 5))
        attach(app, "sharing-night-light")
        app.buttons["sharing.close"].tap()
        scrollTo(app.buttons["System"], in: app)
        app.buttons["System"].tap()
    }
}
