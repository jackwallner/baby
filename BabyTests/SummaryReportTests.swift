import CoreData
import XCTest
@testable import Baby

@MainActor
final class SummaryReportTests: XCTestCase {
    private var persistence: Persistence!
    private var store: EventStore!
    private var calendar = Calendar.current

    override func setUp() async throws {
        persistence = Persistence(cloudKit: false, inMemory: true)
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.activeChildID)
        // A UI test can leave a button off in the shared defaults, which would
        // hide its entries from these reports.
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.hiddenKinds)
        store = EventStore(persistence: persistence)
        store.createChild(name: "Nora", birthDate: calendar.date(byAdding: .day, value: -4, to: .now))
    }

    private func report(daysBack: Int = 3) -> SummaryReport {
        let start = calendar.date(byAdding: .day, value: -daysBack, to: .now)!
        return SummaryReport.make(
            childName: store.child?.displayName ?? "",
            birthDate: store.child?.birthDate,
            events: store.events,
            from: start,
            to: .now
        )
    }

    func testOneRowPerDayIncludingDaysWithNothingLogged() {
        store.log(.wet, at: calendar.date(byAdding: .day, value: -3, to: .now)!)
        let report = report()
        XCTAssertEqual(report.dayCount, 4, "three days back plus today, inclusive")
        XCTAssertEqual(report.days.first?.wet, 1)
        XCTAssertEqual(report.days[1].feeds, 0, "a blank day is information at a well visit")
        XCTAssertEqual(report.days.first?.dayOfLife, 2)
    }

    private func day(_ back: Int, hour: Int) -> Date {
        let start = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: .now))!
        return start.addingTimeInterval(TimeInterval(hour) * 3600)
    }

    func testAveragesSkipTodayBecauseTodayIsStillBeingFilledIn() {
        store.log(.feed, at: day(2, hour: 9)) // the day logging began
        for hour in 0..<8 { store.log(.feed, at: day(1, hour: hour * 2)) }
        store.log(.feed) // today, one feed so far
        let report = report(daysBack: 2)
        XCTAssertEqual(report.totalFeeds, 10)
        XCTAssertEqual(report.averageFeedsPerDay, 8, accuracy: 0.001)
        XCTAssertEqual(report.days.last?.partial, .today)
        XCTAssertEqual(report.completeDays.map(\.feeds), [8])
    }

    func testTheDayLoggingBeganIsPartialBecauseItStartedMidDay() {
        let firstEntry = day(2, hour: 16)
        store.log(.wet, at: firstEntry)
        store.log(.feed, at: day(2, hour: 18))
        for hour in [1, 4, 7, 10, 13, 16, 19, 22] { store.log(.feed, at: day(1, hour: hour)) }
        let report = report(daysBack: 2)
        XCTAssertEqual(report.days[0].partial, .loggingBegan(firstEntry))
        XCTAssertEqual(report.days[0].partial?.label, "from \(Format.time(firstEntry))")
        XCTAssertNil(report.days[1].partial)
        XCTAssertEqual(report.averageFeedsPerDay, 8, accuracy: 0.001, "two hours of day one do not make a day")
        XCTAssertEqual(report.partialDays.count, 2, "the first day and today")
        XCTAssertTrue(report.averagesNote.hasPrefix("Averages use 1 complete day."), report.averagesNote)
        XCTAssertTrue(report.averagesNote.contains("logging began \(Format.time(firstEntry))"), report.averagesNote)
        XCTAssertTrue(report.averagesNote.contains("today (so far)"), report.averagesNote)
    }

    func testADayWithNothingLoggedIsShownButNotAveraged() {
        store.log(.feed, at: day(4, hour: 8)) // logging began
        for hour in [2, 8, 14, 20] { store.log(.feed, at: day(3, hour: hour)) }
        // Nobody logged two days ago.
        for hour in [1, 7, 13, 19, 23] { store.log(.feed, at: day(1, hour: hour)) }
        let report = report(daysBack: 4)
        XCTAssertEqual(report.days[2].partial, .nothingLogged)
        XCTAssertEqual(report.days[2].feeds, 0, "the blank row still prints")
        XCTAssertEqual(report.completeDays.count, 2)
        XCTAssertEqual(report.averageFeedsPerDay, 4.5, accuracy: 0.001)
        XCTAssertEqual(report.lowestDay(\.feeds)?.feeds, 4, "the lowest day is a logged day, not the blank one")
    }

    func testAGapAcrossAnUnloggedDayIsNotAFeedGap() {
        store.log(.feed, at: day(3, hour: 22))
        // Nobody logged two days ago.
        store.log(.feed, at: day(1, hour: 1))
        store.log(.feed, at: day(1, hour: 6))
        let report = report(daysBack: 3)
        XCTAssertEqual(report.days[2].longestFeedGapSeconds, 5 * 3600, accuracy: 1, "the 27-hour gap is a logging hole, not a feed gap")
        XCTAssertEqual(report.longestFeedGapSeconds, 5 * 3600, accuracy: 1)
    }

    func testWithoutACompleteDayTheAveragesUseEveryLoggedDay() {
        for _ in 0..<8 { store.log(.feed, at: day(1, hour: 12)) }
        store.log(.feed)
        let report = report(daysBack: 1)
        XCTAssertFalse(report.hasCompleteDays)
        XCTAssertEqual(report.averageFeedsPerDay, 4.5, accuracy: 0.001)
        XCTAssertTrue(report.partialDays.isEmpty, "nothing is 'left out' when every day is in")
        XCTAssertEqual(report.averagesNote, "No complete day yet, so averages use every day logged so far.")
    }

    func testBottleFiguresReadPerDayAndPerBottle() {
        store.log(.feed, at: day(3, hour: 9))
        for (hour, amount) in [(6, 60.0), (12, 90.0), (18, 60.0)] {
            let feed = store.log(.feed, side: .bottle, at: day(2, hour: hour))
            feed?.amount = amount
        }
        store.log(.feed, at: day(1, hour: 10)) // breastfed day: no bottle, not in the bottle average
        store.save()
        let report = report(daysBack: 3)
        XCTAssertEqual(report.days[1].bottleFeeds, 3)
        XCTAssertEqual(report.averageBottleMillilitresPerDay, 210, accuracy: 0.001)
        XCTAssertEqual(report.averageBottleMillilitresPerFeed, 70, accuracy: 0.001)
    }

    func testLongestStretchIsTheLongestSingleSleepNotTheDayTotal() {
        let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now))!
        let short = day.addingTimeInterval(3600)
        store.startTimed(.sleep, at: short)
        store.stopRunning(.sleep, at: short.addingTimeInterval(45 * 60))
        let long = day.addingTimeInterval(6 * 3600)
        store.startTimed(.sleep, at: long)
        store.stopRunning(.sleep, at: long.addingTimeInterval(3 * 3600))
        let report = report(daysBack: 1)
        let yesterday = report.days[0]
        XCTAssertEqual(Int(yesterday.sleepSeconds / 60), 225)
        XCTAssertEqual(Int(yesterday.longestSleepSeconds / 3600), 3)
        XCTAssertEqual(Int(report.longestSleepSeconds / 3600), 3)
    }

    func testWeightChangeReadsFromTheFirstAndLastWeighIn() {
        let first = calendar.date(byAdding: .day, value: -3, to: .now)!
        let a = store.log(.weight, at: first)
        a?.amount = 3180
        let b = store.log(.weight, at: calendar.date(byAdding: .day, value: -1, to: .now)!)
        b?.amount = 3390
        store.save()
        let report = report()
        XCTAssertEqual(report.firstWeight, 3180)
        XCTAssertEqual(report.latestWeight, 3390)
        XCTAssertEqual(report.weightChangeGrams, 210)
        XCTAssertEqual(report.weightChangePercent!, 6.6, accuracy: 0.05)
        XCTAssertTrue(report.weightChangeDescription!.contains("(+6.6%) since"), report.weightChangeDescription!)
    }

    func testASingleWeighInHasNoChangeToReport() {
        store.log(.weight)?.amount = 3300
        store.save()
        XCTAssertNil(report().weightChangePercent)
        XCTAssertEqual(report().weightChangeDescription, "One weigh-in")
    }

    func testLongestFeedGapReachesBackToTheFeedBeforeTheRange() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now))!
        store.log(.feed, at: yesterday.addingTimeInterval(-2 * 3600)) // 10pm the night before the range
        store.log(.feed, at: yesterday.addingTimeInterval(2 * 3600))
        store.log(.feed, at: yesterday.addingTimeInterval(5 * 3600))
        let report = report(daysBack: 1)
        XCTAssertEqual(report.days[0].longestFeedGapSeconds, 4 * 3600, accuracy: 1)
        XCTAssertEqual(report.days[1].longestFeedGapSeconds, 0, "no feed today, so no gap to credit to it")
        XCTAssertEqual(report.longestFeedGapSeconds, 4 * 3600, accuracy: 1)
    }

    func testAmountsReadInThePediatriciansUnits() {
        XCTAssertEqual(Format.grams(3390, imperial: false), "3.39 kg")
        XCTAssertEqual(Format.grams(3390, imperial: true), "7 lb 7.5 oz")
        XCTAssertEqual(Format.grams(3629, imperial: true), "8 lb 0 oz")
        XCTAssertEqual(Format.gramsChange(210, imperial: false), "+210 g")
        XCTAssertEqual(Format.gramsChange(-210, imperial: true), "−7.5 oz")
        XCTAssertEqual(Format.millilitres(60, imperial: false), "60 ml")
        XCTAssertEqual(Format.millilitres(60, imperial: true), "2 oz")
        XCTAssertEqual(Format.millilitres(75, imperial: true), "2.5 oz")
    }

    func testCSVEscapesNotesAndKeepsOneRowPerEvent() {
        let event = store.log(.dirty)
        event?.note = "green, \"seedy\""
        event?.stool = .green
        store.save()
        store.log(.feed, side: .bottle)
        let csv = SummaryReport.csv(events: store.events, childName: "Nora")
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 3, "header plus two events")
        XCTAssertTrue(lines[0].hasPrefix("baby,date,time,kind,side"))
        XCTAssertTrue(csv.contains("\"green, \"\"seedy\"\"\""), "a note with a comma and quotes survives the round trip")
        XCTAssertTrue(csv.contains(",dirty,"))
        XCTAssertTrue(csv.contains(",feed,bottle,"))
    }

    func testTheSampleReportIsLabelledAndNeverEmpty() {
        let sample = SampleReport.make()
        XCTAssertEqual(sample.childName, "Example baby")
        XCTAssertEqual(sample.dayCount, 8)
        XCTAssertGreaterThan(sample.averageFeedsPerDay, 0)
        XCTAssertEqual(sample.completeDays.count, 7, "the example's today is partial, like a real one")
    }

    func testThePDFRendersAPageForBothTheSampleAndTheRealLog() {
        let sampleData = PDFReport.render(SampleReport.make(), isExample: true)
        XCTAssertGreaterThan(sampleData.count, 1000)
        XCTAssertNotNil(PDFReport.firstPageImage(sampleData, width: 300))
        store.log(.feed)
        let data = PDFReport.render(report())
        XCTAssertGreaterThan(data.count, 1000)
    }
}
