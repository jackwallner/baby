import XCTest

/// Persona audit: a skeptical free user deciding what is paid, comparing the
/// value, and testing restore and the ways out. Every step attaches a
/// screenshot and a dump of what is on screen (labels, buttons, controls
/// under 44 pt), so the walk can be reviewed without running the app.
/// Purchases are disabled on the simulator by design (RevenueCat is never
/// configured there), so the purchase tap is observed, not completed.
final class SubscriptionAuditUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.baby")
        app.launchArguments = ["-NoCloudKit", "-hasCompletedSetup", "YES"] + extra
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)

        var lines: [String] = []
        for text in app.staticTexts.allElementsBoundByIndex where text.exists && !text.label.isEmpty {
            lines.append("text   \(text.label)")
        }
        for button in app.buttons.allElementsBoundByIndex where button.exists {
            let f = button.frame
            let small = (f.width < 44 || f.height < 44) ? "  SMALL" : ""
            lines.append("button \(button.label) [\(button.identifier)] \(Int(f.width))x\(Int(f.height)) @\(Int(f.minX)),\(Int(f.minY))\(small)")
        }
        let dump = XCTAttachment(string: lines.joined(separator: "\n"))
        dump.name = "\(name).txt"
        dump.lifetime = .keepAlways
        add(dump)
    }

    private func note(_ text: String) {
        let item = XCTAttachment(string: text)
        item.name = "observation"
        item.lifetime = .keepAlways
        add(item)
    }

    private func openTab(_ app: XCUIApplication, _ id: String) {
        let tab = app.buttons[id]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "\(id) missing")
        tab.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, max: Int = 8) {
        var tries = 0
        while !element.isHittable && tries < max {
            app.swipeUp()
            tries += 1
        }
    }

    /// DemoPro persists into the shared defaults, so every free flow clears it first.
    private func freeLaunch(_ extra: [String] = []) -> XCUIApplication {
        let app = launch(extra)
        openTab(app, "tab.settings")
        let toggle = app.switches["Local Pro override (debug)"]
        scrollTo(toggle, in: app)
        if toggle.waitForExistence(timeout: 5), (toggle.value as? String) == "1" {
            toggle.switches.firstMatch.tap()
        }
        return app
    }

    func testFreeUserReadsThePaywallTopToBottom() {
        let app = freeLaunch(["-SeedScreenshotData"])
        openTab(app, "tab.log")
        snap(app, "01-now-free")
        openTab(app, "tab.reports")
        XCTAssertTrue(app.staticTexts["paywall.billedAmount"].waitForExistence(timeout: 30), "billed amount never rendered")
        snap(app, "02-paywall-top")
        app.swipeUp()
        snap(app, "03-paywall-scrolled")
        app.swipeUp()
        snap(app, "04-paywall-bottom")
        let cta = app.buttons["Continue with Baby+"]
        note("CTA exists: \(cta.exists), hittable: \(cta.isHittable), capsule tab.reports label: \(app.buttons["tab.reports"].label)")
        note("Mentions of the word 'free' in static texts: \(app.staticTexts.allElementsBoundByIndex.filter { $0.label.lowercased().contains("free") }.map(\.label))")
    }

    func testPlanSwitchAndSilentPurchaseTap() {
        let app = freeLaunch(["-SeedScreenshotData"])
        openTab(app, "tab.reports")
        let billed = app.staticTexts["paywall.billedAmount"]
        XCTAssertTrue(billed.waitForExistence(timeout: 30))
        var seen: [String] = ["default: \(billed.label)"]
        for name in ["Monthly", "Lifetime", "Yearly"] {
            let plan = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
            scrollTo(plan, in: app)
            if plan.exists {
                plan.tap()
                seen.append("\(name): \(billed.label)")
                snap(app, "10-plan-\(name.lowercased())")
            } else {
                seen.append("\(name): no plan card")
            }
        }
        note(seen.joined(separator: "\n"))
        let cta = app.buttons["Continue with Baby+"]
        scrollTo(cta, in: app)
        cta.tap()
        sleep(2)
        snap(app, "11-after-cta-tap")
        note("After the CTA tap, the paywall is still showing: \(app.staticTexts["paywall.billedAmount"].exists); alerts: \(app.alerts.count)")
    }

    func testRestoreFromThePaywallAndFromSettings() {
        let app = freeLaunch()
        openTab(app, "tab.reports")
        XCTAssertTrue(app.staticTexts["paywall.billedAmount"].waitForExistence(timeout: 30))
        let restore = app.buttons["Restore purchases"]
        scrollTo(restore, in: app)
        restore.tap()
        sleep(2)
        snap(app, "20-paywall-after-restore")
        let all = app.staticTexts.allElementsBoundByIndex.map(\.label)
        let hits = all.filter { $0.contains("Purchases aren't available") || $0.contains("No active Baby+") }
        note("Restore messages on the paywall (count \(hits.count)): \(hits)")

        openTab(app, "tab.settings")
        let settingsRestore = app.buttons["Restore purchases"]
        scrollTo(settingsRestore, in: app)
        snap(app, "21-settings-baby-plus")
        settingsRestore.tap()
        sleep(2)
        snap(app, "22-settings-after-restore")
        note("Settings restore alert shown: \(app.alerts.count > 0); alert text: \(app.alerts.firstMatch.label)")
        if app.alerts.buttons["OK"].exists { app.alerts.buttons["OK"].tap() }
    }

    /// `-SeedScreenshotData` unlocks History's chart, so these flows log by tapping.
    private func logSome(_ app: XCUIApplication) {
        openTab(app, "tab.log")
        for id in ["log.wet", "log.dirty", "log.wet"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "\(id) missing")
            button.tap()
        }
    }

    func testHistoryChartLockAndClosingThePaywall() {
        let app = freeLaunch(["-EmptyLog"])
        logSome(app)
        openTab(app, "tab.history")
        let lock = app.buttons["history.dayChart.locked"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20), "locked chart missing")
        snap(app, "30-history-locked-chart")
        lock.tap()
        XCTAssertTrue(app.staticTexts["paywall.billedAmount"].waitForExistence(timeout: 30))
        snap(app, "31-history-paywall-sheet")
        let close = app.buttons["Close"]
        note("Close button: exists \(close.exists), frame \(close.frame)")
        close.tap()
        sleep(1)
        snap(app, "32-history-after-close")
        note("Back on History after Close: \(app.buttons["history.dayChart.locked"].exists)")
    }

    func testSettingsEntryAndEmptyLogReports() {
        let app = freeLaunch(["-EmptyLog"])
        openTab(app, "tab.settings")
        let see = app.buttons["See Baby+"]
        scrollTo(see, in: app)
        snap(app, "40-settings-free-status")
        see.tap()
        XCTAssertTrue(app.staticTexts["paywall.billedAmount"].waitForExistence(timeout: 30))
        snap(app, "41-settings-paywall-sheet")
        app.buttons["Close"].tap()
        sleep(1)
        openTab(app, "tab.reports")
        sleep(3)
        snap(app, "42-empty-log-upgrade")
        app.swipeUp()
        snap(app, "43-empty-log-upgrade-scrolled")
    }

    func testSubscriberStatusManageAndLapse() {
        let app = launch(["-EmptyLog", "-DemoPro"])
        logSome(app)
        openTab(app, "tab.reports")
        sleep(3)
        snap(app, "50-pro-reports")
        note("Tab label when Pro: \(app.buttons["tab.reports"].label)")
        openTab(app, "tab.settings")
        let manage = app.links["Manage subscription"].exists ? app.links["Manage subscription"] : app.buttons["Manage subscription"]
        scrollTo(manage, in: app)
        snap(app, "51-settings-pro")
        note("Manage subscription row exists: \(manage.exists)")
        let toggle = app.switches["Local Pro override (debug)"]
        scrollTo(toggle, in: app)
        toggle.switches.firstMatch.tap()
        sleep(1)
        openTab(app, "tab.reports")
        sleep(2)
        snap(app, "52-after-lapse-reports-tab")
        note("After the entitlement ends, the tab label is: \(app.buttons["tab.reports"].label); paywall billed amount present: \(app.staticTexts["paywall.billedAmount"].exists)")
        openTab(app, "tab.history")
        sleep(1)
        snap(app, "53-after-lapse-history")
        note("History keeps the log after lapse (day rows or locked chart): \(app.buttons["history.dayChart.locked"].exists)")
    }
}
