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

    func testAveragesSkipTodayBecauseTodayIsStillBeingFilledIn() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        for _ in 0..<8 { store.log(.feed, at: yesterday) }
        store.log(.feed) // today, one feed so far
        let report = report(daysBack: 1)
        XCTAssertEqual(report.totalFeeds, 9)
        XCTAssertEqual(report.averageFeedsPerDay, 8, accuracy: 0.001)
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
