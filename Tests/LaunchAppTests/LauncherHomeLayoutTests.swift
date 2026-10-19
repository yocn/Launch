import CoreGraphics
import XCTest
@testable import LaunchApp

final class LauncherHomeLayoutTests: XCTestCase {
    func testDefaultGridMatchesReferenceCapacity() {
        XCTAssertEqual(LauncherHomeLayout.columnCount, 7)
        XCTAssertEqual(LauncherHomeLayout.rowCount, 5)
        XCTAssertEqual(LauncherHomeLayout.pageCapacity, 35)
    }

    func testIconSizeScalesWithinUsableBounds() {
        XCTAssertEqual(
            LauncherHomeLayout.iconSideLength(
                for: CGSize(width: 3024, height: 1920)
            ),
            160
        )
        XCTAssertEqual(
            LauncherHomeLayout.iconSideLength(
                for: CGSize(width: 1280, height: 800)
            ),
            88
        )
    }

    func testGridHeightLeavesRoomForSearchAndPageIndicator() {
        XCTAssertEqual(
            LauncherHomeLayout.gridHeight(for: CGSize(width: 3024, height: 1920)),
            1_344
        )
    }

    func testRowSpacingCapsAtReferenceDensity() {
        XCTAssertEqual(
            LauncherHomeLayout.rowSpacing(
                for: CGSize(width: 3_024, height: 1_920),
                iconSide: 160
            ),
            48
        )
    }
}
