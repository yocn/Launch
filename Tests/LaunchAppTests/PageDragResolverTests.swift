import CoreGraphics
import XCTest
@testable import LaunchApp

final class PageDragResolverTests: XCTestCase {
    private func offset(_ translation: CGFloat, page: Int, count: Int = 3) -> CGFloat {
        PageDragResolver.displayOffset(translation: translation, currentPage: page, pageCount: count, pageWidth: 1000)
    }

    func testMiddlePageFollowsTranslation() {
        XCTAssertEqual(offset(-200, page: 1), -200)
        XCTAssertEqual(offset(200, page: 1), 200)
    }

    func testEdgesResistDragging() {
        XCTAssertEqual(offset(200, page: 0), 60, accuracy: 0.001)
        XCTAssertEqual(offset(-200, page: 2), -60, accuracy: 0.001)
        XCTAssertEqual(offset(-200, page: 0, count: 1), -60, accuracy: 0.001)
    }

    func testDraggingPastOuterPagesFromMiddlePageIsResisted() {
        XCTAssertEqual(offset(1500, page: 1), 1150, accuracy: 0.001)
        XCTAssertEqual(offset(-2500, page: 1), -1450, accuracy: 0.001)
        XCTAssertEqual(offset(-1800, page: 0), -1800)
    }

    func testPredictedTranslationBeyondThresholdTurnsPage() {
        XCTAssertEqual(PageDragResolver.targetPage(currentPage: 0, pageCount: 3, predictedTranslation: -310, pageWidth: 1000), 1)
        XCTAssertEqual(PageDragResolver.targetPage(currentPage: 1, pageCount: 3, predictedTranslation: 310, pageWidth: 1000), 0)
    }

    func testShortDragSnapsBack() {
        XCTAssertEqual(PageDragResolver.targetPage(currentPage: 1, pageCount: 3, predictedTranslation: -200, pageWidth: 1000), 1)
        XCTAssertEqual(PageDragResolver.targetPage(currentPage: 1, pageCount: 3, predictedTranslation: 0, pageWidth: 0), 1)
    }

    func testEdgePagesDoNotTurnPastBounds() {
        XCTAssertEqual(PageDragResolver.targetPage(currentPage: 0, pageCount: 3, predictedTranslation: 900, pageWidth: 1000), 0)
        XCTAssertEqual(PageDragResolver.targetPage(currentPage: 2, pageCount: 3, predictedTranslation: -900, pageWidth: 1000), 2)
    }
}
