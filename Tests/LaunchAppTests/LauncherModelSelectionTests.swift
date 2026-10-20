import CoreGraphics
import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelSelectionTests: XCTestCase {
    private let layout = LauncherHomeLayout(
        screenSize: LauncherHomeLayout.canvasSize,
        referenceSize: LauncherHomeLayout.canvasSize
    )

    private var gridFrame: CGRect {
        CGRect(x: 0, y: 135, width: layout.contentSize.width, height: layout.gridHeight)
    }

    private func tile(_ index: Int) -> CGRect {
        GridHitTester(layout: layout, frame: gridFrame).tileRect(index)
    }

    private func center(_ index: Int) -> CGPoint {
        let rect = tile(index)
        return CGPoint(x: rect.midX, y: rect.minY + layout.tilePadding + layout.iconSide / 2)
    }

    private func leading(_ index: Int) -> CGPoint {
        let rect = tile(index)
        return CGPoint(x: rect.minX + 4, y: rect.maxY - 6)
    }

    private func id(_ app: CatalogApp) -> LayoutItemID {
        .app(app.identity.stableKey)
    }

    @MainActor
    private func makeModel(pages: [[ResolvedItem]]) -> (LauncherModel, EditLog) {
        let model = LauncherModel()
        let log = EditLog()
        model.updateLayout(pages)
        model.canEditLayout = true
        model.onEdit = { log.edits.append($0) }
        model.updateHomeLayout(layout)
        model.updatePageWidth(layout.contentSize.width)
        model.updateGridFrame(gridFrame)
        return (model, log)
    }

    @MainActor
    private func commandClick(_ model: LauncherModel, _ index: Int) {
        XCTAssertTrue(model.beginMarquee(at: center(index)))
        model.endMarquee()
    }

    @MainActor
    func testCommandClickTogglesItems() {
        let apps = makeApps(count: 4)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])

        commandClick(model, 1)
        commandClick(model, 3)
        commandClick(model, 1)

        XCTAssertEqual(model.multiSelection.items, [id(apps[3])])
        XCTAssertNil(model.marqueeRect)
    }

    @MainActor
    func testMarqueeAddsIntersectingTilesToExistingSelection() {
        let apps = makeApps(count: 12)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 10)

        XCTAssertTrue(model.beginMarquee(at: CGPoint(x: tile(0).minX - 2, y: tile(0).minY + 1)))
        model.updateMarquee(to: center(8))
        XCTAssertNotNil(model.marqueeRect)
        XCTAssertEqual(model.multiSelection.items, Set([0, 1, 7, 8, 10].map { id(apps[$0]) }))

        model.updateMarquee(to: center(1))
        XCTAssertEqual(model.multiSelection.items, Set([0, 1, 10].map { id(apps[$0]) }))
        model.endMarquee()

        XCTAssertNil(model.marqueeRect)
        XCTAssertEqual(model.multiSelection.count, 3)
    }

    @MainActor
    func testMultiSelectNeedsEditableGridWithoutSearchOrFolder() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [[makeFolder(id: "f", name: "效率", apps: apps)]])

        XCTAssertFalse(model.beginMarquee(at: CGPoint(x: 5, y: 5)))
        model.canEditLayout = false
        XCTAssertFalse(model.beginMarquee(at: center(0)))
        model.canEditLayout = true
        model.showFolder(id: "f")
        XCTAssertFalse(model.beginMarquee(at: center(0)))
        model.closeFolder()
        model.setQuery("App")
        XCTAssertFalse(model.beginMarquee(at: center(0)))
        model.setQuery("")
        XCTAssertTrue(model.beginMarquee(at: center(0)))
    }

    @MainActor
    func testEscapeClearsSelectionBeforeStoppingJiggle() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        model.beginJiggling()
        commandClick(model, 0)

        XCTAssertEqual(model.handleEscape(), .clearedSelection)
        XCTAssertTrue(model.multiSelection.isEmpty)
        XCTAssertEqual(model.handleEscape(), .stoppedJiggling)
    }

    @MainActor
    func testSearchActivationAndPresentationClearSelection() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])

        commandClick(model, 0)
        model.setQuery("App")
        XCTAssertTrue(model.multiSelection.isEmpty)

        model.setQuery("")
        commandClick(model, 0)
        model.moveSelection(.right)
        XCTAssertNil(model.activateSelection())
        XCTAssertTrue(model.multiSelection.isEmpty)
        XCTAssertNotNil(model.activateSelection())

        commandClick(model, 1)
        model.prepareForPresentation()
        XCTAssertTrue(model.multiSelection.isEmpty)
    }

    @MainActor
    func testLayoutUpdateDropsMissingItems() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 0)
        commandClick(model, 1)

        model.updateLayout([[.app(apps[0]), .app(apps[2])]])

        XCTAssertEqual(model.multiSelection.items, [id(apps[0])])
    }

    @MainActor
    func testPickedEntriesAreMarked() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 1)

        XCTAssertEqual(
            model.gridEntries(page: 0, items: model.pages[0], area: .grid).map(\.isPicked),
            [false, true, false]
        )
    }

    @MainActor
    func testMenuOnlyOnPickedItemAndListsPickedFolders() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [[.app(apps[0]), .app(apps[1]), makeFolder(id: "f", name: "效率", apps: [apps[2]])]])
        commandClick(model, 2)
        commandClick(model, 1)

        XCTAssertNil(model.selectionMenu(at: center(0)))
        XCTAssertEqual(
            model.selectionMenu(at: center(1)),
            SelectionMenuContent(count: 2, folders: [.init(id: "f", name: "效率")], pageCount: 1)
        )
    }

    @MainActor
    func testMenuCommandsBecomeGroupEditsInPageOrder() {
        let apps = makeApps(count: 4)
        let (model, log) = makeModel(pages: [
            [.app(apps[0]), .app(apps[1])],
            [makeFolder(id: "f", name: "效率", apps: [apps[3]]), .app(apps[2])],
        ])
        let picked: [LayoutItemID] = [id(apps[1]), .folder("f"), id(apps[2])]
        let commands: [SelectionCommand] = [.mergeIntoNewFolder, .mergeInto(folder: "f"), .moveToPage(0), .moveToNewPage]

        for command in commands {
            for item in picked.reversed() {
                model.toggleMultiSelection(item)
            }
            model.performSelectionCommand(command)
            XCTAssertTrue(model.multiSelection.isEmpty)
        }

        XCTAssertEqual(log.edits, [
            .mergeIntoNewFolder(picked),
            .moveGroup(picked, to: .merge(.folder("f"))),
            .moveGroup(picked, to: .insert(page: 0, before: nil)),
            .moveGroup(picked, to: .newPage),
        ])
    }

    @MainActor
    func testDraggingPickedItemMovesWholeGroup() {
        let apps = makeApps(count: 8)
        let (model, log) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 3)
        commandClick(model, 1)
        guard let press = model.itemPress(at: center(3)) else {
            return XCTFail("no item")
        }

        XCTAssertEqual(model.dragCount(for: press), 2)
        model.beginItemDrag(press, at: center(3))
        XCTAssertEqual(model.dragPreview?.count, 2)
        model.updateItemDrag(at: leading(3), now: 0)
        model.updateItemDrag(at: leading(3), now: 0.2)
        XCTAssertEqual(model.dragPreview?.target, .insert(page: 0, index: 3))
        model.endItemDrag(at: leading(3), now: 0.3)

        XCTAssertEqual(log.edits, [.moveGroup([id(apps[1]), id(apps[3])], to: .insert(page: 0, before: id(apps[5])))])
        XCTAssertTrue(model.multiSelection.isEmpty)
        XCTAssertEqual(model.landing?.entryIDs, ["app:" + apps[1].identity.stableKey, "app:" + apps[3].identity.stableKey])
    }

    @MainActor
    func testGroupDroppedOnAppCenterMerges() {
        let apps = makeApps(count: 6)
        let (model, log) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 0)
        commandClick(model, 1)
        guard let press = model.itemPress(at: center(0)) else {
            return XCTFail("no item")
        }

        model.beginItemDrag(press, at: center(0))
        model.updateItemDrag(at: center(1), now: 0)
        model.updateItemDrag(at: center(1), now: 0.15)
        model.endItemDrag(at: center(1), now: 0.2)

        XCTAssertEqual(log.edits, [.moveGroup([id(apps[0]), id(apps[1])], to: .merge(id(apps[3])))])
    }

    @MainActor
    func testDraggingUnpickedItemDropsSelection() {
        let apps = makeApps(count: 4)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 1)
        commandClick(model, 2)
        guard let press = model.itemPress(at: center(0)) else {
            return XCTFail("no item")
        }

        XCTAssertEqual(model.dragCount(for: press), 1)
        model.beginItemDrag(press, at: center(0))

        XCTAssertTrue(model.multiSelection.isEmpty)
        XCTAssertEqual(model.dragPreview?.isGroup, false)
    }

    @MainActor
    func testModifiedClickDoesNotDragPages() {
        let apps = makeApps(count: 40)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        model.isModifiedClick = true

        model.dragPage(by: -300)

        XCTAssertFalse(model.isPageDragging)
    }
}
