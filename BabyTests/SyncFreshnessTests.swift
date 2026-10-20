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
        XCTAssertNil(CloudSyncProblem(CKError(.networkUnavailable)), "CloudKit retries a dropped connection itself")
        XCTAssertNil(CloudSyncProblem(nil))
    }

    func testTheSyncLineSaysJustNowForTheFirstMinute() {
        let now = Date.now
        XCTAssertEqual(SettingsView.syncedPhrase(now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertNotEqual(SettingsView.syncedPhrase(now.addingTimeInterval(-600), now: now), "just now")
    }
}
