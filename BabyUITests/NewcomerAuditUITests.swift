import XCTest

/// Persona audit: a first-time parent who knows none of the app's words.
/// Every step attaches a screenshot and a dump of what is on screen
/// (labels, buttons and any control under 44 pt), so the walk can be
/// reviewed without running the app.
final class NewcomerAuditUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func fresh(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-NoCloudKit", "-EmptyLog", "-hasCompletedSetup", "NO"] + extra
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)

        var lines: [String] = []
        for text in app.staticTexts.allElementsBoundByIndex where text.exists && !text.label.isEmpty {
            lines.append("text   \(text.label)")
        }
        for button in app.buttons.allElementsBoundByIndex where button.exists {
            let f = button.frame
            let small = (f.width < 44 || f.height < 44) ? "  SMALL" : ""
            lines.append("button \(button.label) [\(button.identifier)] \(Int(f.width))x\(Int(f.height)) @\(Int(f.minX)),\(Int(f.minY))\(small)")
        }
        let dump = XCTAttachment(string: lines.joined(separator: "\n"))
        dump.name = "\(name).txt"
        dump.lifetime = .keepAlways
        add(dump)
    }

    private func finishOnboarding(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 15))
        app.buttons["onboarding.primary"].tap()
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 8))
    }

    func testFirstRunAndFirstLogs() {
        let app = fresh()
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 15))
        snap(app, "01-onboarding-top")
        app.swipeUp()
        snap(app, "02-onboarding-scrolled")
        app.swipeDown()

        app.textFields["onboarding.name"].tap()
        app.typeText("Ada")
        snap(app, "03-onboarding-keyboard")
        app.keyboards.buttons["Done"].tap()

        app.buttons["onboarding.feeding.breast"].tap()
        snap(app, "04-onboarding-fed-chosen")

        finishOnboarding(app)
        snap(app, "05-now-empty")

        app.buttons["log.feed"].tap()
        snap(app, "06-after-feed-tap")
        sleep(2)
        snap(app, "07-feed-sides-offered")
        app.buttons["feedSide.left"].tap()
        snap(app, "08-side-left")

        app.buttons["log.wet"].tap()
        snap(app, "09-after-pee-tap")
        app.buttons["log.dirty"].tap()
        snap(app, "10-after-poop-tap")

        app.buttons["log.sleep"].tap()
        sleep(1)
        snap(app, "11-sleep-running")
        app.buttons["log.sleep"].tap()
        sleep(1)
        snap(app, "12-sleep-ended")

        app.buttons["logTime.earlier"].tap()
        snap(app, "13-log-time-wound-back")
        app.buttons["logTime.now"].tap()

        app.buttons["addOlderEntry"].tap()
        snap(app, "14-older-entry-menu")
        app.buttons["Pee diaper"].tap()
        sleep(1)
        snap(app, "15-editor")
    }

    func testTabsOnAnEmptyLog() {
        let app = fresh()
        finishOnboarding(app)
        app.buttons["tab.history"].tap()
        sleep(1)
        snap(app, "20-history-empty")
        app.buttons["tab.reports"].tap()
        sleep(3)
        snap(app, "21-upgrade")
        app.swipeUp()
        sleep(1)
        snap(app, "22-upgrade-scrolled")
        app.swipeUp()
        sleep(1)
        snap(app, "23-upgrade-bottom")
        app.buttons["tab.settings"].tap()
        sleep(1)
        snap(app, "24-settings")
        app.swipeUp()
        snap(app, "25-settings-2")
        app.swipeUp()
        snap(app, "26-settings-3")
        app.swipeUp()
        snap(app, "27-settings-4")
    }

    func testFirstWeeksAndHelpers() {
        let app = fresh()
        finishOnboarding(app)
        app.buttons["tab.settings"].tap()
        for label in ["First Weeks", "Stain helper", "Reminders"] {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            var tries = 0
            while !row.isHittable && tries < 6 { app.swipeUp(); tries += 1 }
            guard row.exists else { snap(app, "30-missing-\(label)"); continue }
            row.tap()
            sleep(1)
            snap(app, "30-\(label.replacingOccurrences(of: " ", with: "-"))")
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            app.swipeDown()
            app.swipeDown()
        }
    }

    func testReminderOfferAfterFirstFeed() {
        let app = fresh(["-ShowReminderOffer"])
        finishOnboarding(app)
        app.buttons["log.feed"].tap()
        sleep(8)
        snap(app, "40-reminder-offer")
    }

    func testLargeText() {
        let app = fresh(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 15))
        snap(app, "50-onboarding-axl")
        finishOnboarding(app)
        snap(app, "51-now-axl")
    }

    func testJoinPath() {
        let app = fresh()
        XCTAssertTrue(app.buttons["onboarding.path.join"].waitForExistence(timeout: 15))
        app.buttons["onboarding.path.join"].tap()
        sleep(1)
        snap(app, "60-join")
    }
}
