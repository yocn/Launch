import XCTest
@testable import LaunchApp

final class GridNavigatorTests: XCTestCase {
    private func move(
        _ position: GridPosition?,
        _ direction: MoveDirection,
        page: Int = 0,
        sizes: [Int]
    ) -> GridPosition? {
        GridNavigator.move(from: position, direction: direction, currentPage: page, pageSizes: sizes, columns: 7)
    }

    func testFirstMoveSelectsFirstItemOfCurrentPage() {
        XCTAssertEqual(move(nil, .right, page: 1, sizes: [35, 10]), GridPosition(page: 1, index: 0))
        XCTAssertEqual(move(nil, .down, page: 0, sizes: [35, 10]), GridPosition(page: 0, index: 0))
    }

    func testRightWrapsRowsAndCrossesToNextPage() {
        XCTAssertEqual(move(GridPosition(page: 0, index: 6), .right, sizes: [35, 10]), GridPosition(page: 0, index: 7))
        XCTAssertEqual(move(GridPosition(page: 0, index: 34), .right, sizes: [35, 10]), GridPosition(page: 1, index: 0))
        XCTAssertEqual(move(GridPosition(page: 1, index: 9), .right, sizes: [35, 10]), GridPosition(page: 1, index: 9))
    }

    func testLeftCrossesToPreviousPageLastItem() {
        XCTAssertEqual(move(GridPosition(page: 1, index: 0), .left, sizes: [35, 10]), GridPosition(page: 0, index: 34))
        XCTAssertEqual(move(GridPosition(page: 0, index: 0), .left, sizes: [35, 10]), GridPosition(page: 0, index: 0))
    }

    func testDownMovesByColumnAndLandsOnLastItemOfShortRow() {
        XCTAssertEqual(move(GridPosition(page: 0, index: 1), .down, sizes: [10]), GridPosition(page: 0, index: 8))
        XCTAssertEqual(move(GridPosition(page: 0, index: 5), .down, sizes: [10]), GridPosition(page: 0, index: 9))
        XCTAssertEqual(move(GridPosition(page: 0, index: 8), .down, sizes: [10]), GridPosition(page: 0, index: 8))
    }

    func testUpStopsAtTopRow() {
        XCTAssertEqual(move(GridPosition(page: 0, index: 9), .up, sizes: [10]), GridPosition(page: 0, index: 2))
        XCTAssertEqual(move(GridPosition(page: 0, index: 3), .up, sizes: [10]), GridPosition(page: 0, index: 3))
    }

    func testVerticalMovesCrossPagesWhenScrolling() {
        func scroll(_ position: GridPosition, _ direction: MoveDirection, sizes: [Int]) -> GridPosition? {
            GridNavigator.move(from: position, direction: direction, currentPage: position.page, pageSizes: sizes, columns: 7, crossesPagesVertically: true)
        }

        XCTAssertEqual(scroll(GridPosition(page: 0, index: 30), .down, sizes: [35, 10]), GridPosition(page: 1, index: 2))
        XCTAssertEqual(scroll(GridPosition(page: 0, index: 33), .down, sizes: [35, 3]), GridPosition(page: 1, index: 2))
        XCTAssertEqual(scroll(GridPosition(page: 1, index: 3), .up, sizes: [17, 10]), GridPosition(page: 0, index: 16))
        XCTAssertEqual(scroll(GridPosition(page: 1, index: 1), .up, sizes: [17, 10]), GridPosition(page: 0, index: 15))
        XCTAssertEqual(scroll(GridPosition(page: 1, index: 9), .down, sizes: [35, 10]), GridPosition(page: 1, index: 9))
        XCTAssertEqual(move(GridPosition(page: 0, index: 30), .down, sizes: [35, 10]), GridPosition(page: 0, index: 30))
    }

    func testStalePositionRestartsOnCurrentPage() {
        XCTAssertEqual(move(GridPosition(page: 3, index: 0), .right, page: 0, sizes: [5]), GridPosition(page: 0, index: 0))
    }

    func testEmptyPagesKeepPosition() {
        XCTAssertNil(move(nil, .right, sizes: []))
    }
}
