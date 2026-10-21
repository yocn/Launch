import CoreGraphics
import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelMenuTests: XCTestCase {
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

    private func id(_ app: CatalogApp) -> LayoutItemID {
        .app(app.identity.stableKey)
    }

    @MainActor
    private func makeModel(pages: [[ResolvedItem]], apps: [CatalogApp] = []) -> (LauncherModel, EditLog) {
        let model = LauncherModel(apps: apps)
        let log = EditLog()
        model.updateLayout(pages)
        model.canEditLayout = true
        model.onEdit = { log.edits.append($0) }
        model.updateHomeLayout(layout)
        model.updateGridFrame(gridFrame)
        model.updateFolderGridFrame(gridFrame)
        return (model, log)
    }

    @MainActor
    func testAppAndFolderMenus() {
        let apps = makeApps(count: 3)
        let folder = ResolvedFolder(id: "f", name: "效率", apps: [apps[2]])
        let (model, _) = makeModel(pages: [[.app(apps[0]), .app(apps[1]), .folder(folder)]])
        model.canUninstall = { $0 == apps[1] }

        XCTAssertEqual(model.contextMenu(at: center(0)), .app(AppMenuContent(app: apps[0], canOpen: true, canEdit: true, canUninstall: false)))
        XCTAssertEqual(model.contextMenu(at: center(1)), .app(AppMenuContent(app: apps[1], canOpen: true, canEdit: true, canUninstall: true)))
        XCTAssertEqual(model.contextMenu(at: center(2)), .folder(FolderMenuContent(folder: folder, canEdit: true)))
        XCTAssertEqual(model.contextMenu(at: CGPoint(x: 5, y: 5)), .main(MainMenuContent(canSelectAll: true, canArrange: true)))

        model.beginJiggling()
        model.canEditLayout = false
        XCTAssertEqual(model.contextMenu(at: center(0)), .app(AppMenuContent(app: apps[0], canOpen: false, canEdit: false, canUninstall: false)))
    }

    @MainActor
    func testPickedItemGetsSelectionMenuAndOtherItemClearsSelection() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        model.toggleMultiSelection(id(apps[0]))
        model.toggleMultiSelection(id(apps[1]))

        guard case .selection? = model.contextMenu(at: center(0)) else {
            return XCTFail("expected selection menu")
        }
        XCTAssertEqual(model.multiSelection.count, 2)
        guard case .app? = model.contextMenu(at: center(2)) else {
            return XCTFail("expected app menu")
        }
        XCTAssertTrue(model.multiSelection.isEmpty)
    }

    @MainActor
    func testMemberMenuInsideOpenFolder() {
        let apps = makeApps(count: 2)
        let (model, _) = makeModel(pages: [[.folder(ResolvedFolder(id: "f", name: "效率", apps: apps))]])
        model.showFolder(id: "f")

        XCTAssertEqual(model.contextMenu(at: center(1)), .app(AppMenuContent(app: apps[1], canOpen: true, canEdit: true, canUninstall: false)))
    }

    @MainActor
    func testMenuCommandsBecomeEdits() {
        let apps = makeApps(count: 3)
        let (model, log) = makeModel(pages: [[.app(apps[0]), makeFolder(id: "f", name: "效率", apps: [apps[1], apps[2]])]])

        model.performMenuCommand(.hide(id(apps[0])))
        model.performMenuCommand(.ungroup(folder: "f"))
        model.toggleMultiSelection(id(apps[0]))
        model.toggleMultiSelection(.folder("f"))
        model.performMenuCommand(.hideSelection)
        model.performMenuCommand(.showInfo(apps[0]))

        XCTAssertEqual(log.edits, [.hide([id(apps[0])]), .ungroupFolder("f"), .hide([id(apps[0]), .folder("f")])])
        XCTAssertTrue(model.multiSelection.isEmpty)

        model.canEditLayout = false
        model.performMenuCommand(.hide(id(apps[0])))
        model.performMenuCommand(.ungroup(folder: "f"))
        XCTAssertEqual(log.edits.count, 3)
    }

    @MainActor
    func testRenameCommandOpensFolderAndStartsRenaming() {
        let apps = makeApps(count: 2)
        let (model, _) = makeModel(pages: [[makeFolder(id: "f", name: "效率", apps: apps)]])

        model.performMenuCommand(.rename(folder: "f"))

        XCTAssertEqual(model.openFolderID, "f")
        XCTAssertEqual(model.renamingFolderID, "f")
        XCTAssertEqual(model.folderNameDraft, "效率")
    }

    @MainActor
    func testSearchSkipsHiddenApps() {
        let apps = makeApps(count: 3)
        let model = LauncherModel(apps: apps)

        model.updateHiddenApps([apps[1]])
        model.setQuery("App")

        XCTAssertEqual(model.results, [apps[0], apps[2]])
    }

    @MainActor
    func testSelectAllPicksEveryItemOnCurrentPage() {
        let apps = makeApps(count: 3)
        let folder = ResolvedFolder(id: "f", name: "效率", apps: [apps[2]])
        let (model, _) = makeModel(pages: [[.app(apps[0]), .folder(folder)], [.app(apps[1])]])

        model.selectAllOnPage()
        XCTAssertEqual(model.multiSelection.items, [id(apps[0]), .folder("f")])

        model.selectPage(1)
        model.performMenuCommand(.selectAll)
        XCTAssertEqual(model.multiSelection.items, [id(apps[1])])
    }

    @MainActor
    func testSelectAllAndArrangeNeedEditableLayoutWithoutQuery() {
        let apps = makeApps(count: 2)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)], apps: apps)

        model.setQuery("a")
        XCTAssertEqual(model.mainMenu, MainMenuContent(canSelectAll: false, canArrange: false))
        model.selectAllOnPage()
        XCTAssertTrue(model.multiSelection.isEmpty)

        model.setQuery("")
        model.canEditLayout = false
        XCTAssertEqual(model.mainMenu, MainMenuContent(canSelectAll: false, canArrange: false))
    }
}
