import AppKit

enum HotCorner: String, CaseIterable, Sendable {
    case off
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    private static let reach: CGFloat = 2

    // 屏幕坐标原点在主屏左下角、向上为正；指针贴边时可能正好落在最大边上
    func contains(_ point: CGPoint, screens: [CGRect]) -> Bool {
        guard self != .off else {
            return false
        }
        return screens.contains { frame in
            guard frame.insetBy(dx: -1, dy: -1).contains(point) else {
                return false
            }
            let left = point.x - frame.minX <= Self.reach
            let right = frame.maxX - point.x <= Self.reach
            let bottom = point.y - frame.minY <= Self.reach
            let top = frame.maxY - point.y <= Self.reach
            switch self {
            case .off: return false
            case .topLeft: return top && left
            case .topRight: return top && right
            case .bottomLeft: return bottom && left
            case .bottomRight: return bottom && right
            }
        }
    }

    var dockKey: String? {
        switch self {
        case .off: nil
        case .topLeft: "wvous-tl-corner"
        case .topRight: "wvous-tr-corner"
        case .bottomLeft: "wvous-bl-corner"
        case .bottomRight: "wvous-br-corner"
        }
    }
}

// 指针进入所选角时触发一次，离开后才能再次触发
struct HotCornerDetector {
    var corner = HotCorner.off
    private var isInside = false

    mutating func update(_ point: CGPoint, screens: [CGRect]) -> Bool {
        let inside = corner.contains(point, screens: screens)
        defer { isInside = inside }
        return inside && !isInside
    }
}

enum HotCornerConflicts {
    // 系统触发角取值 0 和 1 表示无动作
    static func system(_ corner: HotCorner, value: (String) -> Int?) -> Bool {
        guard let key = corner.dockKey else {
            return false
        }
        return (value(key) ?? 0) > 1
    }

    // LaunchOS 的取值顺序按其设置界面推测：1 左上、2 右上、3 左下、4 右下
    static func launchOSCorner(_ value: Int?) -> HotCorner? {
        switch value {
        case 1: .topLeft
        case 2: .topRight
        case 3: .bottomLeft
        case 4: .bottomRight
        default: nil
        }
    }
}
