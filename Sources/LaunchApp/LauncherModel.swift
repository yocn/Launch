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
    private(set) var presentationCount = 0
    private(set) var openFolderID: String?

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

    func setQuery(_ newQuery: String) {
        guard newQuery != query else {
            return
        }
        query = newQuery
        currentPage = 0
        if !newQuery.isEmpty {
            openFolderID = nil
        }
    }

    func selectPage(_ index: Int) {
        openFolderID = nil
        currentPage = clampedPage(index)
    }

    func showFolder(id: String) {
        openFolderID = id
    }

    func closeFolder() {
        openFolderID = nil
    }

    func prepareForPresentation() {
        openFolderID = nil
        setQuery("")
        currentPage = clampedPage(currentPage)
        presentationCount += 1
    }

    func handleEscape() -> EscapeOutcome {
        if openFolderID != nil {
            openFolderID = nil
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
        currentPage = clampedPage(currentPage)
    }

    func updateLayout(_ pages: [[ResolvedItem]]) {
        layoutPages = pages
        currentPage = clampedPage(currentPage)
        if openFolderID != nil, openFolder == nil {
            openFolderID = nil
        }
    }

    private func clampedPage(_ index: Int) -> Int {
        LauncherPagination.normalizedPageIndex(index, pageCount: pages.count)
    }
}
