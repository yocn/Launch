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

    func setQuery(_ newQuery: String) {
        guard newQuery != query else {
            return
        }
        query = newQuery
        currentPage = 0
        if newQuery.isEmpty {
            selectedIndex = nil
        } else {
            closeFolder()
            selectedIndex = visibleItems.isEmpty ? nil : 0
        }
    }

    func selectPage(_ index: Int) {
        closeFolder()
        currentPage = clampedPage(index)
        selectedIndex = nil
    }

    func selectFolderPage(_ index: Int) {
        folderPage = LauncherPagination.normalizedPageIndex(index, pageCount: folderPages.count)
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
        folderPage = 0
        folderSelectedIndex = nil
    }

    func closeFolder() {
        openFolderID = nil
        folderPage = 0
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
                folderPage = next.page
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
            currentPage = next.page
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
        currentPage = clampedPage(currentPage)
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
        currentPage = clampedPage(currentPage)
        selectedIndex = clampedSelection(selectedIndex, count: visibleItems.count)
        if openFolderID != nil, openFolder == nil {
            closeFolder()
        } else if openFolder != nil {
            folderPage = LauncherPagination.normalizedPageIndex(folderPage, pageCount: folderPages.count)
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
