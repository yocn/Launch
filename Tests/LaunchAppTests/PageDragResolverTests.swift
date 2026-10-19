import CoreGraphics
import XCTest
@testable import LaunchApp

final class PageDragResolverTests: XCTestCase {
    func testMiddlePageFollowsTranslation() {
        XCTAssertEqual(PageDragResolver.displayOffset(translation: -200, currentPage: 1, pageCount: 3), -200)
        XCTAssertEqual(PageDragResolver.displayOffset(translation: 200, currentPage: 1, pageCount: 3), 200)
    }

    func testEdgesResistDragging() {
        XCTAssertEqual(PageDragResolver.displayOffset(translation: 200, currentPage: 0, pageCount: 3), 60, accuracy: 0.001)
        XCTAssertEqual(PageDragResolver.displayOffset(translation: -200, currentPage: 2, pageCount: 3), -60, accuracy: 0.001)
        XCTAssertEqual(PageDragResolver.displayOffset(translation: -200, currentPage: 0, pageCount: 1), -60, accuracy: 0.001)
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
