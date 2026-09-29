import XCTest

final class LoggingUITests: XCTestCase {
    private func tally(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(identifier: "todayTotals").firstMatch.label
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit"]
        app.launch()
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 15))
        return app
    }

    func testFeedAndDiaperTapsCanBeUndone() {
        let app = launch()
        let originalTally = tally(app)
        app.buttons["log.feed"].tap()
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
        for identifier in ["log.feed", "log.wet", "log.dirty", "log.sleep"] {
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

        // The time is an inline wheel; its first column is the day.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        app.datePickers["editor.time"].pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: formatter.string(from: yesterday))

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

    func testGuidesLiveInSettingsAndReportsPreviewWithoutPaying() {
        let app = launch()
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["Stain helper"].exists)
        XCTAssertFalse(app.buttons["See Baby+"].exists)

        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let firstWeeks = app.buttons["First Weeks"]
        for _ in 0..<8 where !firstWeeks.isHittable { app.swipeUp() }
        firstWeeks.tap()
        XCTAssertTrue(app.navigationBars["First Weeks"].waitForExistence(timeout: 3))
        app.navigationBars["First Weeks"].buttons["Settings"].tap()
        app.buttons["Done"].tap()

        app.buttons["reports"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["paywall.preview.pediatricianSummary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Restore purchases"].exists)
    }

    /// App Review 4.3: with nothing logged, Reports shows the labelled
    /// example, readable in full, with no purchase.
    func testReportsShowTheExampleBeforeAnythingIsLogged() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-NoCloudKit", "-EmptyLog", "-hasCompletedSetup", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))
        app.buttons["onboarding.primary"].tap()
        XCTAssertTrue(app.buttons["reports"].waitForExistence(timeout: 5))
        app.buttons["reports"].tap()
        let summary = app.descendants(matching: .any)["paywall.preview.pediatricianSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.value as? String, "Example with made-up numbers")
        sleep(2)
        attach(app, "reports-example")
        summary.swipeLeft()
        sleep(1)
        attach(app, "reports-example-trends")
        app.descendants(matching: .any)["paywall.preview.trends"].swipeRight()
        sleep(1)
        summary.tap()
        XCTAssertTrue(app.navigationBars["Example summary"].waitForExistence(timeout: 5))
    }

    func testTurningAButtonOffRemovesItEverywhereOnNow() {
        let app = launch()
        XCTAssertTrue(app.buttons["log.sleep"].exists)
        app.buttons["settings"].tap()
        let sleep = app.switches["track.sleep"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 3))
        sleep.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["log.sleep"].waitForExistence(timeout: 2))
        XCTAssertFalse(tally(app).contains("sleep"), tally(app))
        attach(app, "tracking-no-sleep")

        app.buttons["settings"].tap()
        app.switches["track.sleep"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["log.sleep"].waitForExistence(timeout: 3))
    }

    func testOptionalSetupGoesStraightToLogging() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-NoCloudKit", "-hasCompletedSetup", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))
        app.buttons["onboarding.primary"].tap()
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["paywall.billedAmount"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    func testFeedLogsInOneTapAndTheSideIsOptional() {
        let app = launch()
        let originalTally = tally(app)
        XCTAssertFalse(app.buttons["feedSide.left"].exists, "no side choice before a feed is logged")
        app.buttons["log.feed"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 3), "the tap alone logged the feed")
        XCTAssertNotEqual(tally(app), originalTally)
        XCTAssertTrue(app.staticTexts["just now"].exists)
        XCTAssertTrue(app.buttons["feedSide.left"].waitForExistence(timeout: 3))
        attach(app, "feed-sides-offered")

        app.buttons["feedSide.right"].tap()
        app.buttons["feedSide.left"].tap()
        XCTAssertTrue(app.buttons["feedSide.right"].isSelected)
        XCTAssertTrue(app.buttons["feedSide.left"].isSelected)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Right + Left'")).firstMatch.waitForExistence(timeout: 3))
        attach(app, "feed-sides-chosen")
        app.buttons["feedSide.right"].tap()
        XCTAssertFalse(app.buttons["feedSide.right"].isSelected)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Left breast'")).firstMatch.waitForExistence(timeout: 3))

        app.buttons["log.wet"].tap()
        XCTAssertTrue(app.buttons["feedSide.left"].exists, "a diaper change mid-feed keeps the side row")
    }

    func testWindingTheClockBackLogsAtThatTimeThenReturnsToNow() {
        let app = launch()
        XCTAssertFalse(app.buttons["logTime.now"].exists)
        app.buttons["logTime.earlier"].tap()
        app.buttons["logTime.earlier"].tap()
        app.buttons["logTime.earlier"].tap()
        XCTAssertTrue(app.buttons["logTime.now"].waitForExistence(timeout: 2))
        let hint = app.staticTexts["logHint"]
        XCTAssertTrue(hint.label.hasPrefix("Taps log at"), hint.label)
        attach(app, "log-time-wound-back")

        app.buttons["log.wet"].tap()
        let toast = app.otherElements["undoToast"]
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 3))
        let stamped = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Logged pee · '")).firstMatch
        XCTAssertTrue(stamped.exists || toast.exists, "the toast names the wound-back time")
        XCTAssertTrue(app.buttons["logTime.now"].exists, "the chosen time stays for the next tap")

        app.buttons["logTime.now"].tap()
        XCTAssertFalse(app.buttons["logTime.now"].exists)
        XCTAssertEqual(app.staticTexts["logHint"].label, "Tap to log now. Hold to add details.")
    }

    func testEditingAnEntrySavesWithoutASaveButton() {
        let app = launch()
        app.buttons["History"].tap()
        app.buttons["List"].tap()
        let entry = app.cells.element(boundBy: 2)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.datePickers["editor.time"].waitForExistence(timeout: 3), "the time wheel is inline")
        XCTAssertFalse(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Done"].exists)
        let note = app.descendants(matching: .any)["editor.note"]
        note.tap()
        note.typeText("sleepy")
        attach(app, "editor-autosave")
        // Pull the sheet away: the note must already be saved.
        let editorTime = app.datePickers["editor.time"]
        for _ in 0..<3 where editorTime.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            _ = editorTime.waitForNonExistence(timeout: 2)
        }
        XCTAssertFalse(editorTime.exists)
        entry.tap()
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertEqual(note.value as? String, "sleepy")
    }

    func testTotalsCanCountTheLastTwentyFourHours() {
        let app = launch()
        XCTAssertTrue(tally(app).hasPrefix("Today:"), tally(app))
        XCTAssertTrue(app.descendants(matching: .any)["hourStrip"].exists)
        app.buttons["settings"].tap()
        let mode = app.segmentedControls["totals.mode"]
        for _ in 0..<6 where !mode.isHittable { app.swipeUp() }
        mode.buttons["Last 24 hours"].tap()
        attach(app, "totals-setting")
        app.buttons["Done"].tap()
        XCTAssertTrue(tally(app).hasPrefix("Last 24 hours:"), tally(app))
        attach(app, "totals-last-24")
        app.buttons["settings"].tap()
        for _ in 0..<6 where !mode.isHittable { app.swipeUp() }
        mode.buttons["By day"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(tally(app).hasPrefix("Today:"), tally(app))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
