import XCTest
@testable import LaunchApp

final class LauncherPaginationTests: XCTestCase {
    func testPaginationSplitsItemsAtGridCapacity() {
        let pages = LauncherPagination.pages(
            Array(0 ... 35),
            capacity: 35
        )

        XCTAssertEqual(pages, [Array(0 ... 34), [35]])
    }

    func testPaginationClampsRequestedPageToAvailableRange() {
        XCTAssertEqual(
            LauncherPagination.normalizedPageIndex(4, pageCount: 2),
            1
        )
        XCTAssertEqual(
            LauncherPagination.normalizedPageIndex(-1, pageCount: 2),
            0
        )
        XCTAssertEqual(
            LauncherPagination.normalizedPageIndex(4, pageCount: 0),
            0
        )
    }
}
