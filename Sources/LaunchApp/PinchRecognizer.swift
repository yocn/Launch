import CoreGraphics

enum PinchDirection {
    case pinchIn, spreadOut
}

// 所选手指数的触点一起向内收拢到起始距离的 75% 以内算向内捏合，向外张开到 1/0.75 倍以上算张开；手指数变化时从新的手指数重新开始
struct PinchRecognizer {
    var gesture = PinchGesture.off
    private var startSpread: CGFloat?
    private var startCount = 0
    private var fired = false

    // 触点为触控板上的归一化位置（0～1）
    mutating func update(touches: [CGPoint]) -> PinchDirection? {
        guard accepts(touches.count) else {
            end()
            return nil
        }
        let spread = Self.spread(of: touches)
        guard let start = startSpread, startCount == touches.count else {
            startSpread = spread
            startCount = touches.count
            fired = false
            return nil
        }
        guard !fired else {
            return nil
        }
        let direction: PinchDirection
        if spread < start * 0.75 {
            direction = .pinchIn
        } else if spread > start / 0.75 {
            direction = .spreadOut
        } else {
            return nil
        }
        fired = true
        return direction
    }

    mutating func end() {
        startSpread = nil
        startCount = 0
        fired = false
    }

    private func accepts(_ count: Int) -> Bool {
        switch gesture {
        case .off: false
        case .threeFingers: count == 3
        case .fourOrFiveFingers: count == 4 || count == 5
        case .fiveFingers: count == 5
        }
    }

    private static func spread(of touches: [CGPoint]) -> CGFloat {
        let count = CGFloat(touches.count)
        let center = CGPoint(x: touches.map(\.x).reduce(0, +) / count, y: touches.map(\.y).reduce(0, +) / count)
        return touches.map { hypot($0.x - center.x, $0.y - center.y) }.reduce(0, +) / count
    }
}
