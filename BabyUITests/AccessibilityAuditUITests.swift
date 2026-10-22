import XCTest

/// Persona audit: larger text, imperfect vision, one-handed reach.
/// Each step attaches a screenshot and a dump of every control with its size,
/// whether it is hittable, and how far from the bottom edge it sits (the thumb
/// zone), plus any control under 44 pt or without a label.
final class AccessibilityAuditUITests: XCTestCase {
    private let xxxl = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(size: String? = nil, dark: Bool = false, seed: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        var args = ["-NoCloudKit", seed ? "-SeedScreenshotData" : "-EmptyLog"] + extra
        if let size { args += ["-UIPreferredContentSizeCategoryName", size] }
        if dark { args += ["-AppleInterfaceStyle", "Dark"] }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)

        let screen = app.windows.firstMatch.frame
        var lines = ["screen \(Int(screen.width))x\(Int(screen.height))"]
        for text in app.staticTexts.allElementsBoundByIndex where text.exists && !text.label.isEmpty {
            lines.append("text   \(text.label) \(Int(text.frame.minX)),\(Int(text.frame.minY)) \(Int(text.frame.width))x\(Int(text.frame.height))")
        }
        for button in app.buttons.allElementsBoundByIndex where button.exists {
            let f = button.frame
            var flags = ""
            if f.width < 44 || f.height < 44 { flags += "  SMALL" }
            if button.label.isEmpty { flags += "  NOLABEL" }
            if !button.isHittable { flags += "  NOTHITTABLE" }
            let fromBottom = Int(screen.maxY - f.maxY)
            lines.append("button \(button.label) [\(button.identifier)] \(Int(f.width))x\(Int(f.height)) @\(Int(f.minX)),\(Int(f.minY)) bottomGap=\(fromBottom)\(flags)")
        }
        for other in [app.switches, app.sliders, app.textFields, app.datePickers, app.segmentedControls] {
            for element in other.allElementsBoundByIndex where element.exists {
                let f = element.frame
                lines.append("control \(element.elementType.rawValue) \(element.label) [\(element.identifier)] \(Int(f.width))x\(Int(f.height)) @\(Int(f.minX)),\(Int(f.minY))")
            }
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

    /// Scrolls until the element can be tapped, counting the swipes it took.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Int {
        var swipes = 0
        while !element.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
        return swipes
    }

    // MARK: - Onboarding at the largest text

    func testOnboardingXXXL() {
        let app = launch(size: xxxl, seed: false, extra: ["-hasCompletedSetup", "NO"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 15))
        snap(app, "A01-onboarding-top")
        let swipes = scrollTo(app.buttons["onboarding.primary"], in: app)
        add(XCTAttachment(string: "onboarding.primary needed \(swipes) swipes"))
        snap(app, "A02-onboarding-primary-reached")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        if app.textFields["onboarding.name"].isHittable {
            app.textFields["onboarding.name"].tap()
            app.typeText("Ada")
            snap(app, "A03-onboarding-keyboard")
        }
    }

    // MARK: - Core logging at the largest text

    func testNowXXXL() {
        let app = launch(size: xxxl)
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 15))
        snap(app, "B01-now-top")
        for id in ["log.feed", "log.wet", "log.dirty", "log.sleep", "addOlderEntry"] {
            let el = app.buttons[id]
            let swipes = el.exists ? scrollTo(el, in: app) : -1
            add(XCTAttachment(string: "\(id) exists=\(el.exists) swipesToHittable=\(swipes)"))
        }
        snap(app, "B02-now-scrolled")
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        app.buttons["log.feed"].tap()
        sleep(1)
        snap(app, "B03-after-feed-with-sides-and-toast")
        // Is the Undo toast and the capsule still usable?
        let undo = app.buttons["Undo"]
        add(XCTAttachment(string: "undo exists=\(undo.exists) hittable=\(undo.isHittable) frame=\(undo.frame)"))
        app.buttons["logTime.earlier"].tap()
        snap(app, "B04-log-time-wound-back")
    }

    func testNavigationXXXL() {
        let app = launch(size: xxxl)
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 15))
        for tab in ["tab.log", "tab.history", "tab.reports", "tab.settings"] {
            let b = app.buttons[tab]
            add(XCTAttachment(string: "\(tab) exists=\(b.exists) hittable=\(b.isHittable) frame=\(b.frame) label=\(b.label)"))
        }
        app.buttons["tab.history"].tap()
        sleep(1)
        snap(app, "C01-history-xxxl")
        app.swipeUp()
        snap(app, "C02-history-xxxl-scrolled")
        app.buttons["tab.reports"].tap()
        sleep(3)
        snap(app, "C03-upgrade-xxxl")
        app.swipeUp(); app.swipeUp()
        snap(app, "C04-upgrade-xxxl-scrolled")
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        snap(app, "C05-upgrade-xxxl-bottom")
        app.buttons["tab.settings"].tap()
        sleep(1)
        snap(app, "C06-settings-xxxl")
        app.swipeUp()
        snap(app, "C07-settings-xxxl-2")
    }

    func testEditorXXXL() {
        let app = launch(size: xxxl)
        XCTAssertTrue(app.buttons["addOlderEntry"].waitForExistence(timeout: 15))
        scrollTo(app.buttons["addOlderEntry"], in: app)
        app.buttons["addOlderEntry"].tap()
        snap(app, "D01-older-entry-menu")
        let pee = app.buttons["Pee diaper"]
        if pee.waitForExistence(timeout: 3) {
            pee.tap()
            sleep(1)
            snap(app, "D02-editor-xxxl")
            app.swipeUp()
            snap(app, "D03-editor-xxxl-scrolled")
        }
    }

    // MARK: - Settings pages that matter for the persona

    func testSettingsDetailXXXL() {
        let app = launch(size: xxxl)
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 15))
        app.buttons["tab.settings"].tap()
        for label in ["Buttons", "Appearance", "Reminders", "First Weeks"] {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            var tries = 0
            while !row.isHittable && tries < 10 { app.swipeUp(); tries += 1 }
            guard row.exists else { add(XCTAttachment(string: "missing row \(label)")); continue }
            row.tap()
            sleep(1)
            snap(app, "E-\(label.replacingOccurrences(of: " ", with: "-"))-xxxl")
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            app.swipeDown(); app.swipeDown(); app.swipeDown()
        }
    }

    // MARK: - Dark and a standard size, for contrast and baseline

    func testNowDarkDefaultSize() {
        let app = launch(dark: true)
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 15))
        snap(app, "F01-now-dark")
        app.buttons["log.feed"].tap()
        sleep(1)
        snap(app, "F02-now-dark-after-feed")
    }

    func testNowAX1() {
        let app = launch(size: "UICTContentSizeCategoryAccessibilityM")
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 15))
        snap(app, "G01-now-axm")
    }

    func testNowLargeNonAccessibility() {
        let app = launch(size: "UICTContentSizeCategoryXXXL")
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 15))
        snap(app, "G10-now-xxxl-nonax")
    }

    // MARK: - Reminder offer sheet at the largest text

    func testReminderOfferXXXL() {
        let app = launch(size: xxxl, seed: false, extra: ["-ShowReminderOffer"])
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 15))
        app.buttons["log.feed"].tap()
        sleep(8)
        snap(app, "H01-reminder-offer-xxxl")
        for id in ["reminderOffer.accept", "reminderOffer.decline"] {
            let el = app.buttons[id]
            add(XCTAttachment(string: "\(id) exists=\(el.exists) hittable=\(el.isHittable) frame=\(el.frame)"))
        }
    }

    func testLogTogetherAndJoinXXXL() {
        let app = launch(size: xxxl, seed: false, extra: ["-hasCompletedSetup", "NO"])
        XCTAssertTrue(app.buttons["onboarding.path.join"].waitForExistence(timeout: 15))
        scrollTo(app.buttons["onboarding.path.join"], in: app)
        app.buttons["onboarding.path.join"].tap()
        sleep(1)
        snap(app, "I01-join-xxxl")
        app.swipeUp()
        snap(app, "I02-join-xxxl-scrolled")
    }
}
