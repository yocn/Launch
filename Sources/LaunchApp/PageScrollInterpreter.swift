import CoreGraphics
import Foundation

enum PageDirection: Equatable {
    case next
    case previous
}

enum ScrollAction: Equatable {
    case turn(PageDirection)
    case drag(CGFloat)
    case endDrag(predictedTranslation: CGFloat)
}

struct ScrollSample: Equatable {
    enum Phase: Equatable {
        case none
        case began
        case changed
        case ended
    }

    var deltaX: CGFloat
    var deltaY: CGFloat
    var isPrecise: Bool
    var phase: Phase
    var isMomentum: Bool
    var timestamp: TimeInterval
}

struct PageScrollInterpreter {
    private enum Axis {
        case horizontal
        case vertical
    }

    var threshold: CGFloat = 40
    var wheelInterval: TimeInterval = 0.35
    var burstGap: TimeInterval = 0.25
    var axisLockDistance: CGFloat = 4
    var flingDuration: TimeInterval = 0.2
    private var accumulated: CGFloat = 0
    private var hasTurned = false
    private var lastWheelTurn: TimeInterval?
    private var lastPreciseSample: TimeInterval?
    private var gestureAxis: Axis?
    private var gestureX: CGFloat = 0
    private var gestureY: CGFloat = 0
    private var recentDeltas: [(delta: CGFloat, time: TimeInterval)] = []

    mutating func interpret(_ sample: ScrollSample) -> ScrollAction? {
        guard !sample.isMomentum else {
            return nil
        }
        guard sample.isPrecise else {
            return interpretWheel(sample).map(ScrollAction.turn)
        }
        guard sample.phase != .none else {
            return interpretBurst(sample).map(ScrollAction.turn)
        }
        return interpretGesture(sample)
    }

    private mutating func interpretGesture(_ sample: ScrollSample) -> ScrollAction? {
        if sample.phase == .began {
            resetGesture()
        }
        defer {
            if sample.phase == .ended {
                resetGesture()
            }
        }
        gestureX += sample.deltaX
        gestureY += sample.deltaY
        if gestureAxis == nil, max(abs(gestureX), abs(gestureY)) >= axisLockDistance {
            gestureAxis = abs(gestureX) >= abs(gestureY) ? .horizontal : .vertical
        }
        switch gestureAxis {
        case .horizontal:
            recentDeltas = Array((recentDeltas + [(sample.deltaX, sample.timestamp)]).suffix(4))
            if sample.phase == .ended {
                return .endDrag(predictedTranslation: gestureX + velocity() * flingDuration)
            }
            return .drag(gestureX)
        case .vertical:
            guard !hasTurned, abs(gestureY) >= threshold else {
                return nil
            }
            hasTurned = true
            return .turn(gestureY < 0 ? .next : .previous)
        case nil:
            return nil
        }
    }

    // Mos 等平滑滚动工具产生无阶段的精确滚动，只能按时间间隔划分一次手势
    private mutating func interpretBurst(_ sample: ScrollSample) -> PageDirection? {
        if lastPreciseSample.map({ sample.timestamp - $0 > burstGap }) ?? true {
            accumulated = 0
            hasTurned = false
        }
        lastPreciseSample = sample.timestamp
        accumulated += abs(sample.deltaX) >= abs(sample.deltaY) ? sample.deltaX : sample.deltaY
        guard !hasTurned, abs(accumulated) >= threshold else {
            return nil
        }
        hasTurned = true
        return accumulated < 0 ? .next : .previous
    }

    private mutating func interpretWheel(_ sample: ScrollSample) -> PageDirection? {
        let delta = sample.deltaY != 0 ? sample.deltaY : sample.deltaX
        guard delta != 0 else {
            return nil
        }
        if let lastWheelTurn, sample.timestamp - lastWheelTurn < wheelInterval {
            return nil
        }
        lastWheelTurn = sample.timestamp
        return delta < 0 ? .next : .previous
    }

    private mutating func resetGesture() {
        gestureAxis = nil
        gestureX = 0
        gestureY = 0
        hasTurned = false
        recentDeltas = []
    }

    private func velocity() -> CGFloat {
        guard let first = recentDeltas.first, let last = recentDeltas.last, last.time > first.time else {
            return 0
        }
        let travelled = recentDeltas.dropFirst().reduce(0) { $0 + $1.delta }
        return travelled / CGFloat(last.time - first.time)
    }
}
