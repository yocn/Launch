import LaunchCore
import XCTest
@testable import LaunchApp

final class ArrangeOptionsTests: XCTestCase {
    func testDefaultsFillAllPages() {
        let options = ArrangeOptions()

        XCTAssertEqual(
            options.arrangement(currentPage: 1, pageCount: 3),
            LayoutArrangement(pages: [0, 1, 2], fillsGaps: true, ungroupsFolders: false)
        )
    }

    func testSinglePageCannotFill() {
        var options = ArrangeOptions()
        options.scope = .currentPage

        XCTAssertFalse(options.canFillGaps(currentPage: 1, pageCount: 3))
        XCTAssertNil(options.arrangement(currentPage: 1, pageCount: 3))

        options.ungroupsFolders = true
        XCTAssertEqual(
            options.arrangement(currentPage: 1, pageCount: 3),
            LayoutArrangement(pages: [1], fillsGaps: false, ungroupsFolders: true)
        )
    }

    func testChosenPagesAreSortedAndBounded() {
        var options = ArrangeOptions()
        options.scope = .chosenPages
        XCTAssertNil(options.arrangement(currentPage: 0, pageCount: 3))

        options.chosenPages = [2, 0, 7]
        XCTAssertEqual(options.pages(currentPage: 0, pageCount: 3), [0, 2])
        XCTAssertEqual(
            options.arrangement(currentPage: 0, pageCount: 3),
            LayoutArrangement(pages: [0, 2], fillsGaps: true, ungroupsFolders: false)
        )
    }

    func testGroupingAloneWorksOnSinglePage() {
        var options = ArrangeOptions()
        options.scope = .currentPage
        options.groupsByCategory = true

        XCTAssertEqual(
            options.arrangement(currentPage: 2, pageCount: 3),
            LayoutArrangement(pages: [2], fillsGaps: false, ungroupsFolders: false, groupsByCategory: true)
        )
    }

    func testNeedsAtLeastOneRule() {
        var options = ArrangeOptions()
        options.fillsGaps = false

        XCTAssertNil(options.arrangement(currentPage: 0, pageCount: 3))
    }
}
