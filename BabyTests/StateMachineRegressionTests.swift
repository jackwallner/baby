import CoreData
import UserNotifications
import XCTest
@testable import Baby

/// Regressions from the 2026-11-06 state machine audit and its review
/// (`project-docs/audits/state-machines-2026-11-06-fixes.md`).
@MainActor
final class StateMachineRegressionTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var persistence: Persistence!
    private var store: EventStore!

    override func setUp() async throws {
        suite = "StateMachineRegressionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        Reminders.defaultsOverride = defaults
        Reminders.forgetLastSchedule()
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.hiddenKinds)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.totalsWindow)
        WidgetUndo.clear()
        persistence = Persistence(cloudKit: false, inMemory: true)
        store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: Calendar.current.date(byAdding: .day, value: -2, to: .now))
    }

    override func tearDown() async throws {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        Reminders.defaultsOverride = nil
        Reminders.forgetLastSchedule()
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: - B2: "Last 24 hours" totals on widgets and the Watch age out

    private func summary(window: TotalsWindow, at now: Date) throws -> NowSummary {
        let child = try XCTUnwrap(store.child)
        let events = persistence.events(for: child, in: store.context)
        return NowSummary.make(child: child, events: events, now: now, window: window, tracked: .all, feedTypes: .all)
    }

    private func logTwoFeeds(base: Date) {
        store.log(.feed, at: base.addingTimeInterval(-20 * 3600))
        store.log(.feed, at: base.addingTimeInterval(-1 * 3600))
    }

    func testDayWindowStillClearsAtTheNextDay() throws {
        let base = Calendar.current.startOfDay(for: .now).addingTimeInterval(12 * 3600)
        logTwoFeeds(base: base)
        let made = try summary(window: .midnight, at: base)
        XCTAssertEqual(made.todayFeeds, 1, "precondition: only the feed after midnight counts")
        XCTAssertNil(made.counted, "a day window carries no aging list")
        XCTAssertEqual(made.current(now: base.addingTimeInterval(13 * 3600)).todayFeeds, 0)
    }

    /// The audit's repro: a summary made at `base` and read 10 hours later
    /// must not count the feed that is now 30 hours old.
    func testLast24HoursDropsAFeedOnceItIsOlderThanADay() throws {
        let base = Date.now
        logTwoFeeds(base: base)
        let made = try summary(window: .last24Hours, at: base)
        XCTAssertEqual(made.todayFeeds, 2, "precondition: both feeds are inside 24 hours when made")
        let later = base.addingTimeInterval(10 * 3600)
        let truth = try summary(window: .last24Hours, at: later)
        XCTAssertEqual(truth.todayFeeds, 1, "precondition: a fresh summary counts one")
        XCTAssertEqual(made.current(now: later).todayFeeds, 1)
        XCTAssertEqual(made.current(now: later).current(now: later).todayFeeds, 1, "aging is applied once")
    }

    func testLast24HoursDiapersAgeOutAndMatchTheWatchList() throws {
        let base = Date.now
        store.log(.wet, at: base.addingTimeInterval(-23 * 3600))
        store.log(.dirty, at: base.addingTimeInterval(-22 * 3600))
        store.log(.wet, at: base.addingTimeInterval(-2 * 3600))
        let made = try summary(window: .last24Hours, at: base)
        XCTAssertEqual(made.todayWet, 2)
        XCTAssertEqual(made.todayDirty, 1)
        let later = base.addingTimeInterval(3 * 3600)
        let shown = made.current(now: later)
        XCTAssertEqual(shown.todayWet, 1)
        XCTAssertEqual(shown.todayDirty, 0)
        let listed = shown.recentInWindow(now: later)
        XCTAssertEqual(listed.filter { $0.kind == .wet }.count, shown.todayWet, "the count and the Watch list agree")
    }

    func testAWristTapUnderLast24HoursAgesOutAndItsUndoIsNotSubtractedTwice() throws {
        let base = Date.now
        let made = try summary(window: .last24Hours, at: base)
        let tap = WatchLogPayload(action: .log, kind: .feed, at: base, childID: made.childID)
        let tapped = made.applying(tap, now: base)
        XCTAssertEqual(tapped.todayFeeds, 1)
        XCTAssertEqual(tapped.current(now: base.addingTimeInterval(25 * 3600)).todayFeeds, 0)
        let undone = tapped.applying(tap.undo, now: base.addingTimeInterval(5))
        XCTAssertEqual(undone.todayFeeds, 0)
        XCTAssertEqual(undone.counted, [])
    }

    /// A summary cached or pushed by an older build has no aging list: it
    /// still decodes and keeps its counts until the phone sends a new one.
    func testASummaryFromAnOlderBuildStillDecodes() throws {
        let base = Date.now
        logTwoFeeds(base: base)
        var made = try summary(window: .last24Hours, at: base)
        made.counted = nil
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(made)) as? [String: Any])
        XCTAssertNil(json["counted"])
        json.removeValue(forKey: "counted")
        let old = try JSONDecoder().decode(NowSummary.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.counted)
        XCTAssertEqual(old.todayFeeds, 2)
        XCTAssertEqual(old.current(now: base.addingTimeInterval(3600)).todayFeeds, 2)
        let fresh = try summary(window: .last24Hours, at: base)
        XCTAssertFalse(fresh.sameContent(as: old), "the upgraded phone republishes, so the Watch gets the list")
    }
}
