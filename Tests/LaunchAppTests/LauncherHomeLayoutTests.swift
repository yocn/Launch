import CoreGraphics
import XCTest
@testable import LaunchApp

final class LauncherHomeLayoutTests: XCTestCase {
    private let mainScreen = CGSize(width: 1512, height: 982)

    func testDefaultGridKeepsReferenceMetrics() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen)

        XCTAssertEqual(layout.grid, .default)
        XCTAssertEqual(layout.fitScale, 1)
        XCTAssertEqual(layout.iconSide, 88)
        XCTAssertEqual(layout.tileHeight, 141)
        XCTAssertEqual(layout.rowSpacing, 17, accuracy: 0.0001)
        XCTAssertEqual(layout.gridHeight, 773, accuracy: 0.0001)
        XCTAssertEqual(layout.folderRowSpacing, 17, accuracy: 0.0001)
    }

    func testHiddenNamesGiveLabelSpaceToIcon() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen, showsNames: false)

        XCTAssertEqual(layout.iconSide, 117)
        XCTAssertEqual(layout.labelHeight, 0)
        XCTAssertEqual(layout.tileHeight, 141)
        XCTAssertEqual(layout.tileWidth, 141)
        XCTAssertEqual(layout.rowSpacing, 17, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(layout.columnSpacing, 17)
    }

    func testHiddenNamesStillFitManyColumns() {
        let grid = GridSize(columns: 10, rows: 8)
        for screen in [mainScreen, CGSize(width: 1280, height: 1024), CGSize(width: 1024, height: 768)] {
            let hidden = LauncherHomeLayout(screenSize: screen, referenceSize: screen, grid: grid, showsNames: false)
            let shown = LauncherHomeLayout(screenSize: screen, referenceSize: screen, grid: grid)

            XCTAssertGreaterThanOrEqual(hidden.columnSpacing, 17 * hidden.sizeScale * hidden.fitScale - 0.0001, "\(screen)")
            XCTAssertEqual(hidden.tileHeight * 8 + hidden.rowSpacing * 7, hidden.gridHeight, accuracy: 0.0001, "\(screen)")
            XCTAssertGreaterThan(hidden.iconSide, shown.iconSide, "\(screen)")
        }
    }

    func testWindowAreaIsCenteredFractionOfScreen() {
        XCTAssertEqual(LauncherHomeLayout.windowArea(for: mainScreen), CGSize(width: 1512 * 0.7, height: 982 * 0.75))
        let layout = LauncherHomeLayout(screenSize: LauncherHomeLayout.windowArea(for: mainScreen), referenceSize: mainScreen)

        XCTAssertEqual(layout.sizeScale, 0.7, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(layout.contentSize.height, 982 * 0.75)
    }

    func testFewerRowsKeepIconSizeAndSpreadRows() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen, grid: GridSize(columns: 5, rows: 3))

        XCTAssertEqual(layout.iconSide, 88)
        XCTAssertEqual(layout.gridHeight, 773, accuracy: 0.0001)
        XCTAssertEqual(layout.rowSpacing, (773 - 141 * 3) / 2, accuracy: 0.0001)
        XCTAssertEqual(layout.folderRowSpacing, 17, accuracy: 0.0001)
        let usedWidth = layout.horizontalInset * 2 + layout.tileWidth * 5 + layout.columnSpacing * 4
        XCTAssertEqual(usedWidth, layout.contentSize.width, accuracy: 0.0001)
    }

    func testMoreRowsAndColumnsShrinkTilesToFit() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen, grid: GridSize(columns: 10, rows: 8))

        XCTAssertLessThan(layout.fitScale, 1)
        XCTAssertEqual(layout.iconSide, 88 * layout.fitScale, accuracy: 0.0001)
        XCTAssertEqual(layout.gridHeight, 773, accuracy: 0.0001)
        XCTAssertEqual(layout.tileHeight * 8 + layout.rowSpacing * 7, layout.gridHeight, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(layout.rowSpacing, 17 * layout.fitScale - 0.0001)
        XCTAssertEqual(layout.folderRowSpacing, 17 * layout.fitScale, accuracy: 0.0001)
    }

    func testManyColumnsKeepMinimumColumnSpacing() {
        for screen in [mainScreen, CGSize(width: 1280, height: 1024), CGSize(width: 1024, height: 768)] {
            let layout = LauncherHomeLayout(screenSize: screen, referenceSize: screen, grid: GridSize(columns: 10, rows: 5))

            XCTAssertGreaterThanOrEqual(layout.columnSpacing, 17 * layout.sizeScale * layout.fitScale - 0.0001, "\(screen)")
        }
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
                for grid in [GridSize(columns: 4, rows: 3), GridSize.default, GridSize(columns: 10, rows: 8)] {
                let layout = LauncherHomeLayout(screenSize: screen, referenceSize: reference, grid: grid)
                let usedHeight = layout.topInset
                    + layout.searchBarHeight
                    + layout.searchToGrid
                    + layout.gridHeight
                    + layout.pageDotSize
                    + layout.bottomInset
                let context = "\(reference) -> \(screen) \(grid)"

                XCTAssertLessThanOrEqual(usedHeight, layout.contentSize.height, context)
                XCTAssertLessThanOrEqual(layout.contentSize.width, screen.width + 0.0001, context)
                XCTAssertLessThanOrEqual(layout.contentSize.height, screen.height + 0.0001, context)
                XCTAssertGreaterThan(layout.columnSpacing, 0, context)
                XCTAssertGreaterThan(layout.rowSpacing, 0, context)
                }
            }
        }
    }

    func testGridHeightHoldsEveryRow() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen)
        let rows = CGFloat(layout.grid.rows)

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
        let columns = CGFloat(layout.grid.columns)
        let usedWidth = layout.horizontalInset * 2
            + layout.tileWidth * columns
            + layout.columnSpacing * (columns - 1)

        XCTAssertEqual(usedWidth, layout.contentSize.width, accuracy: 0.0001)
    }

    func testFolderPreviewFitsInsideIcon() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen)

        XCTAssertLessThan(
            layout.folderPreviewIconSide * 3 + layout.folderPreviewSpacing * 2,
            layout.iconSide
        )
    }

    func testFolderRowCountCapsAtFiveRows() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen)

        XCTAssertEqual(layout.folderRowCount(memberCount: 0), 1)
        XCTAssertEqual(layout.folderRowCount(memberCount: 8), 2)
        XCTAssertEqual(layout.folderRowCount(memberCount: 29), 5)
        XCTAssertEqual(layout.folderRowCount(memberCount: 40), 5)
    }

    func testFolderFollowsGridColumnsAndRows() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen, grid: GridSize(columns: 4, rows: 3))

        XCTAssertEqual(layout.folderRowCount(memberCount: 5), 2)
        XCTAssertEqual(layout.folderRowCount(memberCount: 20), 3)
        XCTAssertEqual(layout.folderGridHeight(memberCount: 20), layout.tileHeight * 3 + layout.folderRowSpacing * 2, accuracy: 0.0001)
    }

    func testFullFolderPanelFitsOnEveryScreen() {
        for screen in [mainScreen, CGSize(width: 1920, height: 1080), CGSize(width: 1504, height: 846)] {
            let layout = LauncherHomeLayout(screenSize: screen, referenceSize: mainScreen)
            let usedHeight = layout.folderTitleHeight
                + layout.folderTitleSpacing
                + layout.folderGridHeight(memberCount: 35)
                + layout.folderPanelPadding * 2

            XCTAssertLessThanOrEqual(usedHeight, layout.contentSize.height, "\(screen)")
        }
    }

    func testFolderPanelExtendsBeyondGridColumns() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen)

        XCTAssertEqual(layout.horizontalInset - layout.folderPanelOutset, 94.08, accuracy: 0.01)
    }
}
