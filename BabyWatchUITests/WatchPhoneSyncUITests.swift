import XCTest

/// The real path between a paired iPhone and Watch, no demo data: the phone's
/// summary reaches the wrist, and wrist taps and their Undo come back
/// acknowledged, which the phone only sends after a save. Runs when the
/// paired iPhone has the app open with `-SeedScreenshotData` and the runner
/// gets `TEST_RUNNER_BABY_WATCH_E2E=1` (`scripts/watch-e2e.sh`).
final class WatchPhoneSyncUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func matching(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval, _ message: String) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: timeout), .completed, message)
    }

    func testPhoneSummaryArrivesAndWristTapsReachThePhone() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BABY_WATCH_E2E"] == "1",
                          "needs the paired iPhone app open with -SeedScreenshotData")
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Poop"].waitForExistence(timeout: 20))
        settle(app)
        waitUntilGone(app.staticTexts["Open Baby Tracker on your iPhone to connect"], timeout: 90, "the phone's summary never arrived")
        XCTAssertTrue(matching(app, "Fed · Left").waitForExistence(timeout: 10), "the glance shows the phone's last feed")

        app.buttons["Poop"].tap()
        XCTAssertTrue(app.staticTexts["Poop logged"].waitForExistence(timeout: 3))
        waitUntilGone(matching(app, "waiting for iPhone"), timeout: 90, "the phone never acknowledged the Poop")

        app.buttons["Pee"].tap()
        XCTAssertTrue(app.staticTexts["Pee logged"].waitForExistence(timeout: 3))
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Removed"].waitForExistence(timeout: 3))
        waitUntilGone(matching(app, "waiting for iPhone"), timeout: 90, "the phone never acknowledged the Pee and its Undo")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "synced"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
