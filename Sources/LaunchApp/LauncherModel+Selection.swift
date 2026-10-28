import CoreGraphics
import Foundation
import LaunchCore

// 多选、框选与右键菜单内容
extension LauncherModel {
    var canMultiSelect: Bool {
        canDragItems && openFolder == nil
    }

    func toggleMultiSelection(_ item: LayoutItemID) {
        guard canMultiSelect else {
            return
        }
        multiSelection.toggle(item)
    }

    @discardableResult
    func clearMultiSelection() -> Bool {
        guard !multiSelection.isEmpty else {
            return false
        }
        multiSelection = MultiSelection()
        return true
    }

    func beginMarquee(at point: CGPoint) -> Bool {
        guard canMultiSelect, gridFrame.contains(point) else {
            return false
        }
        marqueeStart = point
        multiSelection.beginMarquee()
        return true
    }

    func updateMarquee(to point: CGPoint) {
        guard let start = marqueeStart, let homeLayout else {
            return
        }
        let rect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        marqueeRect = rect
        let gridPages = pages
        let hits = visibleHomePages().flatMap { page, frame in
            homeTester(frame, layout: homeLayout)
                .tileIndices(intersecting: rect, itemCount: gridPages[page].count)
                .compactMap { gridPages[page][$0].layoutID }
        }
        var selection = multiSelection
        selection.updateMarquee(hits: Set(hits))
        setMultiSelection(selection)
    }

    // 没拖出选框即为 ⌘ 单击，切换按下处图标的选中状态
    func endMarquee() {
        guard let start = marqueeStart else {
            return
        }
        var selection = multiSelection
        if marqueeRect == nil, let item = itemPress(at: start)?.item.layoutID {
            selection.toggle(item)
        }
        selection.endMarquee()
        setMultiSelection(selection)
        marqueeStart = nil
        marqueeRect = nil
    }

    func dragCount(for press: ItemPress) -> Int {
        isGroupDrag(press) ? multiSelection.count : 1
    }

    func selectionMenu(at point: CGPoint) -> SelectionMenuContent? {
        guard canMultiSelect, let item = itemPress(at: point)?.item.layoutID, multiSelection.contains(item) else {
            return nil
        }
        let gridPages = pages
        let folders = gridPages.joined().compactMap { item -> SelectionMenuContent.Folder? in
            guard case .folder(let folder) = item, multiSelection.contains(.folder(folder.id)) else {
                return nil
            }
            return SelectionMenuContent.Folder(id: folder.id, name: folder.name)
        }
        return SelectionMenuContent(
            count: multiSelection.ordered(in: gridPages).count,
            folders: folders,
            pageCount: gridPages.count
        )
    }

    // 未选中的图标弹出自己的菜单前先清空多选
    func contextMenu(at point: CGPoint) -> ItemMenuContent? {
        if let selection = selectionMenu(at: point) {
            return .selection(selection)
        }
        guard let press = itemPress(at: point) else {
            var menu = mainMenu
            menu.pageIndex = homePage(at: point)?.page ?? currentPage
            return .main(menu)
        }
        clearMultiSelection()
        switch press.item {
        case .item(let app):
            return .item(AppMenuContent(
                app: app,
                canOpen: !isJiggling,
                canEdit: canEditMenuItems,
                canUninstall: canUninstall(app),
                isHidden: isHiddenItem(app),
                canManageExtraItems: app.application == nil && canEditLayout,
                isPinned: app.application == nil && isPinned(app.identity),
                pinPage: app.application == nil ? (query.isEmpty ? currentPage : pageBeforeSearch) : 0
            ))
        case .folder(let folder):
            return .folder(FolderMenuContent(folder: folder, canEdit: canEditMenuItems))
        case .empty:
            return nil
        }
    }

    var mainMenu: MainMenuContent {
        MainMenuContent(
            canSelectAll: canMultiSelect && !visibleItems.isEmpty,
            canArrange: canMultiSelect,
            sort: displaySort,
            browsingStyle: browsingStyle,
            displayMode: displayMode,
            canAddWebsite: canEditLayout && query.isEmpty && displaySort.field == .custom,
            pageIndex: currentPage
        )
    }

    private func isPinned(_ identity: ItemIdentity) -> Bool {
        (layoutPages ?? []).joined().contains { item in
            switch item {
            case .item(let entry): return entry.identity == identity
            case .folder(let folder): return folder.items.contains { $0.identity == identity }
            case .empty: return false
            }
        }
    }
}
