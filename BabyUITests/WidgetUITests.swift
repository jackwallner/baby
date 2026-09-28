import XCTest

/// Adds the one-tap Pee widget to the Home Screen and taps it, proving the
/// tile renders and logs without opening the app. Springboard's widget
/// gallery changes between iOS releases, so this drives it by label and
/// attaches a screenshot at each step. App Intents only run for a signed
/// app: re-sign the simulator build with the team identity first (see
/// `.claude/rules/release-verification.md`), or the tap is silently dropped.
@MainActor
final class WidgetUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPeeButtonWidgetLogsWithOneTap() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BABY_WIDGET_TEST"] == "1", "needs a re-signed build; see release-verification.md")
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit"]
        app.launch()
        XCTAssertTrue(app.buttons["log.wet"].waitForExistence(timeout: 20))

        XCUIDevice.shared.press(.home)
        sleep(2)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 2)
        XCTAssertTrue(springboard.buttons["Edit"].waitForExistence(timeout: 5))
        springboard.buttons["Edit"].tap()
        springboard.buttons["Add Widget"].tap()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Baby")
        springboard.cells["Baby Tracker"].tap()

        let preview = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Baby Tracker, '")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let peeButton = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Pee button'")).firstMatch
        for _ in 0..<8 where !(peeButton.exists && peeButton.isHittable) {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.6)))
            sleep(1)
        }
        XCTAssertTrue(peeButton.isHittable, "Pee button page not reached")
        attach("1-gallery-pee-button")
        springboard.buttons.matching(NSPredicate(format: "label ENDSWITH 'Add Widget'")).firstMatch.tap()
        sleep(2)
        springboard.buttons["Done"].tap()
        sleep(2)
        attach("2-home-screen")

        let widget = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Log pee'")).firstMatch
        XCTAssertTrue(widget.waitForExistence(timeout: 10), springboard.debugDescription)
        XCTAssertTrue(widget.value as? String == "3 today", String(describing: widget.value))
        widget.tap()
        // The tap runs in the app process; the tile turns into Undo for a few
        // seconds, then redraws with the new count.
        let undo = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Undo pee'")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 60), "the tile never offered Undo")
        attach("3-undo-offered")
        let updated = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Log pee' AND value == '4 today'")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 60), "the tile never showed the new pee")
        attach("4-after-undo-window")

        // A second tap, then Undo: the count goes back to four.
        updated.tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 60), "the second tap never offered Undo")
        undo.tap()
        let restored = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Log pee' AND value == '4 today'")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 60), "Undo did not take the second pee back")
        attach("5-after-undo")
    }
}
