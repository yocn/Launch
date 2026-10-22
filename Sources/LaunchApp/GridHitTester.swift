import CoreGraphics

enum GridHit: Equatable {
    enum Zone: Equatable {
        case leading
        case center
        case trailing
    }

    case item(Int, Zone)
    case end
    case edge(PageDirection)
    case outside
}

struct GridHitTester {
    let layout: LauncherHomeLayout
    // 网格单页可视区域在 SwiftUI 全局坐标中的位置
    let frame: CGRect
    var rowCount: Int
    // 文件夹用紧凑行距；主网格行距会随行数均分
    var rowSpacing: CGFloat
    // 滚动浏览时左右两侧不翻页
    var detectsPageEdges = true
    // 集中排列时首行离区域顶部的距离
    var topInset: CGFloat

    init(layout: LauncherHomeLayout, frame: CGRect, rowCount: Int? = nil, rowSpacing: CGFloat? = nil, topInset: CGFloat = 0) {
        self.layout = layout
        self.frame = frame
        self.rowCount = rowCount ?? layout.grid.rows
        self.rowSpacing = rowSpacing ?? layout.rowSpacing
        self.topInset = topInset
    }

    private var columns: Int { layout.grid.columns }
    private var columnPitch: CGFloat { layout.tileWidth + layout.columnSpacing }
    private var rowPitch: CGFloat { layout.tileHeight + rowSpacing }

    func tileRect(_ index: Int) -> CGRect {
        let column = index % columns
        let row = index / columns
        return CGRect(
            x: frame.minX + layout.horizontalInset + CGFloat(column) * columnPitch,
            y: frame.minY + topInset + CGFloat(row) * rowPitch,
            width: layout.tileWidth,
            height: layout.tileHeight
        )
    }

    func tileIndex(at point: CGPoint, itemCount: Int) -> Int? {
        (0 ..< itemCount).first { tileRect($0).contains(point) }
    }

    func tileIndices(intersecting rect: CGRect, itemCount: Int) -> [Int] {
        (0 ..< itemCount).filter { tileRect($0).intersects(rect) }
    }

    func hit(_ point: CGPoint, itemCount: Int) -> GridHit {
        guard point.y >= frame.minY - rowSpacing, point.y <= frame.maxY + rowSpacing else {
            return .outside
        }
        let edgeWidth = layout.horizontalInset / 2
        if detectsPageEdges, point.x < frame.minX + edgeWidth {
            return .edge(.previous)
        }
        if detectsPageEdges, point.x > frame.maxX - edgeWidth {
            return .edge(.next)
        }
        let rawColumn = (point.x - frame.minX - layout.horizontalInset + layout.columnSpacing / 2) / columnPitch
        let rawRow = (point.y - frame.minY - topInset + rowSpacing / 2) / rowPitch
        let column = min(max(Int(rawColumn.rounded(.down)), 0), columns - 1)
        let row = min(max(Int(rawRow.rounded(.down)), 0), rowCount - 1)
        let index = row * columns + column
        guard index < itemCount else {
            return .end
        }
        let rect = tileRect(index)
        let iconCenterY = rect.minY + layout.tilePadding + layout.iconSide / 2
        let reach = layout.iconSide * 0.3
        if abs(point.x - rect.midX) <= reach, abs(point.y - iconCenterY) <= reach {
            return .item(index, .center)
        }
        return .item(index, point.x < rect.midX ? .leading : .trailing)
    }
}
