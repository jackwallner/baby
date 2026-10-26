import XCTest

/// Shared helpers for the temporary App Store preview walkthroughs (never committed).
@MainActor
extension XCTestCase {
    func pause(_ seconds: Double) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func installAlertDismisser() {
        addUIInterruptionMonitor(withDescription: "system alerts") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Don’t Allow", "Don't Allow", "Not Now", "Continue"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
    }

    @discardableResult
    func tapIfPresent(_ element: XCUIElement, timeout: Double = 4) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        if element.isHittable { element.tap() } else { element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        return true
    }

    func element(_ app: XCUIApplication, prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A slow drag; up = content moves up (reveals what is below).
    func gentleScroll(_ app: XCUIApplication, up: Bool = true, distance: Double = 0.28) {
        let from = up ? 0.72 : 0.40
        let to = up ? from - distance : from + distance
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 350, thenHoldForDuration: 0.3)
    }

    func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 2) { back.tap() }
    }

    func tab(_ app: XCUIApplication, _ name: String) {
        tapIfPresent(app.tabBars.buttons[name], timeout: 3)
    }
}
