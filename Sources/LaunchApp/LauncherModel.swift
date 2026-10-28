import CoreGraphics
import Foundation
import LaunchCore
import Observation

enum EscapeOutcome: Equatable {
    case cancelledRename
    case closedFolder
    case clearedSelection
    case stoppedJiggling
    case clearedQuery
    case close
}

struct ScrollRequest: Equatable {
    enum Kind: Equatable {
        case page(Int)
        case by(CGFloat)
    }

    let kind: Kind
    let serial: Int
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
        let isPicked: Bool
    }

    struct Landing: Equatable {
        let entryIDs: Set<String>
        let from: CGRect
    }

    private(set) var catalog: [LaunchItem] {
        didSet { searchIndex = SearchIndex(items: catalog) }
    }
    private(set) var layoutPages: [[ResolvedItem]]?
    private(set) var query = ""
    private(set) var grid = GridSize.default
    var browsingStyle = BrowsingStyle.paged
    var displayMode = DisplayMode.fullScreen
    // 滚动浏览时交给视图执行：滚到某页，或拖动靠近上下边缘时滚一段
    var scrollRequest: ScrollRequest?
    @ObservationIgnored var scrollSerial = 0
    // 滚动浏览时各页网格的全局位置；分页时只用 gridFrame
    @ObservationIgnored var pageFrames: [Int: CGRect] = [:]
    @ObservationIgnored var lastAutoScroll: TimeInterval?
    private(set) var displaySort = DisplaySort()
    // 非自定义排序时为排好的一串，其余情况与 layoutPages 相同
    private(set) var arrangedPages: [[ResolvedItem]]?
    private(set) var hint: String?
    @ObservationIgnored private var appDates: [String: AppDates] = [:]
    @ObservationIgnored private var hintGeneration = 0
    var currentPage = 0
    var pageBeforeSearch = 0
    var selectedIndex: Int?
    private(set) var presentationCount = 0
    private(set) var openFolderID: String?
    private(set) var folderPage = 0
    var folderSelectedIndex: Int?
    private(set) var gridPosition: CGFloat = 0
    private(set) var folderPosition: CGFloat = 0
    var dragPreview: DragPreview?
    var landing: Landing?
    private(set) var isJiggling = false
    private(set) var renamingFolderID: String?
    var multiSelection = MultiSelection()
    var marqueeRect: CGRect?
    private(set) var isPresented = false
    private(set) var hiddenItems: [LaunchItem] = []
    private(set) var wallpaper: Wallpaper?
    var showsHiddenAppsInSearch = false
    // 距上次关闭达到这个时长就回到第一页；为空表示从不
    @ObservationIgnored var returnToFirstPageDelay: TimeInterval?
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored private var hiddenAt: Date?
    var folderNameDraft = ""
    // 以下每帧都会变化，不参与视图观察，否则每帧都会重建整个网格
    @ObservationIgnored private(set) var isPageDragging = false
    @ObservationIgnored private(set) var pageWidth: CGFloat = 0
    @ObservationIgnored private var gridMotion = PagerMotion()
    @ObservationIgnored private var folderMotion = PagerMotion()
    @ObservationIgnored var onNeedsFrames: (() -> Void)?
    @ObservationIgnored var onEdit: ((LayoutEdit) -> Void)?
    @ObservationIgnored var canEditLayout = false
    @ObservationIgnored var canUninstall: (LaunchItem) -> Bool = { _ in false }
    @ObservationIgnored var homeLayout: LauncherHomeLayout?
    @ObservationIgnored var gridFrame: CGRect = .zero
    @ObservationIgnored var folderGridFrame: CGRect = .zero
    @ObservationIgnored var dragSession: DragSession?
    @ObservationIgnored var dragStartPoint: CGPoint = .zero
    @ObservationIgnored var pendingLayout: [[ResolvedItem]]?
    // ⌘ 或 ⌃ 按下的点击；SwiftUI 的翻页与点空白手势不受事件监听拦截，靠它忽略
    @ObservationIgnored var isModifiedClick = false
    @ObservationIgnored var marqueeStart: CGPoint?
    @ObservationIgnored var dragGroup: [LayoutItemID] = []
    @ObservationIgnored private var searchIndex: SearchIndex

    init(catalog: [LaunchItem] = []) {
        self.catalog = catalog
        searchIndex = SearchIndex(items: catalog)
    }

    var results: [LaunchItem] {
        // searchIndex 不参与观察，读一次 catalog 让搜索结果随条目变化刷新
        _ = catalog
        let hidden = showsHiddenAppsInSearch ? [] : Set(hiddenItems.map(\.identity))
        return searchIndex.results(for: query, hidden: hidden)
    }

    var pages: [[ResolvedItem]] {
        let source: [[ResolvedItem]]
        if query.isEmpty, let arrangedPages {
            source = arrangedPages
        } else {
            source = [results.map(ResolvedItem.item)]
        }
        let paged = source.flatMap {
            LauncherPagination.pages($0, capacity: grid.capacity)
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
        guard let openFolderID, let arrangedPages else {
            return nil
        }
        for item in arrangedPages.joined() {
            if case .folder(let folder) = item, folder.id == openFolderID {
                return folder
            }
        }
        return nil
    }

    var folderPages: [[LaunchItem]] {
        guard let openFolder else {
            return []
        }
        return LauncherPagination.pages(openFolder.items, capacity: grid.capacity)
    }

    var visibleFolderApps: [LaunchItem] {
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
        canEditLayout && query.isEmpty && layoutPages != nil && renamingFolderID == nil && displaySort.field == .custom
    }


    func updateDisplaySort(_ sort: DisplaySort) {
        guard sort != displaySort else {
            return
        }
        displaySort = sort
        rearrange()
    }

    func updateAppDates(_ dates: [String: AppDates]) {
        appDates = dates
        if displaySort.field == .dateAdded || displaySort.field == .lastUsed {
            rearrange()
        }
    }

    // 从图标上拖动却因排序不能拖时提示
    func notifyBlockedDrag() {
        guard displaySort.field != .custom, canEditLayout, query.isEmpty, layoutPages != nil else {
            return
        }
        showHint("仅在自定义排序时可以拖动调整顺序")
    }

    // 耗时操作期间一直显示，传 nil 收起
    func setProgressHint(_ text: String?) {
        hintGeneration += 1
        hint = text
    }

    func showHint(_ text: String) {
        hintGeneration += 1
        let generation = hintGeneration
        hint = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, hintGeneration == generation else {
                return
            }
            hint = nil
        }
    }

    private func rearrange() {
        if let layoutPages, displaySort.field != .custom {
            arrangedPages = [DisplaySorter.sorted(layoutPages, by: displaySort, dates: appDates)]
        } else {
            arrangedPages = layoutPages
        }
        normalizeState()
    }



    func dragPage(by translation: CGFloat) {
        // 发起图标拖拽的那次拖动事件也会被转给 SwiftUI 翻页手势，且它永远收不到结束
        guard dragSession == nil, !isModifiedClick, browsingStyle == .paged || openFolder != nil else {
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

    func setGridPage(_ page: Int, animated: Bool) {
        currentPage = page
        if browsingStyle == .scroll {
            requestScroll(.page(page))
        }
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
        if query.isEmpty && !newQuery.isEmpty { pageBeforeSearch = currentPage }
        query = newQuery
        setGridPage(0, animated: false)
        if newQuery.isEmpty {
            selectedIndex = nil
        } else {
            isJiggling = false
            clearMultiSelection()
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

    func uninstallTarget(at point: CGPoint) -> LaunchItem? {
        guard isJiggling,
              let homeLayout,
              let press = itemPress(at: point),
              case .item(let app) = press.item,
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
                columns: grid.columns
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
            columns: grid.columns,
            crossesPagesVertically: browsingStyle == .scroll
        ) {
            if next.page != currentPage {
                setGridPage(next.page, animated: true)
            }
            selectedIndex = next.index
        }
    }

    func activateSelection() -> LaunchItem? {
        if clearMultiSelection() {
            return nil
        }
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
        case .item(let app):
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
        clearMultiSelection()
        closeFolder()
        setQuery("")
        selectedIndex = nil
        let returnsHome = returnToFirstPageDelay.map { delay in
            hiddenAt.map { now().timeIntervalSince($0) >= delay } ?? true
        } ?? false
        setGridPage(returnsHome ? 0 : clampedPage(currentPage), animated: false)
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
        if clearMultiSelection() {
            return .clearedSelection
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

    func updateCatalog(_ items: [LaunchItem]) {
        catalog = items
        normalizeState()
    }

    func updateGrid(_ newGrid: GridSize) {
        guard newGrid != grid else {
            return
        }
        grid = newGrid
        normalizeState()
    }

    // 正在取网站图标的条目，网格里显示转圈
    private(set) var fetchingIcons: Set<ItemIdentity> = []

    func updateFetchingIcons(_ identities: Set<ItemIdentity>) {
        if identities != fetchingIcons { fetchingIcons = identities }
    }

    func updateHiddenItems(_ items: [LaunchItem]) {
        guard items != hiddenItems else {
            return
        }
        hiddenItems = items
        normalizeState()
    }

    func isHiddenItem(_ item: LaunchItem) -> Bool {
        hiddenItems.contains(item)
    }

    func updateWallpaper(_ wallpaper: Wallpaper?) {
        self.wallpaper = wallpaper
    }

    func setPresented(_ presented: Bool) {
        isPresented = presented
        if !presented {
            hiddenAt = now()
        }
    }

    func updateLayout(_ pages: [[ResolvedItem]]) {
        guard dragSession == nil else {
            pendingLayout = pages
            return
        }
        layoutPages = pages
        rearrange()
    }

    func normalizeState() {
        if let layoutPages {
            var selection = multiSelection
            selection.retain(Set(layoutPages.joined().compactMap(\.layoutID)))
            setMultiSelection(selection)
        }
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

    func clampedPage(_ index: Int) -> Int {
        LauncherPagination.normalizedPageIndex(index, pageCount: pages.count)
    }
}
