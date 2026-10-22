import XCTest

/// Persona audit: a parent weeks into using the app who repeats the core
/// taps all day and goes looking for the deeper features (timed feeds,
/// backfill, twins, reports). Each test records what it saw as a text
/// attachment, so the audit report cites runtime, not guesses.
final class ExperiencedParentAuditUITests: XCTestCase {
    private var notes: [String] = []

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
        attachment.name = "observations"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 20))
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ line: String) { notes.append(line) }

    private func tally(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(identifier: "todayTotals").firstMatch.label
    }

    /// 1. Repeat taps: five quick Pee taps, then Undo. What does Undo take back?
    func testRapidRepeatTapsAndUndoScope() {
        let app = launch()
        let before = tally(app)
        note("tally before: \(before)")
        for _ in 0..<5 { app.buttons["log.wet"].tap() }
        let after = tally(app)
        note("tally after 5 rapid Pee taps: \(after)")
        shot(app, "rapid-5-pee")
        XCTAssertTrue(app.buttons["Undo"].exists)
        app.buttons["Undo"].tap()
        let afterUndo = tally(app)
        note("tally after one Undo: \(afterUndo)")
        note("Undo button still shown after undo: \(app.buttons["Undo"].waitForExistence(timeout: 1))")
        shot(app, "rapid-after-undo")
        // Toast lifetime
        let toast = app.otherElements["undoToast"]
        note("toast frame (after undo): \(toast.exists ? "\(toast.frame)" : "none")")
    }

    /// 2. Timed feed through the long press: how many steps, and what Now shows.
    func testTimedFeedFlow() {
        let app = launch()
        app.buttons["log.feed"].press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Log"].waitForExistence(timeout: 5))
        shot(app, "timed-feed-editor")
        let timer = app.switches["Start a timer"]
        note("editor has Start a timer switch: \(timer.exists), value: \(String(describing: timer.value))")
        if timer.exists {
            timer.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            shot(app, "timed-feed-editor-timer-on")
        }
        app.buttons["Log"].tap()
        _ = app.buttons["finishFeed"].waitForExistence(timeout: 4)
        note("Finish feed visible: \(app.buttons["finishFeed"].exists)")
        shot(app, "timed-feed-running")
        let heading = app.staticTexts["Feeding now"]
        note("'Feeding now' heading: \(heading.exists)")

        // Experienced reflex: tap Feed while one is running.
        let beforeTap = tally(app)
        app.buttons["log.feed"].tap()
        note("tally before Feed tap during timer: \(beforeTap); after: \(tally(app))")
        note("Finish feed still visible after second Feed tap: \(app.buttons["finishFeed"].exists)")
        shot(app, "timed-feed-second-tap")
        if app.buttons["finishFeed"].exists {
            app.buttons["finishFeed"].tap()
            shot(app, "timed-feed-finished")
        }
    }

    /// 3. Backfill a 3 hour sleep: count the stepper taps the editor needs.
    func testBackfillLongSleepStepper() {
        let app = launch()
        app.buttons["addOlderEntry"].tap()
        let sleep = app.buttons["Sleep"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 3))
        sleep.tap()
        XCTAssertTrue(app.buttons["Log"].waitForExistence(timeout: 5))
        shot(app, "backfill-sleep-editor")
        let stepper = app.steppers.firstMatch
        note("sleep editor stepper exists: \(stepper.exists), value: \(String(describing: stepper.value)), label: \(stepper.label)")
        var taps = 0
        let inc = stepper.buttons.element(boundBy: 1)
        for _ in 0..<12 where inc.exists {
            inc.tap()
            taps += 1
        }
        note("after \(taps) taps, stepper label: \(stepper.label)")
        shot(app, "backfill-sleep-12-taps")
        let timeToggle = app.switches["Start a timer"]
        note("Start a timer toggle for Sleep editor: \(timeToggle.exists)")
        note("There is no field for end time; only Time (start) wheel and Length stepper.")
    }

    /// 4. History: edit time of a row, check for delete confirmation, and filters.
    func testHistoryEditDeleteAndFilters() {
        let app = launch()
        app.buttons["tab.history"].tap()
        app.buttons["List"].tap()
        let entry = app.cells.element(boundBy: 3)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        shot(app, "history-list")
        note("history has search field: \(app.searchFields.firstMatch.exists)")
        note("history has kind filter: \(app.segmentedControls.count) segmented controls, buttons 'Filter': \(app.buttons["Filter"].exists)")
        entry.tap()
        XCTAssertTrue(app.datePickers["editor.time"].waitForExistence(timeout: 4))
        shot(app, "history-editor")
        let delete = app.buttons["Delete"]
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        shot(app, "history-editor-bottom")
        note("editor Delete button hittable: \(delete.isHittable)")
        let rows = app.cells.count
        delete.tap()
        let confirm = app.sheets.firstMatch.exists || app.alerts.firstMatch.exists
        note("confirmation after tapping Delete in editor: \(confirm)")
        shot(app, "history-after-editor-delete")
        note("Undo toast after editor delete: \(app.buttons["Undo"].waitForExistence(timeout: 2))")
        note("cells before: \(rows), after: \(app.cells.count)")
    }

    /// 5. Twins: add a baby, find out how the active baby is shown and switched.
    func testTwinsAddAndSwitch() {
        let app = launch()
        shot(app, "twins-before")
        app.buttons["tab.settings"].tap()
        let add = app.buttons["Add a baby"]
        var swipes = 0
        while !add.isHittable && swipes < 12 { app.swipeUp(); swipes += 1 }
        note("swipes in Settings to reach Add a baby: \(swipes)")
        shot(app, "twins-settings-babies")
        add.tap()
        let field = app.textFields["Name (optional)"]
        if field.waitForExistence(timeout: 3) { field.tap(); field.typeText("Milo") }
        app.alerts.buttons["Add"].tap()
        shot(app, "twins-after-add")
        app.buttons["tab.log"].tap()
        sleep(1)
        shot(app, "twins-now-after-add")
        note("Now nav bar titles: \(app.navigationBars.allElementsBoundByIndex.map { $0.identifier })")
        note("Now tally after switching (new baby): \(tally(app))")
        note("any baby-switcher on Now: \(app.buttons.matching(NSPredicate(format: 'label CONTAINS[c] \"switch\" OR label CONTAINS[c] \"baby\"')).count)")
        // Switch back: how many taps?
        app.buttons["tab.settings"].tap()
        var back = 0
        let babyRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Milo'")).firstMatch
        while !babyRow.exists && back < 12 { app.swipeUp(); back += 1 }
        shot(app, "twins-switch-list")
        note("Settings switch list present: \(babyRow.exists) after \(back) swipes")
    }

    /// 6. Reports as an experienced Baby+ user: ranges, stats, charts.
    func testReportsRangesAndCharts() {
        let app = launch()
        app.buttons["tab.settings"].tap()
        let override = app.switches["Local Pro override (debug)"]
        for _ in 0..<14 where !override.isHittable { app.swipeUp() }
        override.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["tab.reports"].tap()
        XCTAssertTrue(app.navigationBars["Reports"].waitForExistence(timeout: 6))
        sleep(1)
        shot(app, "reports-14d")
        for title in ["7 days", "30 days", "Custom"] {
            let b = app.segmentedControls["reportRange"].buttons[title]
            if b.exists { b.tap(); sleep(1); shot(app, "reports-\(title.replacingOccurrences(of: " ", with: ""))") }
        }
        app.swipeUp()
        shot(app, "reports-scrolled-1")
        app.swipeUp()
        shot(app, "reports-scrolled-2")
        app.swipeUp()
        shot(app, "reports-scrolled-3")
        note("CSV export row: \(app.buttons["Export CSV"].exists)")
        note("Charts have tap-to-inspect hint: not testable by XCUI; source has no chartXSelection")
    }

    /// 7. Buttons: what a long press on Pee shows (diaper editor), colors.
    func testDiaperEditorAndWindowedTotals() {
        let app = launch()
        app.buttons["log.dirty"].press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["Log"].waitForExistence(timeout: 5))
        shot(app, "dirty-editor")
        note("Color menu exists: \(app.buttons["Color"].exists || app.staticTexts["Color"].exists)")
        app.buttons["Cancel"].tap()
    }

    /// 8. Return visit: leave and come back; does the clock/side chips state persist?
    func testSideChipsWindowAndBackground() {
        let app = launch()
        app.buttons["log.feed"].tap()
        XCTAssertTrue(app.buttons["feedSide.left"].waitForExistence(timeout: 3))
        shot(app, "side-chips-open")
        let l = app.buttons["feedSide.left"]
        note("side chip height: \(l.frame.height), width: \(l.frame.width)")
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        _ = app.buttons["log.feed"].waitForExistence(timeout: 5)
        note("side chips after background/return: \(app.buttons["feedSide.left"].exists)")
        shot(app, "side-chips-after-return")
    }
}
