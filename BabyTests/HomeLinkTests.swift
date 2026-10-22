import XCTest
@testable import Baby

final class HomeLinkTests: XCTestCase {
    func testTabLinksOpenTheirTab() {
        XCTAssertEqual(HomeTab(link: URL(string: "babytracker://log")!), .log)
        XCTAssertEqual(HomeTab(link: URL(string: "babytracker://history")!), .history)
        XCTAssertEqual(HomeTab(link: URL(string: "babytracker://reports")!), .reports)
        XCTAssertEqual(HomeTab(link: URL(string: "babytracker://settings")!), .settings)
    }

    func testOtherLinksOpenNothing() {
        XCTAssertNil(HomeTab(link: URL(string: "babytracker://upgrade")!))
        XCTAssertNil(HomeTab(link: URL(string: "babywatch://log")!))
        XCTAssertNil(HomeTab(link: URL(string: "https://www.icloud.com/share/abc")!))
    }

    @MainActor
    func testTourStopsAreDebugRoutesWithTheirAnchors() {
        XCTAssertEqual(DuoTour.Stop(url: URL(string: "babytracker://tour/firstweeks")!), .firstWeeks)
        XCTAssertEqual(DuoTour.Stop(url: URL(string: "babytracker://tour/wet")!), .wet)
        XCTAssertNil(DuoTour.Stop(url: URL(string: "babytracker://tour/upgrade")!))
        // A tab link is not a tour stop.
        XCTAssertNil(DuoTour.Stop(url: URL(string: "babytracker://reports")!))
        XCTAssertEqual(DuoTour.Stop.reports.anchor, SummaryView.tourAnchor)
        XCTAssertEqual(DuoTour.Stop.firstWeeks.anchor, FirstWeeksView.tourAnchor)
        XCTAssertEqual(DuoTour.Stop.settings.anchor, SettingsView.tourAnchor)
        XCTAssertNil(DuoTour.Stop.log.anchor)
    }
}
