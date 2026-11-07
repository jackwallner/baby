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

    // MARK: - B1 and B4: coming back to the app hands the reminder plan over

    /// Allowing notifications in iOS Settings leaves the log unchanged, so the
    /// foreground pass must reschedule without waiting for a summary change.
    func testReturningToTheAppHandsTheReminderPlanOverWithAnUnchangedLog() throws {
        Reminders.feedInterval = .threeHours
        store.log(.feed, at: .now.addingTimeInterval(-600))
        XCTAssertNotNil(store.summary.lastFeedAt, "precondition: a feed is logged")
        XCTAssertEqual(Reminders.lastPlanned?.map(\.id), [Reminders.feedID], "precondition: the tap planned the reminder")
        // What happened while notifications were denied is unknown to the
        // process; the foreground pass forgets it and must plan again.
        Reminders.forgetLastSchedule()
        store.returnToForeground()
        XCTAssertEqual(Reminders.lastPlanned?.map(\.id), [Reminders.feedID])
    }

    /// Settings' "Notifications are off" footer reads permission again when
    /// the app returns, since the Settings screen stays mounted meanwhile.
    func testReturningToTheAppAsksSettingsToReadPermissionAgain() {
        let posted = expectation(forNotification: Reminders.foregrounded, object: nil)
        store.returnToForeground()
        wait(for: [posted], timeout: 1)
    }

    // MARK: - Product call 6: a late pending-list answer deleted a newer feed reminder

    /// Records what `reschedule` hands to the notification center.
    private final class RecordingCenter: @unchecked Sendable {
        var pending: Set<String> = []
        var passes = 0

        var center: Reminders.Center {
            Reminders.Center(
                remove: { ids in
                    self.passes += 1
                    self.pending.subtract(ids)
                },
                add: { request in _ = self.pending.insert(request.identifier) }
            )
        }
    }

    /// Starting a feed timer plans no reminder; stopping it plans one. The
    /// first pass used to remove stale requests in a pending-list callback;
    /// answered after the second pass added `baby.feed`, it deleted it, and a
    /// later identical plan stops early, so nothing put it back. On the old
    /// code, with the callbacks held and answered after both passes, this
    /// ends with nothing pending.
    func testALatePendingAnswerKeepsTheNewerFeedReminder() throws {
        let fake = RecordingCenter()
        Reminders.centerOverride = fake.center
        defer { Reminders.centerOverride = nil }
        Reminders.feedInterval = .threeHours
        Reminders.forgetLastSchedule()
        let now = Date.now
        var feeding = NowSummary()
        feeding.lastFeedAt = now.addingTimeInterval(-60)
        feeding.runningFeedStart = now.addingTimeInterval(-60)
        var fed = feeding
        fed.runningFeedStart = nil

        Reminders.reschedule(summary: feeding, birthDate: nil, now: now)
        XCTAssertEqual(Reminders.lastPlanned?.map(\.id), [], "precondition: no reminder while a feed runs")
        XCTAssertEqual(fake.passes, 1, "precondition: the first plan reached the center")
        Reminders.reschedule(summary: fed, birthDate: nil, now: now)
        XCTAssertEqual(Reminders.lastPlanned?.map(\.id), [Reminders.feedID], "precondition: the stopped feed plans one")
        XCTAssertEqual(fake.passes, 2, "precondition: the second plan reached the center")
        Reminders.reschedule(summary: fed, birthDate: nil, now: now)
        XCTAssertEqual(fake.pending, [Reminders.feedID])
    }

    /// Stale requests are cleared by identifier, so every one a plan can
    /// schedule must be in the list a new plan clears.
    func testEveryPlannedReminderIsOneANewPlanClears() throws {
        let now = Date.now
        let birth = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let visit = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: now))
        var fed = NowSummary()
        fed.lastFeedAt = now
        let planned = [Reminders.feedReminder(for: fed, interval: .threeHours, now: now)].compactMap { $0 }
            + Reminders.checkupReminders(birthDate: birth, nextCheckup: nil, now: now)
            + Reminders.checkupReminders(birthDate: nil, nextCheckup: visit, now: now)
        XCTAssertEqual(planned.count, 5, "precondition: the feed reminder, three newborn visits and an entered date")
        XCTAssertEqual(Set(planned.map(\.id)), Set(Reminders.ownedIDs))
    }
}
