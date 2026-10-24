import XCTest
@testable import Baby

final class RemindersTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func summary(fedMinutesAgo minutes: Double?, sides: [FeedSide] = [], recent: [RecentEntry] = []) -> NowSummary {
        var summary = NowSummary()
        summary.childName = "Hazel"
        summary.lastFeedAt = minutes.map { now.addingTimeInterval(-$0 * 60) }
        summary.setLastFeedSides(sides)
        summary.recent = recent
        return summary
    }

    private func feed(_ minutesAgo: Double, _ sides: [FeedSide]) -> RecentEntry {
        RecentEntry(id: UUID(), kind: .feed, at: now.addingTimeInterval(-minutesAgo * 60), endedAt: nil, sides: sides)
    }

    // MARK: - Next side

    func testNextSideIsTheOtherBreastFromWhereTheLastFeedEnded() {
        XCTAssertEqual(summary(fedMinutesAgo: 30, sides: [.left]).nextBreastSide, .right)
        XCTAssertEqual(summary(fedMinutesAgo: 30, sides: [.right, .left]).nextBreastSide, .right, "ended on left")
        XCTAssertEqual(summary(fedMinutesAgo: 30, sides: [.left]).nextSideLine, "Start on Right")
    }

    func testABottleInBetweenKeepsTheBreastFromTheFeedBefore() {
        let s = summary(fedMinutesAgo: 20, sides: [.bottle], recent: [feed(20, [.bottle]), feed(200, [.right])])
        XCTAssertEqual(s.nextBreastSide, .left)
    }

    func testNoBreastNamedMeansNoHint() {
        XCTAssertNil(summary(fedMinutesAgo: 20, sides: [.bottle], recent: [feed(20, [.bottle])]).nextBreastSide)
        XCTAssertNil(summary(fedMinutesAgo: 20, sides: []).nextSideLine)
        XCTAssertNil(summary(fedMinutesAgo: nil).nextSideLine)
    }

    func testAFeedWithNoSideYetGivesNoHint() {
        // 8:00 Left, then an 11:00 Feed tap with no side picked: Right would
        // be a guess from the older feed.
        let s = summary(fedMinutesAgo: 10, sides: [], recent: [feed(10, []), feed(190, [.left])])
        XCTAssertNil(s.nextBreastSide)
    }

    func testTheHintHidesWhileAFeedRuns() {
        var s = summary(fedMinutesAgo: 5, sides: [.left])
        s.runningFeedStart = now.addingTimeInterval(-300)
        XCTAssertNil(s.nextSideLine)
    }

    func testWidgetsLeaveTheSideToHome() {
        let lines = summary(fedMinutesAgo: 30, sides: [.left]).supportingLines(now: now)
        XCTAssertFalse(lines.contains("Start on Right"))
    }

    // MARK: - Feed reminder

    func testFeedReminderIsDueTheChosenGapAfterTheFeedStarted() throws {
        let planned = try XCTUnwrap(Reminders.feedReminder(for: summary(fedMinutesAgo: 30, sides: [.left]), interval: .twoAndAHalfHours, now: now))
        XCTAssertEqual(planned.id, Reminders.feedID)
        XCTAssertEqual(planned.date, now.addingTimeInterval(120 * 60))
        XCTAssertEqual(planned.title, "2½ hours since Hazel's last feed")
        XCTAssertTrue(planned.body.hasSuffix("Start on Right."), planned.body)
        XCTAssertNil(planned.route)
    }

    func testNoFeedReminderWhenOffBeforeAFeedWhileFeedingOrOnceDue() {
        XCTAssertNil(Reminders.feedReminder(for: summary(fedMinutesAgo: 30), interval: .off, now: now))
        XCTAssertNil(Reminders.feedReminder(for: summary(fedMinutesAgo: nil), interval: .threeHours, now: now))
        XCTAssertNil(Reminders.feedReminder(for: summary(fedMinutesAgo: 200), interval: .threeHours, now: now))
        var feeding = summary(fedMinutesAgo: 5)
        feeding.runningFeedStart = now.addingTimeInterval(-300)
        XCTAssertNil(Reminders.feedReminder(for: feeding, interval: .threeHours, now: now))
    }

    func testFeedReminderWithoutASideSaysOnlyTheTime() throws {
        let planned = try XCTUnwrap(Reminders.feedReminder(for: summary(fedMinutesAgo: 10, sides: [.bottle]), interval: .threeHours, now: now))
        XCTAssertFalse(planned.body.contains("Start on"))
    }

    // MARK: - Checkups

    func testAnEnteredCheckupGetsOneNoteAtSevenTheEveningBefore() throws {
        let visit = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: now))
        let planned = Reminders.checkupReminders(birthDate: nil, nextCheckup: visit, now: now, calendar: calendar)
        XCTAssertEqual(planned.count, 1)
        let note = try XCTUnwrap(planned.first)
        XCTAssertEqual(note.route, Reminders.checkupRoute)
        XCTAssertEqual(calendar.component(.hour, from: note.date), Reminders.checkupEveningHour)
        XCTAssertEqual(calendar.dateComponents([.day], from: calendar.startOfDay(for: note.date), to: calendar.startOfDay(for: visit)).day, 1)
    }

    func testWithoutADateTheUsualNewbornVisitsCountFromBirth() throws {
        let birth = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let planned = Reminders.checkupReminders(birthDate: birth, nextCheckup: nil, now: now, calendar: calendar)
        XCTAssertEqual(planned.map(\.id), Reminders.typicalCheckupDays.map { Reminders.checkupPrefix + "day\($0)" })
        for (note, day) in zip(planned, Reminders.typicalCheckupDays) {
            let visit = DateHelpers.date(forDayOfLife: day, birthDate: birth, calendar: calendar)
            XCTAssertLessThan(note.date, visit)
            XCTAssertEqual(calendar.component(.hour, from: note.date), Reminders.checkupEveningHour)
        }
    }

    func testPastVisitsAndUnknownBirthDatesScheduleNothing() throws {
        let oldBirth = try XCTUnwrap(calendar.date(byAdding: .day, value: -40, to: now))
        XCTAssertTrue(Reminders.checkupReminders(birthDate: oldBirth, nextCheckup: nil, now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(Reminders.checkupReminders(birthDate: nil, nextCheckup: nil, now: now, calendar: calendar).isEmpty)
        let midMonth = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: now))
        XCTAssertEqual(Reminders.checkupReminders(birthDate: midMonth, nextCheckup: nil, now: now, calendar: calendar).map(\.id), [Reminders.checkupPrefix + "day14", Reminders.checkupPrefix + "day30"])
    }

    // MARK: - Stored choices

    func testChoicesRoundTripAndDefaultOff() throws {
        let suite = "RemindersTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        Reminders.defaultsOverride = defaults
        defer {
            Reminders.defaultsOverride = nil
            defaults.removePersistentDomain(forName: suite)
        }
        XCTAssertEqual(Reminders.feedInterval, .off)
        XCTAssertFalse(Reminders.checkupRemindersOn)
        XCTAssertNil(Reminders.feedingStyle)
        Reminders.feedInterval = .threeHours
        Reminders.feedingStyle = .bottle
        Reminders.nextCheckup = now
        XCTAssertEqual(Reminders.feedInterval, .threeHours)
        XCTAssertEqual(Reminders.feedingStyle?.suggestedInterval, .threeHours)
        XCTAssertEqual(Reminders.nextCheckup, now)
        Reminders.nextCheckup = nil
        XCTAssertNil(Reminders.nextCheckup)
    }

    // Build 66 aborted on a notification tap: the async delegate answered
    // UIKit from a background thread.
    func testANotificationTapIsAnsweredOnTheMainThread() {
        let answered = expectation(description: "completion handler called")
        DispatchQueue.global(qos: .userInitiated).async {
            NotificationRouter.handleTap(route: nil) {
                XCTAssertTrue(Thread.isMainThread)
                answered.fulfill()
            }
        }
        wait(for: [answered], timeout: 2)
    }
}
