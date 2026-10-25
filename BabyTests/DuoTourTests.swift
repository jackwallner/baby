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
}
