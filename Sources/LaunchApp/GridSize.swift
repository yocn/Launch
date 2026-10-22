// 行列少、放不满时：间距拉开铺满屏幕，或按默认间距集中在中央
enum GridPlacement: String, CaseIterable {
    case spread
    case centered
}

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
