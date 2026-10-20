import AppKit
import CoreGraphics
import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelSettingsTests: XCTestCase {
    private let layout = LauncherHomeLayout(
        screenSize: LauncherHomeLayout.canvasSize,
        referenceSize: LauncherHomeLayout.canvasSize
    )

    private var gridFrame: CGRect {
        CGRect(x: 0, y: 135, width: layout.contentSize.width, height: layout.gridHeight)
    }

    private func center(_ index: Int) -> CGPoint {
        let rect = GridHitTester(layout: layout, frame: gridFrame).tileRect(index)
        return CGPoint(x: rect.midX, y: rect.minY + layout.tilePadding + layout.iconSide / 2)
    }

    @MainActor
    private func makeModel(apps: [CatalogApp]) -> LauncherModel {
        let model = LauncherModel(apps: apps)
        model.updateLayout(LauncherPagination.pages(apps.map(ResolvedItem.app), capacity: LauncherHomeLayout.pageCapacity))
        model.canEditLayout = true
        model.updateHomeLayout(layout)
        model.updateGridFrame(gridFrame)
        return model
    }

    @MainActor
    func testReopenKeepsPageUnlessFirstPageIsAsked() {
        let model = makeModel(apps: makeApps(count: 40))
        model.selectPage(1)

        model.prepareForPresentation()
        XCTAssertEqual(model.currentPage, 1)

        model.reopensAtFirstPage = true
        model.prepareForPresentation()
        XCTAssertEqual(model.currentPage, 0)
    }

    @MainActor
    func testSearchCanIncludeHiddenApps() {
        let apps = makeApps(count: 3)
        let model = makeModel(apps: apps)
        model.updateHiddenApps([apps[1]])
        model.setQuery("App")

        XCTAssertEqual(model.hiddenApps, [apps[1]])
        XCTAssertEqual(model.results, [apps[0], apps[2]])

        model.showsHiddenAppsInSearch = true
        XCTAssertEqual(model.results, apps)
        XCTAssertTrue(model.isHiddenApp(apps[1]))
        XCTAssertFalse(model.isHiddenApp(apps[0]))
        XCTAssertEqual(
            model.contextMenu(at: center(1)),
            .app(AppMenuContent(app: apps[1], canOpen: true, canEdit: true, canUninstall: false, isHidden: true))
        )
    }

    @MainActor
    func testBlankPointGivesMainMenu() {
        let model = makeModel(apps: makeApps(count: 3))

        XCTAssertEqual(model.contextMenu(at: CGPoint(x: 5, y: 5)), .main)
    }

    @MainActor
    func testWallpaperIsStoredForView() {
        let model = makeModel(apps: [])
        let wallpaper = Wallpaper(image: NSImage(size: CGSize(width: 1, height: 1)), fill: .aspectFill, fillColor: nil)

        model.updateWallpaper(wallpaper)
        XCTAssertTrue(model.wallpaper?.image === wallpaper.image)

        model.updateWallpaper(nil)
        XCTAssertNil(model.wallpaper)
    }
}
