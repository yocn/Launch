import LaunchCore
import Observation

enum EscapeOutcome: Equatable {
    case clearedQuery
    case close
}

@MainActor
@Observable
final class LauncherModel {
    private(set) var apps: [CatalogApp]
    private(set) var query = ""
    private(set) var currentPage = 0
    private(set) var presentationCount = 0

    init(apps: [CatalogApp] = []) {
        self.apps = apps
    }

    var results: [CatalogApp] {
        SearchService.results(for: query, in: apps, hidden: [])
    }

    var pages: [[CatalogApp]] {
        LauncherPagination.pages(results, capacity: LauncherHomeLayout.pageCapacity)
    }

    var visibleApps: [CatalogApp] {
        let pages = pages
        guard !pages.isEmpty else {
            return []
        }
        return pages[LauncherPagination.normalizedPageIndex(currentPage, pageCount: pages.count)]
    }

    func setQuery(_ newQuery: String) {
        guard newQuery != query else {
            return
        }
        query = newQuery
        currentPage = 0
    }

    func selectPage(_ index: Int) {
        currentPage = clampedPage(index)
    }

    func prepareForPresentation() {
        setQuery("")
        currentPage = clampedPage(currentPage)
        presentationCount += 1
    }

    func handleEscape() -> EscapeOutcome {
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

    private func clampedPage(_ index: Int) -> Int {
        LauncherPagination.normalizedPageIndex(index, pageCount: pages.count)
    }
}
