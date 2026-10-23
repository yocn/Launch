import CoreGraphics
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
final class EditLog {
    var edits: [LayoutEdit] = []
}

final class LauncherModelDragTests: XCTestCase {
    private let layout = LauncherHomeLayout(
        screenSize: LauncherHomeLayout.canvasSize,
        referenceSize: LauncherHomeLayout.canvasSize
    )

    private var gridFrame: CGRect {
        CGRect(x: 0, y: 135, width: layout.contentSize.width, height: layout.gridHeight)
    }

    private func tile(_ index: Int, in frame: CGRect? = nil) -> CGRect {
        GridHitTester(layout: layout, frame: frame ?? gridFrame).tileRect(index)
    }

    private func center(_ index: Int, in frame: CGRect? = nil) -> CGPoint {
        let rect = tile(index, in: frame)
        return CGPoint(x: rect.midX, y: rect.minY + layout.tilePadding + layout.iconSide / 2)
    }

    private func leading(_ index: Int, in frame: CGRect? = nil) -> CGPoint {
        let rect = tile(index, in: frame)
        return CGPoint(x: rect.minX + 4, y: rect.maxY - 6)
    }

    @MainActor
    private func makeModel(pages: [[ResolvedItem]], apps: [LaunchItem] = []) -> (LauncherModel, EditLog) {
        let model = LauncherModel(apps: apps)
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
    private func begin(_ model: LauncherModel, at point: CGPoint) {
        guard let press = model.itemPress(at: point) else {
            return XCTFail("no item at \(point)")
        }
        model.beginItemDrag(press, at: point)
    }

    @MainActor
    func testPressOnTileReportsItemAndOrigin() {
        let apps = makeLaunchItems(count: 5)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.item)])

        XCTAssertEqual(
            model.itemPress(at: center(2)),
            LauncherModel.ItemPress(item: .item(apps[2]), origin: .grid(page: 0, index: 2))
        )
        XCTAssertNil(model.itemPress(at: CGPoint(x: tile(0).maxX + 20, y: tile(0).midY)))
    }

    @MainActor
    func testDwellingBesideItemInsertsBeforeIt() {
        let apps = makeLaunchItems(count: 5)
        let (model, log) = makeModel(pages: [apps.map(ResolvedItem.item)])

        begin(model, at: center(4))
        model.updateItemDrag(at: leading(1), now: 0)
        model.updateItemDrag(at: leading(1), now: 0.2)
        XCTAssertEqual(model.dragPreview?.target, .insert(page: 0, index: 1))
        model.endItemDrag(at: leading(1), now: 0.3)

        XCTAssertEqual(log.edits, [.move(
            .item(apps[4].identity.stableKey),
            to: .insert(page: 0, before: .item(apps[1].identity.stableKey))
        )])
        XCTAssertNil(model.dragPreview)
    }

    @MainActor
    func testHoveringIconCenterMergesIntoFolder() {
        let apps = makeLaunchItems(count: 5)
        let (model, log) = makeModel(pages: [apps.map(ResolvedItem.item)])

        begin(model, at: center(0))
        model.updateItemDrag(at: center(3), now: 0)
        model.updateItemDrag(at: center(3), now: 0.15)
        XCTAssertEqual(model.dragPreview?.target, .merge(page: 0, index: 3))
        let entries = model.gridEntries(page: 0, items: model.pages[0], area: .grid)
        XCTAssertEqual(entries.first?.content, .gap)
        XCTAssertEqual(entries.map(\.isMergeTarget), [false, false, false, true, false])
        model.endItemDrag(at: center(3), now: 0.2)

        XCTAssertEqual(log.edits, [.move(.item(apps[0].identity.stableKey), to: .merge(.item(apps[3].identity.stableKey)))])
    }

    @MainActor
    func testQuickDropOnIconCenterInsertsBeforeIt() {
        let apps = makeLaunchItems(count: 5)
        let (model, log) = makeModel(pages: [apps.map(ResolvedItem.item)])

        begin(model, at: center(0))
        model.endItemDrag(at: center(3), now: 0)

        XCTAssertEqual(log.edits, [.move(
            .item(apps[0].identity.stableKey),
            to: .insert(page: 0, before: .item(apps[3].identity.stableKey))
        )])
    }

    @MainActor
    func testCancelProducesNoEdit() {
        let apps = makeLaunchItems(count: 5)
        let (model, log) = makeModel(pages: [apps.map(ResolvedItem.item)])

        begin(model, at: center(4))
        model.updateItemDrag(at: leading(1), now: 0)
        model.updateItemDrag(at: leading(1), now: 0.2)
        model.cancelItemDrag()

        XCTAssertTrue(log.edits.isEmpty)
        XCTAssertNil(model.dragPreview)
    }

    @MainActor
    func testEdgeDwellTurnsToTemporaryNewPage() {
        let apps = makeLaunchItems(count: 5)
        let (model, log) = makeModel(pages: [apps.map(ResolvedItem.item)])
        let edge = CGPoint(x: gridFrame.maxX - 10, y: tile(0).midY)

        begin(model, at: center(0))
        model.updateItemDrag(at: edge, now: 0)
        model.updateItemDrag(at: edge, now: 0.5)
        XCTAssertEqual(model.pages.count, 2)
        XCTAssertEqual(model.currentPage, 1)
        model.endItemDrag(at: center(0), now: 0.6)

        XCTAssertEqual(log.edits, [.move(.item(apps[0].identity.stableKey), to: .newPage)])
        XCTAssertEqual(model.pages.count, 1)
        XCTAssertEqual(model.currentPage, 0)
    }

    @MainActor
    func testDraggingFolderMemberOutAndIntoGrid() {
        let apps = makeLaunchItems(count: 4)
        let (model, log) = makeModel(pages: [[
            makeFolder(id: "f", name: "效率", apps: Array(apps[0 ..< 3])),
            .item(apps[3]),
        ]])
        model.showFolder(id: "f")
        let folderFrame = CGRect(x: 0, y: 300, width: layout.contentSize.width, height: layout.folderGridHeight(memberCount: 3))
        model.updateFolderGridFrame(folderFrame)
        XCTAssertEqual(model.itemPress(at: center(1, in: folderFrame))?.origin, .folder(id: "f", page: 0, index: 1))

        begin(model, at: center(1, in: folderFrame))
        let outside = CGPoint(x: 756, y: 40)
        model.updateItemDrag(at: outside, now: 0)
        model.updateItemDrag(at: outside, now: 0.3)
        XCTAssertNil(model.openFolderID)
        model.updateItemDrag(at: leading(1), now: 0.4)
        model.updateItemDrag(at: leading(1), now: 0.6)
        model.endItemDrag(at: leading(1), now: 0.7)

        XCTAssertEqual(log.edits, [.moveOutOfFolder(
            app: apps[1].identity.stableKey,
            folder: "f",
            to: .insert(page: 0, before: .item(apps[3].identity.stableKey))
        )])
    }

    @MainActor
    func testReorderingInsideFolder() {
        let apps = makeLaunchItems(count: 3)
        let (model, log) = makeModel(pages: [[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.showFolder(id: "f")
        let folderFrame = CGRect(x: 0, y: 300, width: layout.contentSize.width, height: layout.folderGridHeight(memberCount: 3))
        model.updateFolderGridFrame(folderFrame)

        begin(model, at: center(2, in: folderFrame))
        model.updateItemDrag(at: leading(0, in: folderFrame), now: 0)
        model.updateItemDrag(at: leading(0, in: folderFrame), now: 0.2)
        model.endItemDrag(at: leading(0, in: folderFrame), now: 0.3)

        XCTAssertEqual(log.edits, [.reorderInFolder(
            folder: "f",
            app: apps[2].identity.stableKey,
            before: apps[0].identity.stableKey
        )])
    }

    @MainActor
    func testLayoutUpdatesWaitUntilDragEnds() {
        let apps = makeLaunchItems(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.item)])
        let reversed: [[ResolvedItem]] = [apps.reversed().map(ResolvedItem.item)]

        begin(model, at: center(0))
        model.updateLayout(reversed)
        XCTAssertEqual(model.layoutPages, [apps.map(ResolvedItem.item)])
        model.cancelItemDrag()

        XCTAssertEqual(model.layoutPages, reversed)
    }

    @MainActor
    func testDraggingRequiresEditableLayoutWithoutSearch() {
        let apps = makeLaunchItems(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.item)], apps: apps)

        model.canEditLayout = false
        begin(model, at: center(0))
        XCTAssertNil(model.dragPreview)

        model.canEditLayout = true
        model.setQuery("App")
        begin(model, at: center(0))
        XCTAssertNil(model.dragPreview)
    }

    @MainActor
    func testRenamingCommitsDraftOnSubmitAndWhenFolderCloses() {
        let apps = makeLaunchItems(count: 2)
        let (model, log) = makeModel(pages: [[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.showFolder(id: "f")

        model.beginRenamingFolder()
        XCTAssertEqual(model.folderNameDraft, "效率")
        model.folderNameDraft = "工具"
        model.finishRenamingFolder()
        XCTAssertNil(model.renamingFolderID)

        model.beginRenamingFolder()
        model.folderNameDraft = "常用"
        model.closeFolder()

        XCTAssertEqual(log.edits, [
            .renameFolder(folder: "f", name: "工具"),
            .renameFolder(folder: "f", name: "常用"),
        ])
    }

    @MainActor
    func testEscapeCancelsRenameBeforeClosingFolder() {
        let apps = makeLaunchItems(count: 2)
        let (model, log) = makeModel(pages: [[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.showFolder(id: "f")
        model.beginRenamingFolder()
        model.folderNameDraft = "x"

        XCTAssertEqual(model.handleEscape(), .cancelledRename)
        XCTAssertEqual(model.openFolderID, "f")
        XCTAssertEqual(model.handleEscape(), .closedFolder)
        XCTAssertTrue(log.edits.isEmpty)
    }

    @MainActor
    func testRenameAndDragAreDisabledWhileLayoutIsNotEditable() {
        let apps = makeLaunchItems(count: 2)
        let (model, _) = makeModel(pages: [[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.showFolder(id: "f")
        model.canEditLayout = false

        model.beginRenamingFolder()

        XCTAssertNil(model.renamingFolderID)
    }

    @MainActor
    func testPageDragIsIgnoredWhileDraggingItem() {
        let apps = makeLaunchItems(count: 40)
        let (model, _) = makeModel(pages: [Array(apps[0 ..< 35]).map(ResolvedItem.item), Array(apps[35...]).map(ResolvedItem.item)])

        begin(model, at: center(0))
        model.dragPage(by: -25)
        model.cancelItemDrag()
        model.endPageDrag(predictedTranslation: -900, velocity: -3000)

        XCTAssertFalse(model.needsPagerFrames)
        XCTAssertEqual(model.gridPosition, 0)
        XCTAssertEqual(model.currentPage, 0)
    }

    @MainActor
    func testInsertDropRecordsLandingFromPointerOffset() {
        let apps = makeLaunchItems(count: 5)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.item)])
        let start = center(4)

        begin(model, at: start)
        model.endItemDrag(at: leading(1), now: 0)

        XCTAssertEqual(model.landing?.entryIDs, ["app:" + apps[4].identity.stableKey])
        XCTAssertEqual(
            model.landing?.from,
            tile(4).offsetBy(dx: leading(1).x - start.x, dy: leading(1).y - start.y)
        )
        model.clearLanding()
        XCTAssertNil(model.landing)
    }

    @MainActor
    func testMergeDropHasNoLanding() {
        let apps = makeLaunchItems(count: 5)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.item)])

        begin(model, at: center(0))
        model.updateItemDrag(at: center(3), now: 0)
        model.updateItemDrag(at: center(3), now: 0.15)
        model.endItemDrag(at: center(3), now: 0.2)

        XCTAssertNil(model.landing)
    }
}
