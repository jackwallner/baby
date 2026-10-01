import XCTest

/// The wrist's core loop on a seeded log (`-WatchDemo`: fed Left 2h 14m ago,
/// pee 48m ago): tap, see it confirmed, take it back.
/// The accessibility tree is ready before a loaded simulator finishes the
/// launch animation, and a tap synthesized then never reaches the app (seen
/// on the SE pair). Wait for the first button, then for the screen to draw.
func settle(_ app: XCUIApplication) {
    _ = app.buttons.firstMatch.waitForExistence(timeout: 20)
    Thread.sleep(forTimeInterval: 2)
}

final class WatchLoggingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WatchDemo"] + arguments
        app.launch()
        settle(app)
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func text(_ app: XCUIApplication, containing value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    func testPeeIsConfirmedAndUndone() {
        let app = launch()
        let pee = app.buttons["Pee"]
        XCTAssertTrue(pee.waitForExistence(timeout: 15))
        attach(app, "now")
        pee.tap()
        XCTAssertTrue(app.staticTexts["Pee logged"].waitForExistence(timeout: 3))
        XCTAssertTrue(text(app, containing: "just now").waitForExistence(timeout: 3), "the glance shows the new diaper at once")
        attach(app, "pee-logged")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Removed"].waitForExistence(timeout: 3))
        XCTAssertTrue(text(app, containing: "48m").waitForExistence(timeout: 3), "Undo brings back the previous diaper")
        attach(app, "undone")
    }

    func testNextSideIsOfferedAndLogged() {
        let app = launch()
        let next = app.buttons["Feed, Right, next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "after a Left feed, Right is offered next")
        next.tap()
        XCTAssertTrue(app.staticTexts["Feed · Right logged"].waitForExistence(timeout: 3))
        XCTAssertTrue(text(app, containing: "Fed · Right").exists)
        XCTAssertTrue(app.buttons["Feed, Left, next"].waitForExistence(timeout: 3), "the next side flips")
    }

    func testSleepStartsAndWakes() {
        let app = launch()
        let sleep = app.buttons["Start sleep"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 15))
        sleep.tap()
        XCTAssertTrue(app.staticTexts["Sleep started"].waitForExistence(timeout: 3))
        let wake = text(app, containing: "Wake, asleep")
        XCTAssertTrue(wake.waitForExistence(timeout: 3))
        attach(app, "asleep")
        wake.tap()
        XCTAssertTrue(app.staticTexts["Woke up"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Start sleep"].waitForExistence(timeout: 3))
    }

    func testLogEarlierBackdatesATap() {
        let app = launch()
        let earlier = app.buttons["Log earlier"].firstMatch
        XCTAssertTrue(earlier.waitForExistence(timeout: 15))
        earlier.tap()
        let pee = app.buttons.matching(NSPredicate(format: "label == 'Pee' AND value == '15m ago'")).firstMatch
        XCTAssertTrue(pee.waitForExistence(timeout: 5))
        attach(app, "earlier")
        pee.tap()
        XCTAssertTrue(app.staticTexts["Pee logged"].waitForExistence(timeout: 3))
        XCTAssertTrue(text(app, containing: "15m").waitForExistence(timeout: 3), "the entry is 15 minutes old, not now")
        attach(app, "earlier-logged")
    }

    func testTodayListsCountsAndEntries() {
        let app = launch(["-WatchPage", "1"])
        XCTAssertTrue(app.staticTexts["Today · Day 3"].waitForExistence(timeout: 15))
        XCTAssertTrue(text(app, containing: "7").exists)
        XCTAssertTrue(text(app, containing: "Feed · Left").exists)
        attach(app, "today")
    }
}

final class ComplicationGalleryUITests: XCTestCase {
    func testComplicationFacesRender() {
        let app = XCUIApplication()
        app.launchArguments = ["-WatchDemo", "-ComplicationGallery"]
        app.launch()
        let feed = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "2h 14m")).firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 15))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "complications"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
