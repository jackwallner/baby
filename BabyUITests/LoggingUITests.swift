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

    func testDeletingFromHistoryCanBeUndone() {
        let app = launch()
        app.buttons["History"].tap()
        // The layout is remembered between launches.
        app.buttons["List"].tap()
        // Cell 0 is the List / Calendar picker, then the day header with the
        // day's totals; the entries follow it.
        let totals = app.cells.element(boundBy: 1).staticTexts.element(boundBy: 1)
        let entry = app.cells.element(boundBy: 2)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        let originalTotals = totals.label
        entry.swipeLeft()
        // A long swipe deletes at once; a short one reveals the button.
        if app.buttons["Delete"].waitForExistence(timeout: 2) { app.buttons["Delete"].tap() }
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 3))
        XCTAssertNotEqual(totals.label, originalTotals)
        app.buttons["Undo"].tap()
        XCTAssertEqual(totals.label, originalTotals)
    }

    func testHistoryCalendarShowsTheSelectedDay() {
        let app = launch()
        app.buttons["log.wet"].tap()
        app.buttons["History"].tap()
        app.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["Previous month"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pee'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Today"].exists)
        app.buttons["List"].tap()
        XCTAssertFalse(app.buttons["Previous month"].exists)
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

    func testOlderEntryLandsOnItsOwnDayNotToday() {
        let app = launch()
        let originalTally = tally(app)
        app.buttons["addOlderEntry"].tap()
        app.buttons["Pee diaper"].tap()
        XCTAssertTrue(app.buttons["Log"].waitForExistence(timeout: 3))

        // The compact picker's first button is the date; its popover is a month grid.
        app.datePickers.firstMatch.buttons.firstMatch.tap()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        if !Calendar.current.isDate(yesterday, equalTo: .now, toGranularity: .month) {
            app.buttons["Previous Month"].tap()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        let day = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", formatter.string(from: yesterday))).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 3))
        day.tap()
        // Close the month grid by tapping the sheet's title, not above the sheet.
        app.navigationBars["Log a pee diaper"].staticTexts.firstMatch.tap()

        app.buttons["Log"].tap()
        XCTAssertTrue(app.buttons["log.wet"].waitForExistence(timeout: 3))
        XCTAssertEqual(tally(app), originalTally)
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
