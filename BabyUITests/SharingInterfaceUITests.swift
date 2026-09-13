import XCTest

final class SharingInterfaceUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit", "-Appearance", "system"] + extra
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

    func testOnboardingOffersStartingOrJoiningALog() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-NoCloudKit", "-hasCompletedSetup", "NO", "-Appearance", "system"]
        app.launch()
        let start = app.buttons["onboarding.path.start"]
        let join = app.buttons["onboarding.path.join"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(join.exists, "Joining must be a first-class choice on the setup screen")
        XCTAssertTrue(start.isSelected)
        XCTAssertTrue(app.buttons["onboarding.primary"].exists)
        attach(app, "onboarding-start")

        join.tap()
        XCTAssertTrue(join.isSelected)
        XCTAssertTrue(app.staticTexts["Scan their code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["join.submit"].exists)
        XCTAssertFalse(app.buttons["join.submit"].isEnabled)
        XCTAssertFalse(app.buttons["onboarding.primary"].exists, "Join mode must not also offer to create a separate baby")
        XCTAssertFalse(app.textFields["onboarding.name"].exists)
        attach(app, "onboarding-join")

        let field = app.textFields["join.link"].exists ? app.textFields["join.link"] : app.textViews["join.link"]
        field.tap()
        field.typeText("not a link")
        app.buttons["join.submit"].tap()
        XCTAssertTrue(app.staticTexts["join.error"].waitForExistence(timeout: 5) || app.otherElements["join.error"].exists)

        start.tap()
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 5))
    }

    func testOpeningAnInviteBeforeSetupWaitsForTheBaby() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-NoCloudKit", "-hasCompletedSetup", "NO", "-Appearance", "system", "-PreviewJoining", "-FastJoinTimeout"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Joining the shared log"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding.primary"].exists, "No setup screen while an invitation's baby is on its way")
        XCTAssertTrue(app.buttons["joining.giveUp"].waitForExistence(timeout: 5), "A way out appears if joining takes long")
        attach(app, "joining-wait")
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
        XCTAssertTrue(night.isSelected)
        attach(app, "appearance-night-light")
        let join = app.buttons["settings.partner.join"]
        XCTAssertTrue(join.isHittable)
        join.tap()
        XCTAssertTrue(app.staticTexts["Join a shared log"].waitForExistence(timeout: 5))
        attach(app, "join-night-light")
        app.buttons["join.close"].tap()
        XCTAssertTrue(app.buttons["System"].waitForExistence(timeout: 5))
        app.buttons["System"].tap()
    }
}
