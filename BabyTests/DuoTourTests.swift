import XCTest
@testable import Baby

@MainActor
final class DuoTourTests: XCTestCase {
    func testStopComesFromItsLaunchArgument() {
        XCTAssertEqual(DuoTour.stop(in: ["Baby", "-SeedScreenshotData", "-DuoStop", "firstweeks"]), .firstWeeks)
        XCTAssertEqual(DuoTour.stop(in: ["-DuoStop", "night"]), .night)
        XCTAssertNil(DuoTour.stop(in: ["-DuoStop"]))
        XCTAssertNil(DuoTour.stop(in: ["-DuoStop", "upgrade"]))
        XCTAssertNil(DuoTour.stop(in: ["-SeedScreenshotData"]))
    }

    func testScrollingStopsEndOnTheirPageAnchor() {
        XCTAssertEqual(DuoTour.Stop.reports.anchor, SummaryView.tourAnchor)
        XCTAssertEqual(DuoTour.Stop.firstWeeks.anchor, FirstWeeksView.tourAnchor)
        XCTAssertEqual(DuoTour.Stop.settings.anchor, SettingsView.tourAnchor)
        XCTAssertNil(DuoTour.Stop.log.anchor)
        XCTAssertNil(DuoTour.Stop.night.anchor)
    }
}
