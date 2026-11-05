import XCTest

/// The release gate's journeys (`qa-gate run`, `~/ios/qa/README.md`). They run
/// once per persona, German and the unfolded iPhone Duo included, so controls
/// are found by identifier, or by both languages where only a label exists.
/// They assert reachability; the FleetQA oracles judge each screen. The core
/// loop also asserts what it logged.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    private let bundleID = "com.jackwallner.baby"

    override func setUp() {
        continueAfterFailure = false
    }

    func test1FirstRunToFirstLog() {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        QA.launch(app, arguments: ["-NoCloudKit", "-EmptyLog", "-hasCompletedSetup", "NO"])
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 20))
        QA.checkpoint(app, "onboarding")
        app.buttons["onboarding.path.join"].tap()
        QA.checkpoint(app, "onboarding-join")
        app.buttons["onboarding.path.start"].tap()
        XCTAssertTrue(app.buttons["onboarding.primary"].waitForExistence(timeout: 10))
        app.buttons["onboarding.primary"].tap()
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 15))
        QA.checkpoint(app, "first-log-empty")
        app.buttons["tab.reports"].tap()
        XCTAssertTrue(element("paywall.preview.pediatricianSummary", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["paywall.billedAmount"].waitForExistence(timeout: 30))
        QA.checkpoint(app, "upgrade-before-anything-logged", paywall: true)
    }

    func test2LogFeedSidesAndUndo() {
        let app = seeded()
        logHome("log", in: app)
        app.buttons["log.feed"].tap()
        XCTAssertTrue(app.buttons["feedSide.left"].waitForExistence(timeout: 5))
        toastGone(in: app)
        QA.checkpoint(app, "feed-sides")
        app.buttons["feedSide.left"].tap()
        toastGone(in: app)
        QA.checkpoint(app, "feed-side-chosen")
        app.buttons["feedSide.done"].tap()
        XCTAssertTrue(app.buttons["log.wet"].waitForExistence(timeout: 5))
        let before = counts(in: app)
        app.buttons["log.wet"].tap()
        XCTAssertTrue(undo(in: app).waitForExistence(timeout: 5))
        // The audit can't look at the toast: it fails the journey if the toast
        // expires mid-checkpoint, so its tap target is asserted here instead.
        XCTAssertGreaterThanOrEqual(undo(in: app).frame.height, 44)
        undo(in: app).tap()
        XCTAssertEqual(counts(in: app), before, "Undo takes the pee back")
        app.buttons["log.sleep"].tap()
        toastGone(in: app)
        QA.checkpoint(app, "sleep-running")
        app.buttons["log.sleep"].tap()
        toastGone(in: app)
        logHome("log-after-wake", in: app)
        app.buttons["addOlderEntry"].tap()
        QA.checkpoint(app, "older-entry-menu")
        either("Pee diaper", "Windel: Pipi", in: app).tap()
        XCTAssertTrue(element("editor.time", in: app).waitForExistence(timeout: 10))
        QA.checkpoint(app, "entry-editor")
    }

    func test3HistoryListAndCalendar() {
        let app = seeded()
        // Unfolded, History is a pane beside Log and its tab leaves the capsule.
        if app.buttons["tab.history"].waitForExistence(timeout: 3) { app.buttons["tab.history"].tap() }
        XCTAssertTrue(element("history.layout", in: app).waitForExistence(timeout: 15))
        either("List", "Liste", in: app).tap()
        QA.checkpoint(app, "history-list")
        either("Calendar", "Kalender", in: app).tap()
        QA.checkpoint(app, "history-calendar")
        either("List", "Liste", in: app).tap()
    }

    func test4UpgradeAndSettings() {
        let app = seeded()
        app.buttons["tab.reports"].tap()
        XCTAssertTrue(app.staticTexts["paywall.billedAmount"].waitForExistence(timeout: 30))
        QA.checkpoint(app, "upgrade-paywall", paywall: true)
        scroll(until: either("Restore purchases", "Käufe wiederherstellen", in: app), in: app)
        QA.checkpoint(app, "upgrade-paywall-footer", paywall: true)
        app.buttons["tab.settings"].tap()
        let firstWeeks = either("First Weeks", "Erste Wochen", in: app)
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        QA.checkpoint(app, "settings")
        scroll(until: firstWeeks, in: app)
        firstWeeks.tap()
        XCTAssertTrue(element("tallyTable", in: app).waitForExistence(timeout: 10))
        QA.checkpoint(app, "first-weeks")
        back(in: app).tap()
        let stains = either("Stain helper", "Fleckenhilfe", in: app)
        scroll(until: stains, in: app)
        stains.tap()
        QA.checkpoint(app, "stain-helper")
    }

    func test5ReportsAndSummaryWithBabyPlus() {
        let app = seeded(extra: ["-DemoPro"])
        app.buttons["tab.reports"].tap()
        XCTAssertTrue(element("reportRange", in: app).waitForExistence(timeout: 15))
        QA.checkpoint(app, "reports")
        let preview = app.buttons["summary.previewAndSharePDF"]
        scroll(until: preview, in: app)
        QA.checkpoint(app, "reports-for-the-doctor")
        preview.tap()
        let share = either("Share PDF", "PDF teilen", in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 20))
        QA.checkpoint(app, "summary-pdf")
    }

    func test6InterruptedAndRelaunched() {
        let app = seeded()
        logHome("log-before-interrupt", in: app)
        QA.interrupt(app)
        logHome("log-after-background", in: app)
        QA.relaunch(app)
        logHome("log-after-relaunch", in: app)
    }

    /// The one job: a feed and both diapers count on Today and are still there
    /// after the app is killed. Runs on the real store, without the seed.
    func testCoreLoopFeedAndDiapersCountAndSurviveRelaunch() {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        QA.launch(app, arguments: ["-NoCloudKit", "-hasCompletedSetup", "NO"])
        if app.buttons["onboarding.primary"].waitForExistence(timeout: 20) {
            app.buttons["onboarding.primary"].tap()
        }
        logHome("core-start", in: app)
        let before = counts(in: app)

        app.buttons["log.feed"].tap()
        XCTAssertTrue(app.buttons["feedSide.left"].waitForExistence(timeout: 5))
        toastGone(in: app)
        QA.checkpoint(app, "core-feed-logged")
        app.buttons["feedSide.left"].tap()
        app.buttons["feedSide.done"].tap()
        app.buttons["log.wet"].tap()
        toastGone(in: app)
        QA.checkpoint(app, "core-pee-logged")
        app.buttons["log.dirty"].tap()
        toastGone(in: app)
        QA.checkpoint(app, "core-poop-logged")

        let logged = counts(in: app)
        XCTAssertEqual(logged, [before[0] + 1, before[1] + 1, before[2] + 1])

        app.launchArguments = app.launchArguments.filter { $0 != "-hasCompletedSetup" && $0 != "NO" }
        QA.relaunch(app)
        logHome("core-after-relaunch", in: app)
        XCTAssertEqual(counts(in: app), logged, "the entries survive a relaunch")
    }

    // MARK: - Helpers

    private func seeded(extra: [String] = [], journey: String = #function) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: bundleID)
        QA.launch(app, arguments: ["-SeedScreenshotData", "-NoCloudKit"] + extra, journey: journey)
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 20))
        return app
    }

    private func logHome(_ name: String, in app: XCUIApplication, journey: String = #function) {
        XCTAssertTrue(app.buttons["log.feed"].waitForExistence(timeout: 20))
        QA.checkpoint(app, name, journey: journey)
    }

    /// Feeds, pee and poop from the totals label, "Today: 8 feeds · 6 pee · 3 poop".
    private func counts(in app: XCUIApplication) -> [Int] {
        let label = element("todayTotals", in: app).label
        let line = label.components(separatedBy: ": ").last ?? label
        let values = line.components(separatedBy: " · ").prefix(3).compactMap {
            Int($0.prefix { $0.isNumber })
        }
        XCTAssertEqual(values.count, 3, "unreadable totals: \(label)")
        return values
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func undo(in app: XCUIApplication) -> XCUIElement {
        either("Undo", "Rückgängig", in: app)
    }

    /// A control with a visible label and no identifier, in English or German.
    private func either(_ english: String, _ german: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", [english, german])).firstMatch
    }

    /// The system back button. The unfolded iPhone Duo draws it in a toolbar
    /// outside the navigation bar, with no label, so it goes by its identifier.
    private func back(in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["BackButton"]
        return button.waitForExistence(timeout: 3) ? button : app.navigationBars.buttons.firstMatch
    }

    /// A checkpoint fails the journey if an element it is reading disappears,
    /// and the Undo toast lasts 8 seconds.
    private func toastGone(in app: XCUIApplication) {
        XCTAssertTrue(undo(in: app).waitForNonExistence(timeout: 20))
    }

    /// Scrolls in short drags, held so nothing coasts, until the target is clear
    /// of the capsule and the navigation bar: isHittable is already true beneath
    /// them, and a tap there lands on a tab or scrolls to the top. The drag runs
    /// under the capsule, which sits over the open pane when unfolded.
    private func scroll(until target: XCUIElement, in app: XCUIApplication) {
        let page = app.windows.firstMatch
        let capsule = app.buttons["tab.log"].frame.union(app.buttons["tab.settings"].frame)
        let bar = app.navigationBars.firstMatch
        let top = bar.exists ? bar.frame.maxY : 0
        let x = capsule.midX / page.frame.width
        let start = page.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.65))
        let end = page.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.35))
        for _ in 0..<40 {
            if target.exists, target.isHittable, target.frame.minY >= top, !target.frame.intersects(capsule) { return }
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.3)
        }
        XCTFail("never scrolled clear to \(target)")
    }
}
