import XCTest
@testable import LaunchApp

final class GridSizeTests: XCTestCase {
    func testDefaultIsSevenByFive() {
        XCTAssertEqual(GridSize.default.columns, 7)
        XCTAssertEqual(GridSize.default.rows, 5)
        XCTAssertEqual(GridSize.default.capacity, 35)
    }

    func testClampsToSupportedRange() {
        XCTAssertEqual(GridSize(columns: 12, rows: 1), GridSize(columns: 10, rows: 3))
        XCTAssertEqual(GridSize(columns: 2, rows: 9), GridSize(columns: 4, rows: 8))
    }
}
