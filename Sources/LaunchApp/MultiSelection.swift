import LaunchCore

// 选框期间以按下前的选择为底，加上框到的项
struct MultiSelection: Equatable {
    private(set) var items: Set<LayoutItemID>
    private var marqueeBase: Set<LayoutItemID>?

    init(items: Set<LayoutItemID> = []) {
        self.items = items
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    var count: Int {
        items.count
    }

    func contains(_ item: LayoutItemID) -> Bool {
        items.contains(item)
    }

    mutating func toggle(_ item: LayoutItemID) {
        if items.remove(item) == nil {
            items.insert(item)
        }
    }

    mutating func beginMarquee() {
        marqueeBase = items
    }

    mutating func updateMarquee(hits: Set<LayoutItemID>) {
        items = (marqueeBase ?? items).union(hits)
    }

    mutating func endMarquee() {
        marqueeBase = nil
    }

    mutating func retain(_ existing: Set<LayoutItemID>) {
        items.formIntersection(existing)
        marqueeBase?.formIntersection(existing)
    }

    func ordered(in pages: [[ResolvedItem]]) -> [LayoutItemID] {
        pages.joined().compactMap(\.layoutID).filter(items.contains)
    }
}
