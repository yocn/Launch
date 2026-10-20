import CoreGraphics
import Foundation
import LaunchCore
import Observation

enum EscapeOutcome: Equatable {
    case cancelledRename
    case closedFolder
    case stoppedJiggling
    case clearedQuery
    case close
}

@MainActor
@Observable
final class LauncherModel {
    struct ItemPress: Equatable {
        let item: ResolvedItem
        let origin: DragOrigin
    }

    struct GridEntry: Identifiable, Equatable {
        enum Content: Equatable {
            case item(ResolvedItem, index: Int)
            case gap
        }

        let id: String
        let content: Content
        let isMergeTarget: Bool
    }

    struct Landing: Equatable {
        let entryID: String
        let from: CGRect
    }

    private(set) var apps: [CatalogApp]
    private(set) var layoutPages: [[ResolvedItem]]?
    private(set) var query = ""
    private(set) var currentPage = 0
    private(set) var selectedIndex: Int?
    private(set) var presentationCount = 0
    private(set) var openFolderID: String?
    private(set) var folderPage = 0
    private(set) var folderSelectedIndex: Int?
    private(set) var gridPosition: CGFloat = 0
    private(set) var folderPosition: CGFloat = 0
    private(set) var dragPreview: DragPreview?
    private(set) var landing: Landing?
    private(set) var isJiggling = false
    private(set) var renamingFolderID: String?
    var folderNameDraft = ""
    // 以下每帧都会变化，不参与视图观察，否则每帧都会重建整个网格
    @ObservationIgnored private(set) var isPageDragging = false
    @ObservationIgnored private(set) var pageWidth: CGFloat = 0
    @ObservationIgnored private var gridMotion = PagerMotion()
    @ObservationIgnored private var folderMotion = PagerMotion()
    @ObservationIgnored var onNeedsFrames: (() -> Void)?
    @ObservationIgnored var onEdit: ((LayoutEdit) -> Void)?
    @ObservationIgnored var canEditLayout = false
    @ObservationIgnored var canUninstall: (CatalogApp) -> Bool = { _ in false }
    @ObservationIgnored private(set) var homeLayout: LauncherHomeLayout?
    @ObservationIgnored private(set) var gridFrame: CGRect = .zero
    @ObservationIgnored private(set) var folderGridFrame: CGRect = .zero
    @ObservationIgnored private var dragSession: DragSession?
    @ObservationIgnored private var dragStartPoint: CGPoint = .zero
    @ObservationIgnored private var pendingLayout: [[ResolvedItem]]?

    init(apps: [CatalogApp] = []) {
        self.apps = apps
    }

    var results: [CatalogApp] {
        SearchService.results(for: query, in: apps, hidden: [])
    }

    var pages: [[ResolvedItem]] {
        let source: [[ResolvedItem]]
        if query.isEmpty, let layoutPages {
            source = layoutPages
        } else {
            source = [results.map(ResolvedItem.app)]
        }
        let paged = source.flatMap {
            LauncherPagination.pages($0, capacity: LauncherHomeLayout.pageCapacity)
        }
        return dragPreview?.hasExtraPage == true ? paged + [[]] : paged
    }

    var visibleItems: [ResolvedItem] {
        let pages = pages
        guard !pages.isEmpty else {
            return []
        }
        return pages[LauncherPagination.normalizedPageIndex(currentPage, pageCount: pages.count)]
    }

    var openFolder: ResolvedFolder? {
        guard let openFolderID, let layoutPages else {
            return nil
        }
        for item in layoutPages.joined() {
            if case .folder(let folder) = item, folder.id == openFolderID {
                return folder
            }
        }
        return nil
    }

    var folderPages: [[CatalogApp]] {
        guard let openFolder else {
            return []
        }
        return LauncherPagination.pages(openFolder.apps, capacity: LauncherHomeLayout.pageCapacity)
    }

    var visibleFolderApps: [CatalogApp] {
        let pages = folderPages
        guard !pages.isEmpty else {
            return []
        }
        return pages[LauncherPagination.normalizedPageIndex(folderPage, pageCount: pages.count)]
    }

    var pageDragOffset: CGFloat {
        let translation = (openFolder != nil ? folderMotion : gridMotion).dragTranslation ?? 0
        return PageDragResolver.displayOffset(
            translation: translation,
            currentPage: activePage,
            pageCount: activePageCount,
            pageWidth: pageWidth
        )
    }

    var needsPagerFrames: Bool {
        gridMotion.isActive || folderMotion.isActive
    }

    private var activePage: Int {
        openFolder != nil ? folderPage : currentPage
    }

    private var activePageCount: Int {
        openFolder != nil ? folderPages.count : pages.count
    }

    func updatePageWidth(_ width: CGFloat) {
        pageWidth = width
    }

    var canDragItems: Bool {
        canEditLayout && query.isEmpty && layoutPages != nil && renamingFolderID == nil
    }

    func updateHomeLayout(_ layout: LauncherHomeLayout) {
        homeLayout = layout
    }

    func updateGridFrame(_ frame: CGRect) {
        gridFrame = frame
    }

    func updateFolderGridFrame(_ frame: CGRect) {
        folderGridFrame = frame
    }

    func itemPress(at point: CGPoint) -> ItemPress? {
        guard let homeLayout else {
            return nil
        }
        if let folder = openFolder {
            let apps = visibleFolderApps
            let tester = GridHitTester(layout: homeLayout, frame: folderGridFrame)
            return tester.tileIndex(at: point, itemCount: apps.count).map {
                ItemPress(item: .app(apps[$0]), origin: .folder(id: folder.id, page: folderPage, index: $0))
            }
        }
        let items = visibleItems
        let tester = GridHitTester(layout: homeLayout, frame: gridFrame)
        guard let index = tester.tileIndex(at: point, itemCount: items.count), items[index] != .empty else {
            return nil
        }
        return ItemPress(item: items[index], origin: .grid(page: currentPage, index: index))
    }

    func frame(of origin: DragOrigin) -> CGRect? {
        guard let homeLayout else {
            return nil
        }
        switch origin {
        case .grid(_, let index):
            return GridHitTester(layout: homeLayout, frame: gridFrame).tileRect(index)
        case .folder(_, _, let index):
            return GridHitTester(layout: homeLayout, frame: folderGridFrame).tileRect(index)
        }
    }

    func beginItemDrag(_ press: ItemPress, at point: CGPoint) {
        guard canDragItems else {
            return
        }
        selectedIndex = nil
        folderSelectedIndex = nil
        dragStartPoint = point
        dragSession = DragSession(item: press.item, origin: press.origin)
        publishDragPreview()
    }

    func updateItemDrag(at point: CGPoint, now: TimeInterval) {
        guard var session = dragSession else {
            return
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
            landing = Landing(
                entryID: Self.entryID(preview.item, index: 0),
                from: frame.offsetBy(dx: point.x - dragStartPoint.x, dy: point.y - dragStartPoint.y)
            )
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
            capacity: LauncherHomeLayout.pageCapacity,
            in: area
        ) ?? items.indices.map(PreviewEntry.item)
        var seen = Set<String>()
        return entries.map { entry in
            switch entry {
            case .gap:
                return GridEntry(id: "drag-gap", content: .gap, isMergeTarget: false)
            case .item(let index):
                let base = Self.entryID(items[index], index: index)
                let id = seen.insert(base).inserted ? base : "\(base)#\(index)"
                let isMergeTarget = preview?.area == area && preview?.target == .merge(page: page, index: index)
                return GridEntry(id: id, content: .item(items[index], index: index), isMergeTarget: isMergeTarget)
            }
        }
    }

    static func entryID(_ item: ResolvedItem, index: Int) -> String {
        switch item {
        case .app(let app):
            "app:" + app.identity.stableKey
        case .folder(let folder):
            "folder:" + folder.id
        case .empty:
            "empty:\(index)"
        }
    }

    private func finishItemDrag() {
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
                rowCount: homeLayout.folderRowCount(memberCount: folder.apps.count)
            )
        } else {
            let gridPages = pages
            page = currentPage
            itemCount = gridPages.indices.contains(page) ? gridPages[page].count : 0
            tester = GridHitTester(layout: homeLayout, frame: gridFrame)
        }
        let entries = preview.entries(
            page: page,
            itemCount: itemCount,
            capacity: LauncherHomeLayout.pageCapacity,
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
                  case .app(let app) = preview.item,
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
                var items = gridPages.indices.contains(page) ? gridPages[page] : []
                if let source = preview.sourceIndex(onPage: page, in: .grid) {
                    items.remove(at: source)
                }
                dropTarget = .insert(page: page, before: index < items.count ? items[index].layoutID : nil)
            }
        }
        if case .folder(let folderID, _, _) = preview.origin, case .app(let app) = preview.item {
            return .moveOutOfFolder(app: app.identity.stableKey, folder: folderID, to: dropTarget)
        }
        return .move(itemID, to: dropTarget)
    }

    private static func folderAnchor(pages: [[CatalogApp]], page: Int, index: Int, moving: CatalogApp) -> String? {
        let trimmed = pages.map { $0.filter { $0 != moving } }
        let members = Array(trimmed.joined())
        let offset = trimmed.prefix(page).reduce(0) { $0 + $1.count } + index
        return offset < members.count ? members[offset].identity.stableKey : nil
    }

    func dragPage(by translation: CGFloat) {
        // 发起图标拖拽的那次拖动事件也会被转给 SwiftUI 翻页手势，且它永远收不到结束
        guard dragSession == nil else {
            return
        }
        isPageDragging = true
        if openFolder != nil {
            folderMotion.updateDrag(translation: translation)
        } else {
            gridMotion.updateDrag(translation: translation)
        }
        onNeedsFrames?()
    }

    func endPageDrag(predictedTranslation: CGFloat, velocity: CGFloat = 0) {
        guard isPageDragging else {
            return
        }
        let target = PageDragResolver.targetPage(
            currentPage: activePage,
            pageCount: activePageCount,
            predictedTranslation: predictedTranslation,
            pageWidth: pageWidth
        )
        isPageDragging = false
        let pagesPerSecond = pageWidth > 0 ? -velocity / pageWidth : 0
        if openFolder != nil {
            folderMotion.release(velocity: pagesPerSecond)
            if target != folderPage {
                folderPage = target
                folderSelectedIndex = nil
            }
        } else {
            gridMotion.release(velocity: pagesPerSecond)
            if target != currentPage {
                currentPage = target
                selectedIndex = nil
            }
        }
        onNeedsFrames?()
    }

    func advancePager(by dt: CGFloat) {
        if gridMotion.isActive {
            gridMotion.advance(page: currentPage, pageCount: pages.count, pageWidth: pageWidth, dt: dt)
            if gridPosition != gridMotion.position {
                gridPosition = gridMotion.position
            }
        }
        if folderMotion.isActive {
            folderMotion.advance(page: folderPage, pageCount: folderPages.count, pageWidth: pageWidth, dt: dt)
            if folderPosition != folderMotion.position {
                folderPosition = folderMotion.position
            }
        }
    }

    private func setGridPage(_ page: Int, animated: Bool) {
        currentPage = page
        if animated {
            gridMotion.settle()
            onNeedsFrames?()
        } else {
            gridMotion.jump(to: page)
            gridPosition = CGFloat(page)
        }
    }

    private func setFolderPage(_ page: Int, animated: Bool) {
        folderPage = page
        if animated {
            folderMotion.settle()
            onNeedsFrames?()
        } else {
            folderMotion.jump(to: page)
            folderPosition = CGFloat(page)
        }
    }

    func setQuery(_ newQuery: String) {
        guard newQuery != query else {
            return
        }
        query = newQuery
        setGridPage(0, animated: false)
        if newQuery.isEmpty {
            selectedIndex = nil
        } else {
            isJiggling = false
            closeFolder()
            selectedIndex = visibleItems.isEmpty ? nil : 0
        }
    }

    func selectPage(_ index: Int) {
        closeFolder()
        setGridPage(clampedPage(index), animated: true)
        selectedIndex = nil
    }

    func selectFolderPage(_ index: Int) {
        setFolderPage(LauncherPagination.normalizedPageIndex(index, pageCount: folderPages.count), animated: true)
        folderSelectedIndex = nil
    }

    func turnPage(_ direction: PageDirection) {
        let step = direction == .next ? 1 : -1
        if openFolder != nil {
            selectFolderPage(folderPage + step)
        } else {
            selectPage(currentPage + step)
        }
    }

    func showFolder(id: String) {
        openFolderID = id
        setFolderPage(0, animated: false)
        folderSelectedIndex = nil
    }

    func beginRenamingFolder() {
        guard canEditLayout, let folder = openFolder else {
            return
        }
        folderNameDraft = folder.name
        renamingFolderID = folder.id
    }

    func finishRenamingFolder() {
        guard let folderID = renamingFolderID else {
            return
        }
        renamingFolderID = nil
        onEdit?(.renameFolder(folder: folderID, name: folderNameDraft))
    }

    func cancelRenamingFolder() {
        renamingFolderID = nil
    }

    func beginJiggling() {
        guard canDragItems else {
            return
        }
        isJiggling = true
    }

    func endJiggling() {
        isJiggling = false
    }

    func uninstallTarget(at point: CGPoint) -> CatalogApp? {
        guard isJiggling,
              let homeLayout,
              let press = itemPress(at: point),
              case .app(let app) = press.item,
              canUninstall(app),
              let tile = frame(of: press.origin) else {
            return nil
        }
        return homeLayout.uninstallBadgeFrame(inTile: tile).insetBy(dx: -6, dy: -6).contains(point) ? app : nil
    }

    func closeFolder() {
        finishRenamingFolder()
        openFolderID = nil
        setFolderPage(0, animated: false)
        folderSelectedIndex = nil
    }

    func moveSelection(_ direction: MoveDirection) {
        if openFolder != nil {
            let current = folderSelectedIndex.map { GridPosition(page: folderPage, index: $0) }
            if let next = GridNavigator.move(
                from: current,
                direction: direction,
                currentPage: folderPage,
                pageSizes: folderPages.map(\.count),
                columns: LauncherHomeLayout.columnCount
            ) {
                if next.page != folderPage {
                    setFolderPage(next.page, animated: true)
                }
                folderSelectedIndex = next.index
            }
            return
        }
        let current = selectedIndex.map { GridPosition(page: currentPage, index: $0) }
        if let next = GridNavigator.move(
            from: current,
            direction: direction,
            currentPage: currentPage,
            pageSizes: pages.map(\.count),
            columns: LauncherHomeLayout.columnCount
        ) {
            if next.page != currentPage {
                setGridPage(next.page, animated: true)
            }
            selectedIndex = next.index
        }
    }

    func activateSelection() -> CatalogApp? {
        if openFolder != nil {
            guard let index = folderSelectedIndex, visibleFolderApps.indices.contains(index) else {
                return nil
            }
            return visibleFolderApps[index]
        }
        guard let index = selectedIndex, visibleItems.indices.contains(index) else {
            return nil
        }
        switch visibleItems[index] {
        case .app(let app):
            return app
        case .folder(let folder):
            showFolder(id: folder.id)
            folderSelectedIndex = folderPages.isEmpty ? nil : 0
            return nil
        case .empty:
            return nil
        }
    }

    func prepareForPresentation() {
        isJiggling = false
        closeFolder()
        setQuery("")
        selectedIndex = nil
        setGridPage(clampedPage(currentPage), animated: false)
        presentationCount += 1
    }

    func handleEscape() -> EscapeOutcome {
        if renamingFolderID != nil {
            cancelRenamingFolder()
            return .cancelledRename
        }
        if let folderID = openFolderID {
            closeFolder()
            selectedIndex = visibleItems.firstIndex { item in
                if case .folder(let folder) = item {
                    return folder.id == folderID
                }
                return false
            }
            return .closedFolder
        }
        if isJiggling {
            endJiggling()
            return .stoppedJiggling
        }
        guard !query.isEmpty else {
            return .close
        }
        setQuery("")
        return .clearedQuery
    }

    func updateApps(_ newApps: [CatalogApp]) {
        apps = newApps
        normalizeState()
    }

    func updateLayout(_ pages: [[ResolvedItem]]) {
        guard dragSession == nil else {
            pendingLayout = pages
            return
        }
        layoutPages = pages
        normalizeState()
    }

    private func normalizeState() {
        let page = clampedPage(currentPage)
        if page != currentPage {
            setGridPage(page, animated: false)
        }
        selectedIndex = clampedSelection(selectedIndex, count: visibleItems.count)
        if openFolderID != nil, openFolder == nil {
            closeFolder()
        } else if openFolder != nil {
            let page = LauncherPagination.normalizedPageIndex(folderPage, pageCount: folderPages.count)
            if page != folderPage {
                setFolderPage(page, animated: false)
            }
            folderSelectedIndex = clampedSelection(folderSelectedIndex, count: visibleFolderApps.count)
        }
    }

    private func clampedSelection(_ index: Int?, count: Int) -> Int? {
        guard let index, count > 0 else {
            return nil
        }
        return min(index, count - 1)
    }

    private func clampedPage(_ index: Int) -> Int {
        LauncherPagination.normalizedPageIndex(index, pageCount: pages.count)
    }
}
