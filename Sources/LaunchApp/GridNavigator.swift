enum MoveDirection: Equatable {
    case left
    case right
    case up
    case down
}

struct GridPosition: Equatable {
    var page: Int
    var index: Int
}

enum GridNavigator {
    static func move(
        from position: GridPosition?,
        direction: MoveDirection,
        currentPage: Int,
        pageSizes: [Int],
        columns: Int
    ) -> GridPosition? {
        guard pageSizes.indices.contains(currentPage), pageSizes[currentPage] > 0 else {
            return position
        }
        guard let position,
              pageSizes.indices.contains(position.page),
              position.index < pageSizes[position.page] else {
            return GridPosition(page: currentPage, index: 0)
        }
        let size = pageSizes[position.page]
        let index = position.index
        switch direction {
        case .right:
            if index + 1 < size {
                return GridPosition(page: position.page, index: index + 1)
            }
            if position.page + 1 < pageSizes.count, pageSizes[position.page + 1] > 0 {
                return GridPosition(page: position.page + 1, index: 0)
            }
            return position
        case .left:
            if index > 0 {
                return GridPosition(page: position.page, index: index - 1)
            }
            if position.page > 0, pageSizes[position.page - 1] > 0 {
                return GridPosition(page: position.page - 1, index: pageSizes[position.page - 1] - 1)
            }
            return position
        case .down:
            guard index / columns < (size - 1) / columns else {
                return position
            }
            return GridPosition(page: position.page, index: min(index + columns, size - 1))
        case .up:
            guard index >= columns else {
                return position
            }
            return GridPosition(page: position.page, index: index - columns)
        }
    }
}
