import XCTest
@testable import Baby

final class UnfoldedSplitTests: XCTestCase {
    func testCompactWidthNeverSplits() {
        // The folded Duo's outer display and every ordinary iPhone.
        XCTAssertNil(UnfoldedSplit.make(width: 466, isRegularWidth: false, fold: nil))
        XCTAssertNil(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 466...485))
    }

    func testRegularWidthTooNarrowForTwoPanesStaysSingle() {
        // The unfolded Duo held in portrait.
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
    }

    func testPanesMeetTheFoldEdges() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 466...485)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 466, secondaryX: 485, secondaryWidth: 466))
    }

    func testNoFoldSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testFoldLeavingANarrowPaneFallsBackToEvenSplit() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 300...320)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testEveryPaneIsAtLeastTheMinimumWidth() {
        for width in stride(from: CGFloat(720), through: 1400, by: 7) {
            guard let split = UnfoldedSplit.make(width: width, isRegularWidth: true, fold: nil) else {
                return XCTFail("no split at \(width)")
            }
            XCTAssertGreaterThanOrEqual(split.primaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertGreaterThanOrEqual(split.secondaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertEqual(split.secondaryX + split.secondaryWidth, width)
        }
    }

    @MainActor func testDockedPaneEndsAboveTheCapsule() {
        // The unfolded Duo's leading pane: its page must stop where the capsule's
        // reservation starts, above the capsule's own top edge.
        let pane = CGRect(x: 0, y: 0, width: 466, height: 615)
        let reservationTop = pane.maxY - AppTheme.bottomNavigationReservedHeight
        let capsuleTop = reservationTop + AppTheme.hairSpacing
        let docked = CapsuleDock(isDocked: true).path(in: pane).boundingRect
        XCTAssertEqual(docked.maxY, reservationTop)
        XCTAssertLessThanOrEqual(docked.maxY, capsuleTop)
        // Folded, the page runs on beneath the floating capsule.
        let floating = CapsuleDock(isDocked: false).path(in: pane).boundingRect
        XCTAssertGreaterThan(floating.maxY, pane.maxY)
    }
}
