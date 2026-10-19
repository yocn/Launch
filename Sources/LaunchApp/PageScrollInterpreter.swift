import CoreGraphics
import Foundation

enum PageDirection: Equatable {
    case next
    case previous
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
    var threshold: CGFloat = 40
    var wheelInterval: TimeInterval = 0.35
    var burstGap: TimeInterval = 0.25
    private var accumulated: CGFloat = 0
    private var hasTurned = false
    private var lastWheelTurn: TimeInterval?
    private var lastPreciseSample: TimeInterval?

    mutating func interpret(_ sample: ScrollSample) -> PageDirection? {
        guard !sample.isMomentum else {
            return nil
        }
        return sample.isPrecise ? interpretGesture(sample) : interpretWheel(sample)
    }

    private mutating func interpretGesture(_ sample: ScrollSample) -> PageDirection? {
        // Mos 等平滑滚动工具产生无阶段的精确滚动，只能按时间间隔划分一次手势
        let startsBurst = sample.phase == .none
            && lastPreciseSample.map { sample.timestamp - $0 > burstGap } ?? true
        lastPreciseSample = sample.timestamp
        if sample.phase == .began || startsBurst {
            accumulated = 0
            hasTurned = false
        }
        defer {
            if sample.phase == .ended {
                accumulated = 0
                hasTurned = false
            }
        }
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
}
