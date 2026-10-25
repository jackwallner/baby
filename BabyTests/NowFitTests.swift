import XCTest
@testable import Baby

final class NowFitTests: XCTestCase {
    /// Now's fixed part on the iPhone Duo, roomy: status card, time row,
    /// button gaps, totals, Add an older entry and two section gaps.
    private let duoFixed: CGFloat = 371
    private let link: CGFloat = 44
    /// A 60 pt strip whose hour labels take 16 of it.
    private let strip = StripMetrics(full: 60, labels: 16)

    private func make(fixed: CGFloat, available: CGFloat, drawn: StripStyle = .hidden) -> NowFit {
        NowFit.make(fixed: fixed, available: available, rows: 3, strip: strip, drawn: drawn, olderLink: link)
    }

    func testRoomyPhoneSharesTheRestAmongTheButtons() {
        let fit = make(fixed: 400, available: 700, drawn: .full)
        XCTAssertFalse(fit.isTight)
        XCTAssertEqual(fit.strip, .full)
        XCTAssertEqual(fit.buttonHeight, 100)
        XCTAssertEqual(fit.slack, 0)
    }

    func testTallPhoneCapsTheButtonsAndPutsTheRestAboveTheTotals() {
        let fit = make(fixed: 400, available: 900, drawn: .full)
        XCTAssertEqual(fit.buttonHeight, AppTheme.maxLogButtonHeight)
        XCTAssertEqual(fit.slack, 900 - 400 - AppTheme.maxLogButtonHeight * 3)
    }

    func testShortPhoneShedsTheHourLabelsBeforeTheStrip() {
        // Full strip misses the floor by a point; without labels it fits.
        let fit = make(fixed: 500, available: 500 + AppTheme.minLogButtonHeight * 3 - 1, drawn: .full)
        XCTAssertEqual(fit.strip, .compact)
        XCTAssertFalse(fit.isTight)
    }

    func testDuoPaneGoesTightAndFitsAboveTheCapsule() {
        let fit = make(fixed: duoFixed, available: 471)
        XCTAssertTrue(fit.isTight)
        XCTAssertGreaterThanOrEqual(fit.buttonHeight, AppTheme.tightLogButtonHeight)
        // Everything above Add an older entry ends inside the page.
        let drawnAboveLink = duoFixed - NowFit.tightSaving - link
        XCTAssertLessThanOrEqual(drawnAboveLink + fit.buttonHeight * 3 + fit.slack, 471)
    }

    func testTightNeverGrowsTheButtonsPastTheRoomyFloor() {
        // One point short of fitting roomy at the floor.
        let fit = make(fixed: duoFixed, available: duoFixed + AppTheme.minLogButtonHeight * 3 - 1)
        XCTAssertTrue(fit.isTight)
        XCTAssertEqual(fit.buttonHeight, AppTheme.minLogButtonHeight)
        XCTAssertGreaterThan(fit.slack, 0)
    }

    func testPastTheTightFloorThePageScrolls() {
        let fit = make(fixed: duoFixed, available: 380)
        XCTAssertTrue(fit.isTight)
        XCTAssertEqual(fit.buttonHeight, AppTheme.tightLogButtonHeight)
        XCTAssertEqual(fit.slack, 0)
    }

    func testMeasuringATightPageRefitsToTheSameFit() {
        // The page as drawn under a tight fit must not flip it back to roomy.
        let fit = make(fixed: duoFixed, available: 471)
        let drawn = duoFixed - NowFit.tightSaving + fit.slack + fit.buttonHeight * 3
        let measured = fit.fixed(drawn: drawn, rows: 3)
        XCTAssertEqual(measured, duoFixed)
        XCTAssertEqual(make(fixed: measured, available: 471), fit)
    }
}
