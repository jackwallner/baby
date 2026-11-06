import CoreData
import UserNotifications
import XCTest
@testable import Baby

/// State machine audit repro suite (2026-11-06). Failing tests are claims.
/// Each claim first asserts its own preconditions, and has a passing control.
@MainActor
final class StateMachineAuditRepro: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var persistence: Persistence!
    private var store: EventStore!
    private let center = UNUserNotificationCenter.current()

    override func setUp() async throws {
        suite = "StateMachineAuditRepro.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        Reminders.defaultsOverride = defaults
        Reminders.forgetLastSchedule()
        center.removeAllPendingNotificationRequests()
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.hiddenKinds)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.totalsWindow)
        WidgetUndo.clear()
        persistence = Persistence(cloudKit: false, inMemory: true)
        store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: Calendar.current.date(byAdding: .day, value: -2, to: .now))
    }

    override func tearDown() async throws {
        center.removeAllPendingNotificationRequests()
        Reminders.defaultsOverride = nil
        Reminders.forgetLastSchedule()
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: - Claim R1: foreground does not reach the block that reschedules reminders

    /// EventStore.publish() (EventStore.swift:359-363) runs `liveActivities.sync`
    /// and `Reminders.reschedule` in one `if !persistence.isStandingIn` block,
    /// so a counted `sync` is a counted reschedule opportunity. The simulator
    /// has no notification permission to grant, so pending requests cannot be
    /// read back; this seam is the same call site.
    @MainActor
    private final class CountingClient: LiveActivityClient {
        var reads = 0
        var areActivitiesEnabled: Bool { true }
        var activities: [LiveActivitySnapshot] { reads += 1; return [] }
        func end(_ id: String) async {}
        func update(_ id: String, to state: LiveActivityState) async {}
        func request(_ state: LiveActivityState) throws {}
    }

    private func countedStore() async throws -> (EventStore, CountingClient, LiveActivityService) {
        let client = CountingClient()
        let service = LiveActivityService(client: client)
        let counted = EventStore(persistence: persistence, liveActivities: service)
        XCTAssertNotNil(counted.child, "precondition: the baby from setUp is active")
        Reminders.feedInterval = .threeHours
        counted.log(.feed, at: .now.addingTimeInterval(-600))
        await service.waitForUpdates()
        XCTAssertFalse(persistence.isStandingIn, "precondition: the store is open")
        XCTAssertNotNil(counted.summary.lastFeedAt, "precondition: a feed is logged")
        XCTAssertFalse(counted.summary.isFeeding, "precondition: no timer runs")
        XCTAssertGreaterThan(client.reads, 0, "precondition: the feed tap reached publish()")
        return (counted, client, service)
    }

    /// Control: a summary change reaches publish() (and so reschedule).
    func testControlSummaryChangeReachesPublish() async throws {
        let (counted, client, service) = try await countedStore()
        Reminders.forgetLastSchedule()
        let before = client.reads
        counted.log(.wet)
        await service.waitForUpdates()
        XCTAssertGreaterThan(client.reads, before)
    }

    /// Claim: App.swift:112-113 runs `forgetLastSchedule()` then `reload()` on
    /// every foreground so "the next pass hands the plan over again"
    /// (Reminders.swift:203-204). With the summary unchanged, reload() never
    /// reaches publish(), so nothing is handed over.
    func testForegroundReloadReachesPublishSoTheForgottenPlanIsHandedOver() async throws {
        let (counted, client, service) = try await countedStore()
        Reminders.forgetLastSchedule()
        let before = client.reads
        // Exactly what BabyApp's scenePhase == .active handler does (minus the
        // direct LiveActivityService.shared.sync call, which has its own line).
        counted.reload()
        await service.waitForUpdates()
        XCTAssertGreaterThan(client.reads, before, "reload() with an unchanged summary never reached publish()")
    }

    // MARK: - Claim W1: Watch and widget totals under "Last 24 hours" never roll off

    private func summary(window: TotalsWindow, at now: Date) throws -> NowSummary {
        let child = try XCTUnwrap(store.child)
        let events = persistence.events(for: child, in: store.context)
        return NowSummary.make(child: child, events: events, now: now, window: window, tracked: .all, feedTypes: .all)
    }

    private func logTwoFeeds(base: Date) {
        store.log(.feed, at: base.addingTimeInterval(-20 * 3600))
        store.log(.feed, at: base.addingTimeInterval(-1 * 3600))
    }

    /// Control: a midnight day rolls over on the Watch and widgets.
    func testControlDayWindowClearsAtTheNextDay() throws {
        let base = Calendar.current.startOfDay(for: .now).addingTimeInterval(12 * 3600)
        logTwoFeeds(base: base)
        let made = try summary(window: .midnight, at: base)
        XCTAssertEqual(made.todayFeeds, 1, "precondition: only the feed after midnight counts")
        XCTAssertEqual(made.current(now: base.addingTimeInterval(13 * 3600)).todayFeeds, 0)
    }

    /// Claim: Settings > Daily totals > Last 24 hours promises the last 24
    /// hours. A summary made at `base` and read 10 hours later still counts
    /// the feed that is now 30 hours old.
    func testLast24HoursDropsAFeedOnceItIsOlderThanADay() throws {
        let base = Date.now
        logTwoFeeds(base: base)
        let made = try summary(window: .last24Hours, at: base)
        XCTAssertEqual(made.todayFeeds, 2, "precondition: both feeds are inside 24 hours when made")
        let later = base.addingTimeInterval(10 * 3600)
        // Truth at `later`: the feed 20 hours before base is 30 hours old.
        let truth = try summary(window: .last24Hours, at: later)
        XCTAssertEqual(truth.todayFeeds, 1, "precondition: a fresh summary counts one")
        XCTAssertEqual(made.current(now: later).todayFeeds, 1)
    }
}
