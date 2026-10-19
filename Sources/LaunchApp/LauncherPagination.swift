enum LauncherPagination {
    static func pages<Item>(_ items: [Item], capacity: Int) -> [[Item]] {
        precondition(capacity > 0)

        return stride(from: 0, to: items.count, by: capacity).map { start in
            Array(items[start ..< min(start + capacity, items.count)])
        }
    }

    static func normalizedPageIndex(_ requestedIndex: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else {
            return 0
        }
        return min(max(requestedIndex, 0), pageCount - 1)
    }
}
