import Foundation
import LaunchCore

enum DragOrigin: Equatable {
    case grid(page: Int, index: Int)
    case folder(id: String, page: Int, index: Int)
}

enum DragArea: Equatable {
    case grid
    case folder
}

enum DragTarget: Equatable {
    // index 为去掉被拖项之后的位置
    case insert(page: Int, index: Int)
    // index 为页内原始位置
    case merge(page: Int, index: Int)

    var page: Int {
        switch self {
        case .insert(let page, _), .merge(let page, _):
            page
        }
    }
}

enum DragHit: Equatable {
    case target(DragTarget)
    case edge(PageDirection)
    case none
}

enum DragEvent: Equatable {
    case turnPage(PageDirection)
    case leaveFolder
}

enum PreviewEntry: Equatable {
    case item(Int)
    case gap
}

struct DragPreview: Equatable {
    let item: ResolvedItem
    let origin: DragOrigin
    // 一起拖动时各页被拿起项的位置（含按住的那个）；单项拖拽为空
    let group: [Int: [Int]]
    let area: DragArea
    let target: DragTarget?
    let hasExtraPage: Bool

    var isGroup: Bool {
        !group.isEmpty
    }

    var count: Int {
        isGroup ? group.values.reduce(0) { $0 + $1.count } : 1
    }

    var canMerge: Bool {
        if isGroup {
            return true
        }
        if case .app = item {
            return true
        }
        return false
    }

    func sourceIndex(onPage page: Int, in pageArea: DragArea) -> Int? {
        switch (origin, pageArea) {
        case (.grid(let sourcePage, let index), .grid) where sourcePage == page:
            index
        case (.folder(_, let sourcePage, let index), .folder) where sourcePage == page:
            index
        default:
            nil
        }
    }

    func sourceIndices(onPage page: Int, in pageArea: DragArea) -> [Int] {
        guard isGroup else {
            return sourceIndex(onPage: page, in: pageArea).map { [$0] } ?? []
        }
        return pageArea == .grid ? group[page] ?? [] : []
    }

    func entries(page: Int, itemCount: Int, capacity: Int, in pageArea: DragArea) -> [PreviewEntry] {
        if isGroup {
            return groupEntries(page: page, itemCount: itemCount, capacity: capacity, in: pageArea)
        }
        var entries = (0 ..< itemCount).map(PreviewEntry.item)
        let source = sourceIndex(onPage: page, in: pageArea)
        let isActive = pageArea == area
        if isActive, case .insert(let targetPage, let index)? = target, targetPage == page {
            if let source {
                entries.remove(at: source)
            }
            entries.insert(.gap, at: min(index, entries.count))
            return Array(entries.prefix(capacity))
        }
        guard let source else {
            return entries
        }
        if isActive, let target, target.page != page {
            entries.remove(at: source)
        } else {
            entries[source] = .gap
        }
        return entries
    }

    private func groupEntries(page: Int, itemCount: Int, capacity: Int, in pageArea: DragArea) -> [PreviewEntry] {
        let sources = Set(sourceIndices(onPage: page, in: pageArea))
        var entries = (0 ..< itemCount).filter { !sources.contains($0) }.map(PreviewEntry.item)
        if pageArea == area, case .insert(let targetPage, let index)? = target, targetPage == page {
            entries.insert(contentsOf: repeatElement(.gap, count: count), at: min(index, entries.count))
            return Array(entries.prefix(capacity))
        }
        return entries
    }

    func hit(for gridHit: GridHit, entries: [PreviewEntry], itemCount: Int, page: Int, in pageArea: DragArea) -> DragHit {
        let sources = sourceIndices(onPage: page, in: pageArea)
        switch gridHit {
        case .outside:
            return .none
        case .edge(let direction):
            return pageArea == .grid ? .edge(direction) : .none
        case .end:
            return .target(.insert(page: page, index: itemCount - sources.count))
        case .item(let cell, let zone):
            guard case .item(let index) = entries[cell] else {
                // 一组空位都代表当前插入位置
                if isGroup, pageArea == area, let target, case .insert = target, target.page == page {
                    return .target(target)
                }
                return .target(.insert(page: page, index: cell))
            }
            if zone == .center, canMerge, pageArea == .grid {
                return .target(.merge(page: page, index: index))
            }
            let remaining = index - sources.filter { $0 < index }.count
            return .target(.insert(page: page, index: zone == .trailing ? remaining + 1 : remaining))
        }
    }
}

struct DragSession {
    static let insertDwell: TimeInterval = 0.15
    static let mergeDwell: TimeInterval = 0.1
    static let folderExitDwell: TimeInterval = 0.3
    static let edgeDwell: TimeInterval = 0.5
    static let edgeRepeat: TimeInterval = 0.8

    let item: ResolvedItem
    let origin: DragOrigin
    let group: [Int: [Int]]
    private(set) var area: DragArea
    private(set) var target: DragTarget?
    private(set) var hasExtraPage = false
    private var candidate: DragTarget?
    private var candidateSince: TimeInterval = 0
    private var edgeDirection: PageDirection?
    private var edgeSince: TimeInterval = 0
    private var edgeTurns = 0
    private var outsideFolderSince: TimeInterval?

    init(item: ResolvedItem, origin: DragOrigin, group: [Int: [Int]] = [:]) {
        self.item = item
        self.origin = origin
        self.group = group
        if case .folder = origin {
            area = .folder
        } else {
            area = .grid
        }
    }

    var preview: DragPreview {
        DragPreview(item: item, origin: origin, group: group, area: area, target: target, hasExtraPage: hasExtraPage)
    }

    mutating func addExtraPage() {
        hasExtraPage = true
    }

    mutating func update(hit: DragHit, outsideFolder: Bool, now: TimeInterval) -> [DragEvent] {
        if area == .folder {
            guard outsideFolder else {
                outsideFolderSince = nil
                updateTarget(hit: hit, now: now)
                return []
            }
            let since = outsideFolderSince ?? now
            outsideFolderSince = since
            guard now - since >= Self.folderExitDwell else {
                return []
            }
            area = .grid
            target = nil
            candidate = nil
            outsideFolderSince = nil
            return [.leaveFolder]
        }
        guard case .edge(let direction) = hit else {
            edgeDirection = nil
            updateTarget(hit: hit, now: now)
            return []
        }
        candidate = nil
        if edgeDirection != direction {
            edgeDirection = direction
            edgeSince = now
            edgeTurns = 0
        }
        guard now - edgeSince >= Self.edgeDwell + Self.edgeRepeat * TimeInterval(edgeTurns) else {
            return []
        }
        edgeTurns += 1
        target = nil
        return [.turnPage(direction)]
    }

    // 松手时还没等到停留时间的合并目标按插入处理
    func dropTarget(for hit: DragHit) -> DragTarget? {
        guard case .target(let hitTarget) = hit else {
            return target
        }
        guard hitTarget != target, case .merge(let page, let index) = hitTarget else {
            return hitTarget
        }
        let sources = preview.sourceIndices(onPage: page, in: area)
        return .insert(page: page, index: index - sources.filter { $0 < index }.count)
    }

    private mutating func updateTarget(hit: DragHit, now: TimeInterval) {
        guard case .target(let hitTarget) = hit else {
            candidate = nil
            return
        }
        if candidate != hitTarget {
            candidate = hitTarget
            candidateSince = now
        }
        var dwell = Self.insertDwell
        if case .merge = hitTarget {
            dwell = Self.mergeDwell
        }
        if now - candidateSince >= dwell {
            target = hitTarget
        }
    }
}
