struct GridSize: Equatable, Sendable {
    static let `default` = GridSize(columns: 7, rows: 5)
    static let columnRange = 4 ... 10
    static let rowRange = 3 ... 8

    let columns: Int
    let rows: Int

    init(columns: Int, rows: Int) {
        self.columns = min(max(columns, Self.columnRange.lowerBound), Self.columnRange.upperBound)
        self.rows = min(max(rows, Self.rowRange.lowerBound), Self.rowRange.upperBound)
    }

    var capacity: Int {
        columns * rows
    }
}
