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
    var rowCount = LauncherHomeLayout.rowCount

    private var columnPitch: CGFloat { layout.tileWidth + layout.columnSpacing }
    private var rowPitch: CGFloat { layout.tileHeight + layout.rowSpacing }

    func tileRect(_ index: Int) -> CGRect {
        let column = index % LauncherHomeLayout.columnCount
        let row = index / LauncherHomeLayout.columnCount
        return CGRect(
            x: frame.minX + layout.horizontalInset + CGFloat(column) * columnPitch,
            y: frame.minY + CGFloat(row) * rowPitch,
            width: layout.tileWidth,
            height: layout.tileHeight
        )
    }

    func tileIndex(at point: CGPoint, itemCount: Int) -> Int? {
        (0 ..< itemCount).first { tileRect($0).contains(point) }
    }

    func hit(_ point: CGPoint, itemCount: Int) -> GridHit {
        guard point.y >= frame.minY - layout.rowSpacing, point.y <= frame.maxY + layout.rowSpacing else {
            return .outside
        }
        let edgeWidth = layout.horizontalInset / 2
        if point.x < frame.minX + edgeWidth {
            return .edge(.previous)
        }
        if point.x > frame.maxX - edgeWidth {
            return .edge(.next)
        }
        let rawColumn = (point.x - frame.minX - layout.horizontalInset + layout.columnSpacing / 2) / columnPitch
        let rawRow = (point.y - frame.minY + layout.rowSpacing / 2) / rowPitch
        let column = min(max(Int(rawColumn.rounded(.down)), 0), LauncherHomeLayout.columnCount - 1)
        let row = min(max(Int(rawRow.rounded(.down)), 0), rowCount - 1)
        let index = row * LauncherHomeLayout.columnCount + column
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
