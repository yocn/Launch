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
}
