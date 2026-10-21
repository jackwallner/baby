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

    func testOnlyOtherProcessesSavesAreMergedFromHistory() {
        let own = "com.jackwallner.baby"
        XCTAssertTrue(Persistence.isExternal("com.jackwallner.baby.widget", own: own))
        XCTAssertTrue(Persistence.isExternal(nil, own: own))
        XCTAssertFalse(Persistence.isExternal(own, own: own), "this process's saves merge already")
        XCTAssertFalse(
            Persistence.isExternal("NSCloudKitMirroringDelegate.import", own: own),
            "CloudKit's imports merge already"
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
}
