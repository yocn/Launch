import LaunchCore

struct ArrangeOptions: Equatable {
    enum Scope: Equatable {
        case currentPage
        case chosenPages
        case allPages
    }

    var fillsGaps = true
    var ungroupsFolders = false
    var groupsByCategory = false
    var scope = Scope.allPages
    var chosenPages: Set<Int> = []

    func pages(currentPage: Int, pageCount: Int) -> [Int] {
        switch scope {
        case .currentPage:
            [currentPage]
        case .chosenPages:
            chosenPages.filter { (0 ..< pageCount).contains($0) }.sorted()
        case .allPages:
            Array(0 ..< pageCount)
        }
    }

    // 只有一页时没有可填的空位
    func canFillGaps(currentPage: Int, pageCount: Int) -> Bool {
        pages(currentPage: currentPage, pageCount: pageCount).count >= 2
    }

    func arrangement(currentPage: Int, pageCount: Int) -> LayoutArrangement? {
        let pages = pages(currentPage: currentPage, pageCount: pageCount)
        let fills = fillsGaps && pages.count >= 2
        guard !pages.isEmpty, fills || ungroupsFolders || groupsByCategory else {
            return nil
        }
        return LayoutArrangement(pages: pages, fillsGaps: fills, ungroupsFolders: ungroupsFolders, groupsByCategory: groupsByCategory)
    }
}
