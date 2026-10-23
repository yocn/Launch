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
    private func makeModel(apps: [LaunchItem]) -> LauncherModel {
        let model = LauncherModel(apps: apps)
        model.updateLayout(LauncherPagination.pages(apps.map(ResolvedItem.item), capacity: GridSize.default.capacity))
        model.canEditLayout = true
        model.updateHomeLayout(layout)
        model.updateGridFrame(gridFrame)
        return model
    }

    @MainActor
    func testGridChangeRepaginatesAndMovesByNewColumns() {
        let model = makeModel(apps: makeLaunchItems(count: 20))
        XCTAssertEqual(model.pages.map(\.count), [20])

        model.updateGrid(GridSize(columns: 4, rows: 3))

        XCTAssertEqual(model.grid.capacity, 12)
        XCTAssertEqual(model.pages.map(\.count), [12, 8])
        model.moveSelection(.right)
        XCTAssertEqual(model.selectedIndex, 0)
        model.moveSelection(.down)
        XCTAssertEqual(model.selectedIndex, 4)
    }

    @MainActor
    func testSortedDisplayKeepsLayoutAndBlocksEditing() {
        let apps = ["Zed", "Alpha", "Mid"].map { name in
            LaunchItem(identity: AppIdentity(bundleIdentifier: "com.example.\(name)", path: "/Applications/\(name).app"), displayName: name)
        }
        let folder = ResolvedFolder(id: "f", name: "Folder", items: [apps[1], apps[0]])
        let model = LauncherModel(apps: apps)
        model.updateLayout([[.item(apps[0]), .folder(folder)], [.item(apps[2])]])
        model.canEditLayout = true

        model.updateDisplaySort(DisplaySort(field: .name, sortsFolderContents: true))

        XCTAssertEqual(model.pages, [[.folder(ResolvedFolder(id: "f", name: "Folder", items: [apps[1], apps[0]])), .item(apps[2]), .item(apps[0])]])
        XCTAssertFalse(model.canDragItems)
        XCTAssertFalse(model.mainMenu.canSelectAll)
        model.showFolder(id: "f")
        XCTAssertEqual(model.openFolder?.items, [apps[1], apps[0]])
        model.closeFolder()

        model.notifyBlockedDrag()
        XCTAssertEqual(model.hint, "仅在自定义排序时可以拖动调整顺序")

        model.updateDisplaySort(DisplaySort())
        XCTAssertEqual(model.pages, [[.item(apps[0]), .folder(folder)], [.item(apps[2])]])
        XCTAssertTrue(model.canDragItems)
    }

    @MainActor
    func testBlockedDragHintOnlyForSorting() {
        let model = makeModel(apps: makeLaunchItems(count: 3))
        model.notifyBlockedDrag()

        XCTAssertNil(model.hint)
    }

    @MainActor
    func testDatesReorderDateSort() {
        let apps = makeLaunchItems(count: 3)
        let model = makeModel(apps: apps)
        model.updateDisplaySort(DisplaySort(field: .lastUsed, descending: true))

        model.updateAppDates([
            apps[2].identity.stableKey: AppDates(lastUsed: Date(timeIntervalSince1970: 10)),
            apps[0].identity.stableKey: AppDates(lastUsed: Date(timeIntervalSince1970: 5)),
        ])

        XCTAssertEqual(model.pages, [[.item(apps[2]), .item(apps[0]), .item(apps[1])]])
    }

    @MainActor
    func testShrinkingGridClampsCurrentPage() {
        let model = makeModel(apps: makeLaunchItems(count: 20))
        model.updateGrid(GridSize(columns: 4, rows: 3))
        model.selectPage(1)

        model.updateGrid(.default)

        XCTAssertEqual(model.pages.map(\.count), [20])
        XCTAssertEqual(model.currentPage, 0)
    }

    @MainActor
    func testReopenKeepsPageUnlessFirstPageIsAsked() {
        let model = makeModel(apps: makeLaunchItems(count: 40))
        model.selectPage(1)

        model.prepareForPresentation()
        XCTAssertEqual(model.currentPage, 1)

        model.returnToFirstPageDelay = 0
        model.prepareForPresentation()
        XCTAssertEqual(model.currentPage, 0)
    }

    @MainActor
    func testReturnsToFirstPageOnlyAfterDelay() {
        let model = makeModel(apps: makeLaunchItems(count: 40))
        var clock = Date(timeIntervalSince1970: 1000)
        model.now = { clock }
        model.returnToFirstPageDelay = 5
        model.selectPage(1)
        model.setPresented(true)

        model.setPresented(false)
        clock += 2
        model.prepareForPresentation()
        XCTAssertEqual(model.currentPage, 1)

        model.setPresented(false)
        clock += 6
        model.prepareForPresentation()
        XCTAssertEqual(model.currentPage, 0)
    }

    @MainActor
    func testSearchCanIncludeHiddenApps() {
        let apps = makeLaunchItems(count: 3)
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
            .item(AppMenuContent(app: apps[1], canOpen: true, canEdit: true, canUninstall: false, isHidden: true))
        )
    }

    @MainActor
    func testBlankPointGivesMainMenu() {
        let model = makeModel(apps: makeLaunchItems(count: 3))

        XCTAssertEqual(model.contextMenu(at: CGPoint(x: 5, y: 5)), .main(MainMenuContent(canSelectAll: true, canArrange: true)))
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
