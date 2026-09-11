import XCTest
@testable import Baby

final class FormatTests: XCTestCase {
    func testAgoReadsLikeTheBrief() {
        let now = Date.now
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-12 * 60), now: now), "12m ago")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-(2 * 3600 + 14 * 60)), now: now), "2h 14m ago")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-(27 * 3600)), now: now), "1d 3h ago")
        XCTAssertEqual(Format.ago(now.addingTimeInterval(-(48 * 3600)), now: now), "2d ago")
    }

    func testNowSummaryLinesMatchTheBrief() {
        var summary = NowSummary()
        let now = Date.now
        summary.lastFeedAt = now.addingTimeInterval(-(2 * 3600 + 14 * 60))
        summary.lastFeedSide = .left
        summary.lastDiaperAt = now.addingTimeInterval(-48 * 60)
        summary.lastDiaperKind = .wet
        XCTAssertEqual(summary.feedLine(now: now), "Fed 2h 14m ago · Left")
        XCTAssertEqual(summary.diaperLine(now: now), "Last diaper 48m ago · Wet")
        XCTAssertNil(summary.sleepLine(now: now))
        XCTAssertEqual(NowSummary.empty.feedLine(now: now), "No feed logged yet")
    }

    func testWatchStoreReplaysAPendingTapOverAnOlderPhoneSummary() {
        var phone = NowSummary()
        phone.generatedAt = Date.now.addingTimeInterval(-600)
        phone.todayWet = 2
        let tap = WatchLogPayload(action: .log, kind: .wet, at: Date.now.addingTimeInterval(-60))
        let merged = phone.applying(tap)
        XCTAssertEqual(merged.todayWet, 3)
        XCTAssertEqual(merged.lastDiaperKind, .wet)
        XCTAssertEqual(merged.lastDiaperAt, tap.at)
        let sleep = merged.applying(WatchLogPayload(action: .startSleep, kind: .sleep))
        XCTAssertTrue(sleep.isSleeping)
    }
}
