import CoreGraphics
import Foundation
import LaunchCore

// 拖拽图标：命中判断、拖动会话、落点与合并
extension LauncherModel {
    func itemPress(at point: CGPoint) -> ItemPress? {
        guard let homeLayout else {
            return nil
        }
        if let folder = openFolder {
            let apps = visibleFolderApps
            let tester = GridHitTester(layout: homeLayout, frame: folderGridFrame, rowSpacing: homeLayout.folderRowSpacing)
            return tester.tileIndex(at: point, itemCount: apps.count).map {
                ItemPress(item: .item(apps[$0]), origin: .folder(id: folder.id, page: folderPage, index: $0))
            }
        }
        guard let (page, frame) = homePage(at: point) else {
            return nil
        }
        let items = pages[page]
        guard let index = homeTester(frame, layout: homeLayout).tileIndex(at: point, itemCount: items.count), items[index] != .empty else {
            return nil
        }
        return ItemPress(item: items[index], origin: .grid(page: page, index: index))
    }

    func frame(of origin: DragOrigin) -> CGRect? {
        guard let homeLayout else {
            return nil
        }
        switch origin {
        case .grid(let page, let index):
            return homeFrame(ofPage: page).map { homeTester($0, layout: homeLayout).tileRect(index) }
        case .folder(_, _, let index):
            return GridHitTester(layout: homeLayout, frame: folderGridFrame, rowSpacing: homeLayout.folderRowSpacing).tileRect(index)
        }
    }

    func beginItemDrag(_ press: ItemPress, at point: CGPoint) {
        guard canDragItems else {
            return
        }
        selectedIndex = nil
        folderSelectedIndex = nil
        dragStartPoint = point
        if isGroupDrag(press) {
            dragGroup = multiSelection.ordered(in: pages)
        } else {
            dragGroup = []
            clearMultiSelection()
        }
        dragSession = DragSession(item: press.item, origin: press.origin, group: Self.groupSources(dragGroup, in: pages))
        publishDragPreview()
    }

    func updateItemDrag(at point: CGPoint, now: TimeInterval) {
        guard var session = dragSession else {
            return
        }
        if browsingStyle == .scroll, openFolder == nil {
            autoScroll(at: point, now: now)
            // 拖到最后一页下方时多出一页空页可放
            if !session.hasExtraPage, let last = pageFrames[pages.count - 1], point.y > last.maxY + (homeLayout?.folderRowSpacing ?? 0) {
                session.addExtraPage()
                dragSession = session
                publishDragPreview()
            }
        }
        let events = session.update(
            hit: dragHit(at: point, preview: session.preview),
            outsideFolder: isOutsideFolder(point),
            now: now
        )
        dragSession = session
        for event in events {
            switch event {
            case .leaveFolder:
                closeFolder()
            case .turnPage(let direction):
                if direction == .next, currentPage >= pages.count - 1 {
                    guard dragSession?.hasExtraPage == false else {
                        continue
                    }
                    dragSession?.addExtraPage()
                    publishDragPreview()
                }
                setGridPage(clampedPage(currentPage + (direction == .next ? 1 : -1)), animated: true)
            }
        }
        publishDragPreview()
    }

    func endItemDrag(at point: CGPoint, now: TimeInterval) {
        guard let session = dragSession else {
            return
        }
        let preview = session.preview
        let target = session.dropTarget(for: dragHit(at: point, preview: preview))
        let edit = target.flatMap { layoutEdit(for: $0, preview: preview) }
        if edit != nil, case .insert? = target, let frame = frame(of: preview.origin) {
            let ids = preview.isGroup ? dragGroup.map { Self.entryID($0) } : [Self.entryID(preview.item, index: 0)]
            landing = Landing(
                entryIDs: Set(ids),
                from: frame.offsetBy(dx: point.x - dragStartPoint.x, dy: point.y - dragStartPoint.y)
            )
        }
        if edit != nil, preview.isGroup {
            clearMultiSelection()
        }
        finishItemDrag()
        if let edit {
            onEdit?(edit)
        }
    }

    func clearLanding() {
        landing = nil
    }

    func cancelItemDrag() {
        finishItemDrag()
    }

    func gridEntries(page: Int, items: [ResolvedItem], area: DragArea) -> [GridEntry] {
        let preview = dragPreview
        let entries = preview?.entries(
            page: page,
            itemCount: items.count,
            capacity: grid.capacity,
            in: area
        ) ?? items.indices.map(PreviewEntry.item)
        var seen = Set<String>()
        var gaps = 0
        return entries.map { entry in
            switch entry {
            case .gap:
                defer { gaps += 1 }
                return GridEntry(
                    id: gaps == 0 ? "drag-gap" : "drag-gap-\(gaps)",
                    content: .gap,
                    isMergeTarget: false,
                    isPicked: false
                )
            case .item(let index):
                let base = Self.entryID(items[index], index: index)
                let id = seen.insert(base).inserted ? base : "\(base)#\(index)"
                let isMergeTarget = preview?.area == area && preview?.target == .merge(page: page, index: index)
                let isPicked = area == .grid && items[index].layoutID.map(multiSelection.contains) == true
                return GridEntry(
                    id: id,
                    content: .item(items[index], index: index),
                    isMergeTarget: isMergeTarget,
                    isPicked: isPicked
                )
            }
        }
    }

    static func entryID(_ item: ResolvedItem, index: Int) -> String {
        switch item {
        case .item(let app):
            "app:" + app.identity.stableKey
        case .folder(let folder):
            "folder:" + folder.id
        case .empty:
            "empty:\(index)"
        }
    }

    static func entryID(_ item: LayoutItemID) -> String {
        switch item {
        case .item(let key):
            "app:" + key
        case .folder(let id):
            "folder:" + id
        }
    }

    private func finishItemDrag() {
        dragGroup = []
        dragSession = nil
        dragPreview = nil
        if let pendingLayout {
            self.pendingLayout = nil
            updateLayout(pendingLayout)
        } else {
            normalizeState()
        }
    }

    private func publishDragPreview() {
        let preview = dragSession?.preview
        if preview != dragPreview {
            dragPreview = preview
        }
    }

    private func dragHit(at point: CGPoint, preview: DragPreview) -> DragHit {
        guard let homeLayout else {
            return .none
        }
        let page: Int
        let itemCount: Int
        let tester: GridHitTester
        if preview.area == .folder {
            guard let folder = openFolder else {
                return .none
            }
            let folderPages = folderPages
            page = folderPage
            itemCount = folderPages.indices.contains(page) ? folderPages[page].count : 0
            tester = GridHitTester(
                layout: homeLayout,
                frame: folderGridFrame,
                rowCount: homeLayout.folderRowCount(memberCount: folder.items.count),
                rowSpacing: homeLayout.folderRowSpacing
            )
        } else {
            let gridPages = pages
            guard let (hitPage, frame) = homePage(at: point, nearest: true) else {
                return .none
            }
            page = hitPage
            itemCount = gridPages.indices.contains(page) ? gridPages[page].count : 0
            tester = homeTester(frame, layout: homeLayout)
        }
        let entries = preview.entries(
            page: page,
            itemCount: itemCount,
            capacity: grid.capacity,
            in: preview.area
        )
        return preview.hit(
            for: tester.hit(point, itemCount: entries.count),
            entries: entries,
            itemCount: itemCount,
            page: page,
            in: preview.area
        )
    }

    private func isOutsideFolder(_ point: CGPoint) -> Bool {
        guard openFolder != nil, let homeLayout else {
            return false
        }
        let panel = folderGridFrame.insetBy(
            dx: homeLayout.horizontalInset - homeLayout.folderPanelOutset,
            dy: -homeLayout.folderPanelPadding
        )
        return !panel.contains(point)
    }

    private func layoutEdit(for target: DragTarget, preview: DragPreview) -> LayoutEdit? {
        guard let itemID = preview.item.layoutID else {
            return nil
        }
        if preview.area == .folder {
            guard case .folder(let folderID, _, _) = preview.origin,
                  case .item(let app) = preview.item,
                  case .insert(let page, let index) = target else {
                return nil
            }
            let before = Self.folderAnchor(pages: folderPages, page: page, index: index, moving: app)
            return .reorderInFolder(folder: folderID, app: app.identity.stableKey, before: before)
        }
        let gridPages = pages
        let dropTarget: LayoutDropTarget
        switch target {
        case .merge(let page, let index):
            guard gridPages.indices.contains(page),
                  gridPages[page].indices.contains(index),
                  let targetID = gridPages[page][index].layoutID else {
                return nil
            }
            dropTarget = .merge(targetID)
        case .insert(let page, let index):
            if preview.hasExtraPage, page == gridPages.count - 1 {
                dropTarget = .newPage
            } else {
                let sources = Set(preview.sourceIndices(onPage: page, in: .grid))
                let items = (gridPages.indices.contains(page) ? gridPages[page] : [])
                    .enumerated()
                    .filter { !sources.contains($0.offset) }
                    .map(\.element)
                dropTarget = .insert(page: page, before: index < items.count ? items[index].layoutID : nil)
            }
        }
        if preview.isGroup {
            return .moveGroup(dragGroup, to: dropTarget)
        }
        if case .folder(let folderID, _, _) = preview.origin, case .item(let app) = preview.item {
            return .moveOutOfFolder(app: app.identity.stableKey, folder: folderID, to: dropTarget)
        }
        return .move(itemID, to: dropTarget)
    }

    private static func folderAnchor(pages: [[LaunchItem]], page: Int, index: Int, moving: LaunchItem) -> String? {
        let trimmed = pages.map { $0.filter { $0 != moving } }
        let members = Array(trimmed.joined())
        let offset = trimmed.prefix(page).reduce(0) { $0 + $1.count } + index
        return offset < members.count ? members[offset].identity.stableKey : nil
    }
}
