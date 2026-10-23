import SwiftUI
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

    func testEachPaneDropsTheSideInsetAtTheFold() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 466...485)
        XCTAssertEqual(split?.foldEdge(isSecondary: false), .trailing)
        XCTAssertEqual(split?.foldEdge(isSecondary: true), .leading)
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
}
