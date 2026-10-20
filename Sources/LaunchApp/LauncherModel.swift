import CoreGraphics
import LaunchCore
import Observation

enum EscapeOutcome: Equatable {
    case closedFolder
    case clearedQuery
    case close
}

@MainActor
@Observable
final class LauncherModel {
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
    // 以下每帧都会变化，不参与视图观察，否则每帧都会重建整个网格
    @ObservationIgnored private(set) var isPageDragging = false
    @ObservationIgnored private(set) var pageWidth: CGFloat = 0
    @ObservationIgnored private var gridMotion = PagerMotion()
    @ObservationIgnored private var folderMotion = PagerMotion()
    @ObservationIgnored var onNeedsFrames: (() -> Void)?

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
        return source.flatMap {
            LauncherPagination.pages($0, capacity: LauncherHomeLayout.pageCapacity)
        }
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
            pageCount: activePageCount
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

    func dragPage(by translation: CGFloat) {
        isPageDragging = true
        if openFolder != nil {
            folderMotion.updateDrag(translation: translation)
        } else {
            gridMotion.updateDrag(translation: translation)
        }
        onNeedsFrames?()
    }

    func endPageDrag(predictedTranslation: CGFloat, velocity: CGFloat = 0) {
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

    func closeFolder() {
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
        closeFolder()
        setQuery("")
        selectedIndex = nil
        setGridPage(clampedPage(currentPage), animated: false)
        presentationCount += 1
    }

    func handleEscape() -> EscapeOutcome {
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
