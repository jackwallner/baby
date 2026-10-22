import CloudKit
import CoreData
import XCTest
@testable import Baby

/// The widget saves to the log's files from its own process. The app's view
/// context never heard about those saves, so a row it already held kept its
/// old values: a sleep the widget ended still ran on Now, and a feed side
/// changed there stayed as it was, until the app was relaunched.
@MainActor
final class SyncFreshnessTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncFreshnessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        WidgetUndo.clear()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The app's store, and a second stack on the same files standing in for
    /// the widget extension, which writes under its own author.
    private func makeAppAndWidget() -> (EventStore, Persistence) {
        let app = EventStore(persistence: Persistence(cloudKit: false, directory: directory))
        app.createChild(name: "Nora", birthDate: nil)
        let widget = Persistence(cloudKit: false, directory: directory)
        widget.viewContext.transactionAuthor = "com.jackwallner.baby.widget"
        return (app, widget)
    }

    func testASleepTheWidgetEndsStopsRunningInTheOpenApp() throws {
        let (app, widget) = makeAppAndWidget()
        app.toggleSleep()
        XCTAssertNotNil(app.runningSleep)

        let context = widget.viewContext
        let child = try XCTUnwrap(widget.activeChild(in: context))
        for sleep in widget.runningEvents(.sleep, for: child, in: context) {
            sleep.endedAt = .now
        }
        XCTAssertTrue(widget.save(context))
        app.reload()

        XCTAssertNil(app.runningSleep, "the widget's Wake reaches the app without a relaunch")
        XCTAssertNil(app.summary.runningSleepStart)
    }

    func testAnEntryTheWidgetChangesOrRemovesShowsAsItIsNow() throws {
        let (app, widget) = makeAppAndWidget()
        app.log(.feed, side: .left)
        app.log(.wet)

        let context = widget.viewContext
        let child = try XCTUnwrap(widget.activeChild(in: context))
        let entries = widget.events(for: child, in: context)
        try XCTUnwrap(entries.first { $0.eventKind == .feed }).feedSide = .right
        context.delete(try XCTUnwrap(entries.first { $0.eventKind == .wet }))
        XCTAssertTrue(widget.save(context))
        app.reload()

        XCTAssertEqual(app.events.map(\.eventKind), [.feed])
        XCTAssertEqual(app.events.first?.feedSide, .right)
    }

    /// Every tap was followed by CloudKit's remote-change notices for its own
    /// save and export, and each one redrew every screen and reloaded the
    /// widgets and the Watch, a hitch just after the tap.
    func testARefreshThatFindsTheSameLogRedrawsNothing() {
        let (app, _) = makeAppAndWidget()
        app.log(.wet)
        let revision = app.revision
        app.refresh(force: false)
        XCTAssertEqual(app.revision, revision, "an export of this phone's own tap changes nothing on screen")
    }

    func testAPartnersEntryStillRedrawsOnARemoteRefresh() throws {
        let (app, widget) = makeAppAndWidget()
        let revision = app.revision
        let context = widget.viewContext
        let child = try XCTUnwrap(widget.activeChild(in: context))
        _ = widget.insert(kind: .wet, at: .now, side: nil, ended: nil, for: child, in: context)
        XCTAssertTrue(widget.save(context))
        app.refresh(force: false)
        XCTAssertGreaterThan(app.revision, revision)
        XCTAssertEqual(app.events.map(\.eventKind), [.wet])
    }

    /// A widget tap reaches the partner twice (the widget's own upload and
    /// the app's export) until the cleanup deletes one.
    func testATwoCopyEntryShowsAndDeletesAsOne() throws {
        let (app, widget) = makeAppAndWidget()
        let context = widget.viewContext
        let child = try XCTUnwrap(widget.activeChild(in: context))
        let id = UUID()
        for _ in 0..<2 {
            widget.insert(kind: .feed, at: .now, side: .left, ended: .now, for: child, in: context).id = id
        }
        XCTAssertTrue(widget.save(context))
        app.reload()
        XCTAssertEqual(app.events.count, 1)
        XCTAssertEqual(app.summary.todayFeeds, 1)

        app.delete(try XCTUnwrap(app.events.first))
        XCTAssertTrue(app.events.isEmpty, "the hidden copy does not take the deleted one's place")
    }

    func testOnlyOtherProcessesSavesAreMergedFromHistory() {
        let own = "com.jackwallner.baby"
        XCTAssertTrue(Persistence.isExternal("com.jackwallner.baby.widget", own: own))
        XCTAssertTrue(Persistence.isExternal(nil, own: own))
        XCTAssertFalse(Persistence.isExternal(own, own: own), "this process's saves merge already")
        XCTAssertTrue(
            Persistence.isExternal("NSCloudKitMirroringDelegate.import", own: own),
            "imports must merge even when the automatic main-queue merge has not run"
        )
    }

    func testOnlyFixableSyncFailuresAreShown() {
        XCTAssertEqual(CloudSyncProblem(CKError(.quotaExceeded)), .iCloudFull)
        XCTAssertEqual(CloudSyncProblem(CKError(.notAuthenticated)), .signedOut)
        let partial = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "a"): CKError(.quotaExceeded)],
        ])
        XCTAssertEqual(CloudSyncProblem(partial), .iCloudFull)
        XCTAssertEqual(
            CloudSyncProblem(NSError(domain: NSCocoaErrorDomain, code: CloudSyncProblem.noAccountCode)),
            .signedOut,
            "a phone with no iCloud account fails setup with a Cocoa error"
        )
        XCTAssertNil(CloudSyncProblem(CKError(.networkUnavailable)), "CloudKit retries a dropped connection itself")
        XCTAssertNil(CloudSyncProblem(nil))
    }

    private func syncState() -> CloudSyncState {
        let defaults = UserDefaults(suiteName: "SyncFreshnessTests-\(UUID().uuidString)")!
        return CloudSyncState(defaults: defaults)
    }

    func testDownloadsDoNotHideAFullICloud() {
        let sync = syncState()
        let start = Date.now
        sync.ended(.export, at: start, succeeded: false, error: CKError(.quotaExceeded))
        sync.ended(.import, at: start.addingTimeInterval(60), succeeded: true, error: nil)
        XCTAssertEqual(sync.problem, .iCloudFull, "the partner's entries still arrive while this phone's cannot leave")
        sync.ended(.export, at: start.addingTimeInterval(120), succeeded: true, error: nil)
        XCTAssertNil(sync.problem, "an upload proves there is room again")
    }

    func testSigningInClearsTheSignedOutLine() {
        let sync = syncState()
        sync.ended(.setup, at: .now, succeeded: false, error: NSError(domain: NSCocoaErrorDomain, code: CloudSyncProblem.noAccountCode))
        XCTAssertEqual(sync.problem, .signedOut)
        XCTAssertNil(sync.lastSynced, "a setup is not a sync")
        sync.ended(.setup, at: .now, succeeded: true, error: nil)
        XCTAssertNil(sync.problem)
    }

    func testTheSyncTimeMovesAtMostEveryHalfMinute() {
        let sync = syncState()
        let start = Date.now
        sync.ended(.import, at: start, succeeded: true, error: nil)
        sync.ended(.export, at: start.addingTimeInterval(5), succeeded: true, error: nil)
        XCTAssertEqual(sync.lastSynced, start, "a catching-up phone's dozens of events redraw nothing")
        sync.ended(.export, at: start.addingTimeInterval(40), succeeded: true, error: nil)
        XCTAssertEqual(sync.lastSynced, start.addingTimeInterval(40))
    }

    func testTheSyncLineSaysJustNowForTheFirstMinute() {
        let now = Date.now
        XCTAssertEqual(SettingsView.syncedPhrase(now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertNotEqual(SettingsView.syncedPhrase(now.addingTimeInterval(-600), now: now), "just now")
    }

    func testATapMergesTheWidgetSleepBeforeDecidingWhetherToWake() throws {
        let (app, widget) = makeAppAndWidget()
        let child = try XCTUnwrap(widget.activeChild(in: widget.viewContext))
        widget.insert(kind: .sleep, at: .now.addingTimeInterval(-300), for: child, in: widget.viewContext)
        XCTAssertTrue(widget.save(widget.viewContext))
        app.toggleSleep()
        XCTAssertNil(app.runningSleep, "a wake tap must not create a second sleep from a stale snapshot")
        XCTAssertEqual(app.events.filter { $0.eventKind == .sleep }.count, 1)
    }

    func testImportIsMergedBeforeTheScheduledMainQueueMergeRuns() throws {
        let (app, _) = makeAppAndWidget()
        let sleep = try XCTUnwrap(app.startTimed(.sleep, at: .now.addingTimeInterval(-300)))
        let id = sleep.objectID
        let background = app.persistence.newBackgroundContext()
        background.transactionAuthor = "NSCloudKitMirroringDelegate.import"
        try background.performAndWait {
            let remote = try XCTUnwrap(background.existingObject(with: id) as? LogEvent)
            remote.endedAt = .now
            try background.save()
        }
        app.refresh(force: false)
        XCTAssertNil(app.summary.runningSleepStart, "a completed import must not leave the Live Activity running")
    }

    func testConcurrentAppAndWidgetEditsPreserveDifferentFields() throws {
        let (app, widget) = makeAppAndWidget()
        let feed = try XCTUnwrap(app.startTimed(.feed, side: .left, at: .now.addingTimeInterval(-300)))
        let child = try XCTUnwrap(widget.activeChild(in: widget.viewContext))
        let other = try XCTUnwrap(widget.events(for: child, in: widget.viewContext).first)
        feed.note = "from the app"
        other.endedAt = .now
        XCTAssertTrue(widget.save(widget.viewContext))
        XCTAssertTrue(app.save())
        XCTAssertEqual(app.events.first?.note, "from the app")
        XCTAssertNotNil(app.events.first?.endedAt)
    }

    func testBackgroundCleanupEditsMergeBeforeAutomaticDelivery() throws {
        let (app, _) = makeAppAndWidget()
        let feed = try XCTUnwrap(app.startTimed(.feed, side: .left))
        let id = feed.objectID
        let context = app.persistence.newBackgroundContext()
        try context.performAndWait {
            let changed = try XCTUnwrap(context.existingObject(with: id) as? LogEvent)
            changed.feedSide = .right
            try context.save()
        }
        app.refresh(force: false)
        XCTAssertEqual(app.summary.runningSides, [.right])
    }
}
