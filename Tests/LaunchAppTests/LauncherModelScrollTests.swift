import CoreGraphics
import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelScrollTests: XCTestCase {
    private let layout = LauncherHomeLayout(
        screenSize: LauncherHomeLayout.canvasSize,
        referenceSize: LauncherHomeLayout.canvasSize
    )
    private let viewport = CGRect(x: 0, y: 135, width: 1512, height: 800)
    private let gap: CGFloat = 40

    private func pageHeight(rows: Int) -> CGFloat {
        layout.tileHeight * CGFloat(rows) + layout.folderRowSpacing * CGFloat(rows - 1)
    }

    // 第 1 页 2 行、第 2 页 1 行，内容向上滚了 offset
    private func frames(offset: CGFloat) -> [CGRect] {
        let first = CGRect(x: 0, y: viewport.minY - offset, width: viewport.width, height: pageHeight(rows: 2))
        let second = CGRect(x: 0, y: first.maxY + gap, width: viewport.width, height: pageHeight(rows: 1))
        return [first, second]
    }

    private func tile(_ index: Int, in frame: CGRect) -> CGRect {
        GridHitTester(layout: layout, frame: frame, rowSpacing: layout.folderRowSpacing).tileRect(index)
    }

    private func center(_ index: Int, in frame: CGRect) -> CGPoint {
        let rect = tile(index, in: frame)
        return CGPoint(x: rect.midX, y: rect.minY + layout.tilePadding + layout.iconSide / 2)
    }

    private func leading(_ index: Int, in frame: CGRect) -> CGPoint {
        let rect = tile(index, in: frame)
        return CGPoint(x: rect.minX + 4, y: rect.maxY - 6)
    }

    @MainActor
    private func scroll(_ model: LauncherModel, offset: CGFloat) {
        for (page, frame) in frames(offset: offset).enumerated() {
            model.updatePageFrame(frame, page: page)
        }
    }

    @MainActor
    private func makeModel() -> (LauncherModel, [LaunchItem], EditLog) {
        let apps = makeLaunchItems(count: 12)
        let model = LauncherModel(apps: apps)
        let log = EditLog()
        model.updateLayout([apps.prefix(8).map(ResolvedItem.item), apps.dropFirst(8).map(ResolvedItem.item)])
        model.canEditLayout = true
        model.onEdit = { log.edits.append($0) }
        model.updateHomeLayout(layout)
        model.updatePageWidth(layout.contentSize.width)
        model.updateBrowsingStyle(.scroll)
        model.updateGridFrame(viewport)
        scroll(model, offset: 0)
        return (model, apps, log)
    }

    private func key(_ app: LaunchItem) -> LayoutItemID {
        .item(app.identity.stableKey)
    }

    @MainActor
    func testPressUsesPageUnderPointer() {
        let (model, apps, _) = makeModel()
        let second = frames(offset: 0)[1]

        let press = model.itemPress(at: center(2, in: second))

        XCTAssertEqual(press, LauncherModel.ItemPress(item: .item(apps[10]), origin: .grid(page: 1, index: 2)))
        XCTAssertEqual(model.frame(of: .grid(page: 1, index: 2)), tile(2, in: second))
    }

    @MainActor
    func testMarqueeSpansPages() {
        let (model, apps, _) = makeModel()
        let pages = frames(offset: 0)
        let start = CGPoint(x: tile(7, in: pages[0]).midX, y: tile(7, in: pages[0]).midY)

        XCTAssertTrue(model.beginMarquee(at: start))
        model.updateMarquee(to: CGPoint(x: tile(1, in: pages[1]).midX, y: tile(1, in: pages[1]).midY))

        XCTAssertEqual(model.multiSelection.items, [key(apps[7]), key(apps[8]), key(apps[9])])
    }

    @MainActor
    func testCurrentPageStaysWhileVisibleAndFollowsWhenScrolledOut() {
        let (model, _, _) = makeModel()
        model.moveSelection(.right)
        XCTAssertEqual(model.selectedIndex, 0)

        scroll(model, offset: pageHeight(rows: 2) - 50)
        XCTAssertEqual(model.currentPage, 0)
        XCTAssertEqual(model.selectedIndex, 0)

        scroll(model, offset: pageHeight(rows: 2) + 10)
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertNil(model.selectedIndex)
    }

    @MainActor
    func testPageCommandsRequestScroll() {
        let (model, _, _) = makeModel()

        model.selectPage(1)
        XCTAssertEqual(model.scrollRequest?.kind, .page(1))
        model.turnPage(.previous)
        XCTAssertEqual(model.scrollRequest?.kind, .page(0))
    }

    @MainActor
    func testKeyboardDownCrossesIntoNextPage() {
        let (model, _, _) = makeModel()
        model.moveSelection(.right)
        model.moveSelection(.down)
        XCTAssertEqual(model.selectedIndex, 7)

        model.moveSelection(.down)

        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.scrollRequest?.kind, .page(1))
    }

    @MainActor
    func testDragNearEdgesRequestsAutoScroll() throws {
        let (model, _, _) = makeModel()
        guard let press = model.itemPress(at: center(0, in: frames(offset: 0)[0])) else {
            return XCTFail("no item")
        }
        model.beginItemDrag(press, at: center(0, in: frames(offset: 0)[0]))

        model.updateItemDrag(at: CGPoint(x: 700, y: viewport.maxY - 10), now: 0)
        model.updateItemDrag(at: CGPoint(x: 700, y: viewport.maxY - 10), now: 0.1)
        guard case .by(let down)? = model.scrollRequest?.kind else {
            return XCTFail("expected auto scroll")
        }
        XCTAssertGreaterThan(down, 0)

        model.updateItemDrag(at: CGPoint(x: 700, y: viewport.minY + 5), now: 0.2)
        guard case .by(let up)? = model.scrollRequest?.kind else {
            return XCTFail("expected auto scroll")
        }
        XCTAssertLessThan(up, 0)

        let serial = model.scrollRequest?.serial
        model.updateItemDrag(at: CGPoint(x: 700, y: viewport.midY), now: 0.3)
        XCTAssertEqual(model.scrollRequest?.serial, serial)
    }

    @MainActor
    func testDropOnLaterPage() {
        let (model, apps, log) = makeModel()
        let pages = frames(offset: 0)
        guard let press = model.itemPress(at: center(0, in: pages[0])) else {
            return XCTFail("no item")
        }
        model.beginItemDrag(press, at: center(0, in: pages[0]))

        model.updateItemDrag(at: leading(1, in: pages[1]), now: 0)
        model.updateItemDrag(at: leading(1, in: pages[1]), now: 0.2)
        model.endItemDrag(at: leading(1, in: pages[1]), now: 0.3)

        XCTAssertEqual(log.edits, [.move(key(apps[0]), to: .insert(page: 1, before: key(apps[9])))])
    }

    @MainActor
    func testDraggingBelowLastPageAddsNewPage() {
        let (model, _, _) = makeModel()
        let pages = frames(offset: 0)
        guard let press = model.itemPress(at: center(0, in: pages[0])) else {
            return XCTFail("no item")
        }
        model.beginItemDrag(press, at: center(0, in: pages[0]))

        model.updateItemDrag(at: CGPoint(x: 700, y: pages[1].maxY + 100), now: 0)

        XCTAssertEqual(model.pages.count, 3)
        XCTAssertEqual(model.pages.last, [])
    }

    @MainActor
    func testBlankDragDoesNotTurnPages() {
        let (model, _, _) = makeModel()

        model.dragPage(by: -300)
        model.endPageDrag(predictedTranslation: -600, velocity: -2000)

        XCTAssertEqual(model.currentPage, 0)
    }
}
