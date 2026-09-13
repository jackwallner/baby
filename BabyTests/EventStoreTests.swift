import CoreData
import XCTest
@testable import Baby

private enum InjectedSaveError: Error {
    case failure
}

private final class SaveController {
    var callCount = 0
    var failureOnCall: Int?

    func save(_ context: NSManagedObjectContext) throws {
        callCount += 1
        if callCount == failureOnCall { throw InjectedSaveError.failure }
        try context.save()
    }
}

@MainActor
final class EventStoreTests: XCTestCase {
    private var persistence: Persistence!
    private var store: EventStore!

    override func setUp() async throws {
        persistence = Persistence(cloudKit: false, inMemory: true)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.appliedWatchActions)
        store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: Calendar.current.date(byAdding: .day, value: -2, to: .now))
    }

    func testOneTapFeedLogsNowWithTheSuggestedSide() {
        XCTAssertEqual(store.summary.suggestedSide, .left, "first feed suggests the left side")
        store.log(.feed)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.summary.lastFeedSide, .left)
        XCTAssertEqual(store.summary.suggestedSide, .right, "the other side comes next")
        XCTAssertFalse(store.events[0].isRunning, "a one-tap feed is instant, not a timer")
        store.log(.feed, side: .bottle)
        XCTAssertEqual(store.summary.suggestedSide, .bottle, "bottle stays bottle")
    }

    func testDiapersCountTowardTodayAndTheLastDiaperLine() {
        store.log(.wet)
        store.log(.dirty)
        store.log(.wet)
        XCTAssertEqual(store.summary.todayWet, 2)
        XCTAssertEqual(store.summary.todayDirty, 1)
        XCTAssertEqual(store.summary.lastDiaperKind, .wet)
        XCTAssertTrue(store.summary.diaperLine().hasPrefix("Last diaper just now"))
    }

    func testSleepTogglesBetweenRunningAndEnded() {
        store.toggleSleep(at: Date.now.addingTimeInterval(-3600))
        XCTAssertNotNil(store.runningSleep)
        XCTAssertTrue(store.summary.isSleeping)
        XCTAssertEqual(store.summary.sleepLine(), "Asleep 1h")
        store.toggleSleep()
        XCTAssertNil(store.runningSleep)
        XCTAssertEqual(Int((store.events[0].duration ?? 0) / 60), 60)
        XCTAssertEqual(Int(store.tally(on: .now).sleepSeconds / 60), 60)
    }

    func testStartingASecondTimedFeedEndsTheFirst() {
        store.startTimed(.feed, side: .left, at: Date.now.addingTimeInterval(-600))
        store.startTimed(.feed, side: .right)
        XCTAssertEqual(store.events.filter { $0.isRunning }.count, 1)
        XCTAssertEqual(store.runningFeed?.feedSide, .right)
        XCTAssertTrue(store.summary.feedLine().hasPrefix("Feeding · Right"))
    }

    func testUndoRemovesTheLastTapAndReopensAStop() {
        store.log(.wet)
        XCTAssertNotNil(store.lastLogged)
        store.undoLast()
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertNil(store.lastLogged)

        store.toggleSleep(at: Date.now.addingTimeInterval(-1200))
        store.toggleSleep()
        XCTAssertNil(store.runningSleep)
        store.undoLast()
        XCTAssertNotNil(store.runningSleep, "undoing the wake reopens the sleep")
    }

    func testWatchPayloadsApplyOnceEvenWhenRedelivered() {
        let payload = WatchLogPayload(action: .log, kind: .dirty, at: .now)
        store.apply(payload)
        store.apply(payload)
        XCTAssertEqual(store.events.count, 1)
        let start = WatchLogPayload(action: .startSleep, kind: .sleep, at: Date.now.addingTimeInterval(-300))
        store.apply(start)
        store.apply(start)
        XCTAssertEqual(store.events.filter { $0.eventKind == .sleep }.count, 1)
        store.apply(WatchLogPayload(action: .stopSleep, kind: .sleep))
        XCTAssertNil(store.runningSleep)
    }

    func testWatchPayloadStaysWithTheProfileItCameFrom() throws {
        let first = try XCTUnwrap(store.child)
        store.createChild(name: "Other baby", birthDate: nil)
        let second = try XCTUnwrap(store.child)
        store.setActive(second)

        let payload = WatchLogPayload(action: .log, kind: .wet, at: .now, childID: first.id)
        store.apply(payload)

        XCTAssertEqual(store.child?.id, second.id)
        XCTAssertTrue(store.events.isEmpty, "a queued tap for another profile must not appear in the active profile")
        XCTAssertEqual(persistence.events(for: first, in: persistence.viewContext).count, 1)
    }

    func testFailedConfiguredLogRollsBackWithoutLeavingAnEvent() {
        let controller = SaveController()
        let persistence = Persistence(
            cloudKit: false,
            inMemory: true,
            saveOperation: { try controller.save($0) }
        )
        let store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: nil)
        controller.failureOnCall = 2

        let event = store.log(.dirty, at: .now) { $0.note = "should not persist" }

        XCTAssertNil(event)
        XCTAssertTrue(store.events.isEmpty, "a failed atomic log must not leave a blank or partial row")
    }

    func testWatchActionIsAcknowledgedOnlyAfterSuccessfulSave() {
        let controller = SaveController()
        let persistence = Persistence(cloudKit: false, inMemory: true, saveOperation: { try controller.save($0) })
        let store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: nil)
        controller.failureOnCall = controller.callCount + 1
        let payload = WatchLogPayload(action: .log, kind: .wet)

        XCTAssertFalse(store.apply(payload))
        XCTAssertTrue(store.events.isEmpty)
        controller.failureOnCall = nil
        XCTAssertTrue(store.apply(payload))
        XCTAssertTrue(store.apply(payload))
        XCTAssertEqual(store.events.count, 1)
    }

    func testRedeliveredWatchWakeDoesNotEndANewerSleep() throws {
        let firstStart = Date.now.addingTimeInterval(-120)
        store.startTimed(.sleep, at: firstStart)
        let wake = WatchLogPayload(action: .stopSleep, kind: .sleep, at: firstStart.addingTimeInterval(30))
        XCTAssertTrue(store.apply(wake))
        let second = try XCTUnwrap(store.startTimed(.sleep, at: firstStart.addingTimeInterval(60)))
        XCTAssertTrue(store.apply(wake))
        XCTAssertTrue(second.isRunning)
        // Even if the bounded receipt cache no longer contains the old stop,
        // its timestamp must not close a more recent timer.
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.appliedWatchActions)
        XCTAssertTrue(store.apply(wake))
        XCTAssertTrue(second.isRunning)
    }

    func testFailedTimerReplacementRestoresTheExistingTimer() throws {
        let controller = SaveController()
        let persistence = Persistence(
            cloudKit: false,
            inMemory: true,
            saveOperation: { try controller.save($0) }
        )
        let store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: nil)
        let oldStart = Date.now.addingTimeInterval(-600)
        store.startTimed(.sleep, at: oldStart)
        controller.failureOnCall = 3

        let replacement = store.startTimed(.sleep, at: .now)

        XCTAssertNil(replacement)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(try XCTUnwrap(store.runningSleep?.startedAt), oldStart)
    }

    func testFailedEditSaveRestoresThePersistedEvent() throws {
        let controller = SaveController()
        let persistence = Persistence(
            cloudKit: false,
            inMemory: true,
            saveOperation: { try controller.save($0) }
        )
        let store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: nil)
        let event = try XCTUnwrap(store.log(.wet))
        event.note = "not saved"
        controller.failureOnCall = 3

        XCTAssertFalse(store.save())
        XCTAssertNil(store.events.first?.note)
    }

    func testFailedDeleteKeepsTheEventForRetry() throws {
        let controller = SaveController()
        let persistence = Persistence(
            cloudKit: false,
            inMemory: true,
            saveOperation: { try controller.save($0) }
        )
        let store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: nil)
        _ = store.log(.wet)
        let event = try XCTUnwrap(store.events.first)
        controller.failureOnCall = 3

        XCTAssertFalse(store.delete(event))
        XCTAssertEqual(store.events.count, 1, "a failed delete must leave the row available for retry")
    }

    func testFailedUndoKeepsUndoAvailableForRetry() throws {
        let controller = SaveController()
        let persistence = Persistence(
            cloudKit: false,
            inMemory: true,
            saveOperation: { try controller.save($0) }
        )
        let store = EventStore(persistence: persistence)
        XCTAssertTrue(store.createChild(name: "Nora", birthDate: nil))
        _ = store.log(.wet)
        controller.failureOnCall = 3

        XCTAssertFalse(store.undoLast())
        XCTAssertNotNil(store.lastLogged, "a failed undo must remain available for retry")
        XCTAssertEqual(store.events.count, 1)

        controller.failureOnCall = nil
        XCTAssertTrue(store.undoLast())
        XCTAssertNil(store.lastLogged)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testFailedChildCreationDoesNotSelectARolledBackProfile() {
        let controller = SaveController()
        controller.failureOnCall = 1
        let persistence = Persistence(
            cloudKit: false,
            inMemory: true,
            saveOperation: { try controller.save($0) }
        )
        let store = EventStore(persistence: persistence)

        XCTAssertFalse(store.createChild(name: "Nora", birthDate: nil))
        XCTAssertNil(store.child)
        XCTAssertTrue(store.children.isEmpty)
    }

    func testFailedChildUpdateReportsFailureAndRestoresTheName() throws {
        let controller = SaveController()
        let persistence = Persistence(
            cloudKit: false,
            inMemory: true,
            saveOperation: { try controller.save($0) }
        )
        let store = EventStore(persistence: persistence)
        XCTAssertTrue(store.createChild(name: "Nora", birthDate: nil))
        let child = try XCTUnwrap(store.child)
        controller.failureOnCall = 2

        XCTAssertFalse(store.update(child: child, name: "Changed", birthDate: nil))
        XCTAssertEqual(store.child?.displayName, "Nora")
    }

    func testUndoOfBackdatedWakeReopensSleep() {
        let start = Date.now.addingTimeInterval(-7200)
        store.startTimed(.sleep, at: start)
        store.stopRunning(.sleep, at: start.addingTimeInterval(3600))
        store.undoLast()
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.runningSleep?.startedAt, start)
    }

    func testUndoOfNewEntryWithEditedDurationRemovesIt() {
        let start = Date.now.addingTimeInterval(-600)
        let entry = store.log(.feed, side: .left, at: start)!
        entry.endedAt = .now
        store.save()
        store.undoLast()
        XCTAssertTrue(store.events.isEmpty, "Undo must not turn an edited feed into a running timer")
    }

    func testRunningFeedIsTheLatestSideEvenWithAnEarlierFeed() {
        store.log(.feed, side: .left, at: Date.now.addingTimeInterval(-3600))
        store.startTimed(.feed, side: .right)
        XCTAssertEqual(store.summary.lastFeedSide, .right)
        XCTAssertEqual(store.summary.suggestedSide, .left)
    }

    func testTallyCountsByCalendarDayAndSplitsSleepAtMidnight() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        store.log(.wet, at: yesterday.addingTimeInterval(3600))
        store.log(.wet, at: today.addingTimeInterval(3600))
        store.startTimed(.sleep, at: yesterday.addingTimeInterval(23 * 3600))
        store.stopRunning(.sleep, at: today.addingTimeInterval(3600))
        XCTAssertEqual(store.tally(on: yesterday).wet, 1)
        XCTAssertEqual(store.tally(on: today).wet, 1)
        XCTAssertEqual(Int(store.tally(on: yesterday).sleepSeconds), 3600)
        XCTAssertEqual(Int(store.tally(on: today).sleepSeconds), 3600)
        XCTAssertEqual(store.eventsByDay.count, 2)
    }

    func testSummaryRoundTripsThroughTheAppGroup() {
        store.log(.feed, side: .right)
        store.log(.dirty)
        let loaded = NowSummary.load()
        XCTAssertEqual(loaded.lastFeedSide, .right)
        XCTAssertEqual(loaded.lastDiaperKind, .dirty)
        XCTAssertEqual(loaded.dayOfLife, 3)
    }
}
