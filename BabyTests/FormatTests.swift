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

    func testWatchHoldsASleepStopUntilItsStartIsConfirmed() {
        let start = WatchLogPayload(action: .startSleep, kind: .sleep)
        let wet = WatchLogPayload(action: .log, kind: .wet)
        let stop = WatchLogPayload(action: .stopSleep, kind: .sleep)
        XCTAssertEqual(WatchLogPayload.sendable(from: [start, wet, stop]), [start, wet])
        XCTAssertEqual(WatchLogPayload.sendable(from: [wet, stop]), [wet, stop])
    }

    func testWatchReplayUsesEventIDsAndCurrentDayInsteadOfGenerationTime() {
        let now = Date.now
        var phone = NowSummary()
        phone.generatedAt = now
        phone.todayWet = 2
        let tap = WatchLogPayload(
            action: .log,
            kind: .wet,
            at: now.addingTimeInterval(-60)
        )

        let merged = phone.applyingPending([tap], now: now)
        XCTAssertEqual(merged.todayWet, 3)
        XCTAssertTrue(merged.knownEventIDs?.contains(tap.id) == true)

        let acknowledged = merged.applyingPending([tap], now: now)
        XCTAssertEqual(acknowledged.todayWet, 3, "an acknowledged transfer must never be replayed twice")
    }

    func testWatchReplayResetsYesterdayTotalsAtMidnight() {
        let calendar = Calendar.current
        let now = Date.now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        var phone = NowSummary()
        phone.generatedAt = yesterday
        phone.todayWet = 4
        let tap = WatchLogPayload(action: .log, kind: .wet, at: now)

        let merged = phone.applyingPending([tap], calendar: calendar, now: now)

        XCTAssertEqual(merged.todayWet, 1, "a new day must not inherit yesterday's totals")
        XCTAssertEqual(merged.generatedAt, now)
    }

    func testWatchPayloadDecodesWithoutAProfileIDAndRoundTripsItWhenPresent() throws {
        let payload = WatchLogPayload(action: .log, kind: .wet, childID: UUID())
        let data = try JSONEncoder().encode(payload)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "childID")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let oldPayload = try JSONDecoder().decode(WatchLogPayload.self, from: oldData)
        XCTAssertNil(oldPayload.childID)

        let currentPayload = try XCTUnwrap(WatchLogPayload(userInfo: payload.dictionary))
        XCTAssertEqual(currentPayload.childID, payload.childID)
    }

    func testWatchReplayIgnoresATapForAnotherBaby() {
        let first = UUID()
        let second = UUID()
        var phone = NowSummary()
        phone.childID = first
        phone.todayWet = 2
        let tap = WatchLogPayload(action: .log, kind: .wet, childID: second)

        let merged = phone.applyingPending([tap])

        XCTAssertEqual(merged.todayWet, 2)
        XCTAssertFalse(merged.knownEventIDs?.contains(tap.id) == true)
    }

    func testWatchReplayAcknowledgementsStayBounded() {
        let now = Date.now
        var summary = NowSummary()
        summary.generatedAt = now

        for _ in 0...NowSummary.knownEventLimit {
            summary = summary.applying(WatchLogPayload(action: .log, kind: .wet), now: now)
        }

        XCTAssertEqual(summary.knownEventIDs?.count, NowSummary.knownEventLimit)
    }

    func testOlderWatchActionsDoNotReplaceNewerSummaryState() {
        let now = Date.now
        var summary = NowSummary()
        summary.generatedAt = now
        summary.lastFeedAt = now
        summary.lastFeedSide = .right
        summary.lastDiaperAt = now
        summary.lastDiaperKind = .wet
        summary.runningSleepStart = now

        let oldFeed = WatchLogPayload(action: .log, kind: .feed, side: .left, at: now.addingTimeInterval(-60))
        let oldDiaper = WatchLogPayload(action: .log, kind: .dirty, at: now.addingTimeInterval(-60))
        let oldStop = WatchLogPayload(action: .stopSleep, kind: .sleep, at: now.addingTimeInterval(-60))
        let merged = summary.applyingPending([oldFeed, oldDiaper, oldStop], now: now)

        XCTAssertEqual(merged.lastFeedAt, summary.lastFeedAt)
        XCTAssertEqual(merged.lastFeedSide, .right)
        XCTAssertEqual(merged.lastDiaperAt, summary.lastDiaperAt)
        XCTAssertEqual(merged.lastDiaperKind, .wet)
        XCTAssertTrue(merged.isSleeping, "an older stop must not end a newer running sleep")
    }
}
