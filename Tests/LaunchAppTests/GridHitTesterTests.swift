import CoreGraphics
import XCTest
@testable import LaunchApp

final class GridHitTesterTests: XCTestCase {
    private let layout = LauncherHomeLayout(
        screenSize: LauncherHomeLayout.canvasSize,
        referenceSize: LauncherHomeLayout.canvasSize
    )

    private var tester: GridHitTester {
        GridHitTester(layout: layout, frame: CGRect(x: 0, y: 135, width: 1512, height: layout.gridHeight))
    }

    func testTileRectFollowsGridGeometry() {
        let rect = tester.tileRect(8)

        XCTAssertEqual(rect.minX, layout.horizontalInset + layout.tileWidth + layout.columnSpacing, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 135 + layout.tileHeight + layout.rowSpacing, accuracy: 0.001)
        XCTAssertEqual(rect.size, CGSize(width: layout.tileWidth, height: layout.tileHeight))
    }

    func testIconCenterIsMergeZoneAndSidesAreInsertZones() {
        let rect = tester.tileRect(2)
        let iconY = rect.minY + layout.tilePadding + layout.iconSide / 2

        XCTAssertEqual(tester.hit(CGPoint(x: rect.midX, y: iconY), itemCount: 10), .item(2, .center))
        XCTAssertEqual(tester.hit(CGPoint(x: rect.minX + 4, y: rect.maxY - 6), itemCount: 10), .item(2, .leading))
        XCTAssertEqual(tester.hit(CGPoint(x: rect.maxX - 4, y: rect.maxY - 6), itemCount: 10), .item(2, .trailing))
    }

    func testGapBetweenColumnsBelongsToNearestTile() {
        let left = tester.tileRect(0)
        let right = tester.tileRect(1)

        XCTAssertEqual(tester.hit(CGPoint(x: left.maxX + 5, y: left.maxY - 6), itemCount: 10), .item(0, .trailing))
        XCTAssertEqual(tester.hit(CGPoint(x: right.minX - 5, y: right.maxY - 6), itemCount: 10), .item(1, .leading))
    }

    func testPointPastLastItemMeansPageEnd() {
        let rect = tester.tileRect(5)

        XCTAssertEqual(tester.hit(CGPoint(x: rect.midX, y: rect.midY), itemCount: 3), .end)
    }

    func testEdgesAndOutside() {
        XCTAssertEqual(tester.hit(CGPoint(x: 20, y: 300), itemCount: 10), .edge(.previous))
        XCTAssertEqual(tester.hit(CGPoint(x: 1500, y: 300), itemCount: 10), .edge(.next))
        XCTAssertEqual(tester.hit(CGPoint(x: 700, y: 60), itemCount: 10), .outside)
    }

    func testTileIndexOnlyInsideTiles() {
        let rect = tester.tileRect(1)

        XCTAssertEqual(tester.tileIndex(at: CGPoint(x: rect.midX, y: rect.midY), itemCount: 3), 1)
        XCTAssertNil(tester.tileIndex(at: CGPoint(x: rect.minX - 10, y: rect.midY), itemCount: 3))
        XCTAssertNil(tester.tileIndex(at: CGPoint(x: rect.midX, y: rect.midY), itemCount: 1))
    }
}
