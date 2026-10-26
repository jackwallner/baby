import XCTest

@MainActor
final class PreviewCaptureUITests: XCTestCase {
    /// The seed logs "today" in the hours before launch, so run in a zone where it is evening.
    private func eveningZone() -> String {
        let utcHour = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: .now).hour ?? 0
        var offset = 20 - utcHour
        if offset > 14 { offset -= 24 }
        if offset < -11 { offset += 24 }
        return offset == 0 ? "UTC" : (offset > 0 ? "Etc/GMT-\(offset)" : "Etc/GMT+\(-offset)")
    }

    func testPreviewWalkthrough() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-SeedScreenshotData", "-NoCloudKit", "-DemoPro"]
        app.launchEnvironment["TZ"] = eveningZone()
        installAlertDismisser()
        app.launch()
        _ = app.buttons["log.feed"].waitForExistence(timeout: 20)
        print("PREVIEW-MARK log")
        pause(3.5)
        tapIfPresent(app.buttons["log.wet"])
        pause(3)

        print("PREVIEW-MARK history")
        tapIfPresent(app.buttons["tab.history"])
        pause(3.5)
        gentleScroll(app)
        pause(2.5)

        print("PREVIEW-MARK reports")
        tapIfPresent(app.buttons["tab.reports"])
        pause(4)
        gentleScroll(app)
        pause(2.5)
        gentleScroll(app)
        pause(2)

        print("PREVIEW-MARK firstweeks")
        tapIfPresent(app.buttons["tab.settings"])
        pause(1.5)
        tapIfPresent(element(app, prefix: "First Weeks"), timeout: 3)
        pause(4)
        gentleScroll(app)
        pause(2)
        tapIfPresent(app.buttons["tab.log"])
        pause(3)
    }
}
