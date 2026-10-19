import CoreGraphics
import XCTest
@testable import LaunchApp

final class LauncherHomeLayoutTests: XCTestCase {
    private let mainScreen = CGSize(width: 1512, height: 982)

    func testDefaultGridMatchesReferenceCapacity() {
        XCTAssertEqual(LauncherHomeLayout.columnCount, 7)
        XCTAssertEqual(LauncherHomeLayout.rowCount, 5)
        XCTAssertEqual(LauncherHomeLayout.pageCapacity, 35)
    }

    func testReferenceScreenUsesCanvasMetrics() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen)

        XCTAssertEqual(layout.sizeScale, 1)
        XCTAssertEqual(layout.contentSize, mainScreen)
        XCTAssertEqual(layout.iconSide, 88)
    }

    func testOtherScreensScaleReferenceLayoutUniformly() {
        let larger = LauncherHomeLayout(
            screenSize: CGSize(width: 1920, height: 1080),
            referenceSize: mainScreen
        )
        let smaller = LauncherHomeLayout(
            screenSize: CGSize(width: 1504, height: 846),
            referenceSize: mainScreen
        )

        XCTAssertEqual(larger.sizeScale, 1080 / 982, accuracy: 0.0001)
        XCTAssertEqual(larger.contentSize.width, 1512 * 1080 / 982, accuracy: 0.0001)
        XCTAssertEqual(larger.contentSize.height, 1080, accuracy: 0.0001)
        XCTAssertEqual(smaller.sizeScale, 846 / 982, accuracy: 0.0001)
        let ratio = larger.sizeScale / smaller.sizeScale
        XCTAssertEqual(larger.iconSide / smaller.iconSide, ratio, accuracy: 0.0001)
        XCTAssertEqual(larger.columnSpacing / smaller.columnSpacing, ratio, accuracy: 0.0001)
        XCTAssertEqual(larger.labelFontSize / smaller.labelFontSize, ratio, accuracy: 0.0001)
    }

    func testAllRowsFitOnEveryScreen() {
        let references = [
            mainScreen,
            CGSize(width: 1440, height: 900),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1280, height: 1024),
            CGSize(width: 2560, height: 1440),
        ]
        let screens = references + [
            CGSize(width: 1504, height: 846),
            CGSize(width: 3440, height: 1440),
            CGSize(width: 1024, height: 768),
        ]
        for reference in references {
            for screen in screens {
                let layout = LauncherHomeLayout(screenSize: screen, referenceSize: reference)
                let usedHeight = layout.topInset
                    + layout.searchBarHeight
                    + layout.searchToGrid
                    + layout.gridHeight
                    + layout.pageDotSize
                    + layout.bottomInset
                let context = "\(reference) -> \(screen)"

                XCTAssertLessThanOrEqual(usedHeight, layout.contentSize.height, context)
                XCTAssertLessThanOrEqual(layout.contentSize.width, screen.width + 0.0001, context)
                XCTAssertLessThanOrEqual(layout.contentSize.height, screen.height + 0.0001, context)
                XCTAssertGreaterThan(layout.columnSpacing, 0, context)
            }
        }
    }

    func testGridHeightHoldsEveryRow() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen)
        let rows = CGFloat(LauncherHomeLayout.rowCount)

        XCTAssertEqual(layout.tileHeight, 141)
        XCTAssertEqual(
            layout.gridHeight,
            layout.tileHeight * rows + layout.rowSpacing * (rows - 1),
            accuracy: 0.0001
        )
    }

    func testColumnsFillContentWidth() {
        let layout = LauncherHomeLayout(
            screenSize: CGSize(width: 1920, height: 1080),
            referenceSize: mainScreen
        )
        let columns = CGFloat(LauncherHomeLayout.columnCount)
        let usedWidth = layout.horizontalInset * 2
            + layout.tileWidth * columns
            + layout.columnSpacing * (columns - 1)

        XCTAssertEqual(usedWidth, layout.contentSize.width, accuracy: 0.0001)
    }
}
