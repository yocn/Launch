import CoreGraphics
import Foundation

struct PagerMotion: Equatable {
    static let springFrequency: CGFloat = 13
    static let dragSmoothing: CGFloat = 0.016

    private(set) var position: CGFloat = 0
    private(set) var dragTranslation: CGFloat?
    private var velocity: CGFloat = 0
    private var isSettling = false

    var isActive: Bool {
        dragTranslation != nil || isSettling
    }

    mutating func updateDrag(translation: CGFloat) {
        dragTranslation = translation
        isSettling = false
    }

    mutating func release(velocity pagesPerSecond: CGFloat) {
        dragTranslation = nil
        velocity = pagesPerSecond
        isSettling = true
    }

    mutating func settle() {
        dragTranslation = nil
        isSettling = true
    }

    mutating func jump(to page: Int) {
        position = CGFloat(page)
        velocity = 0
        dragTranslation = nil
        isSettling = false
    }

    mutating func advance(page: Int, pageCount: Int, pageWidth: CGFloat, dt: CGFloat) {
        if let dragTranslation {
            guard pageWidth > 0 else {
                return
            }
            let offset = PageDragResolver.displayOffset(
                translation: dragTranslation,
                currentPage: page,
                pageCount: pageCount
            )
            // 指针 125Hz 与屏幕 120Hz 不同步，直接取最新位置会停一帧再跳两步
            let target = CGFloat(page) - offset / pageWidth
            position += (target - position) * (1 - exp(-dt / Self.dragSmoothing))
            return
        }
        guard isSettling else {
            return
        }
        let target = CGFloat(page)
        let frequency = Self.springFrequency
        let distance = position - target
        var initialVelocity = velocity
        // 朝目标的初速度超过 ω·|x0| 时临界阻尼弹簧会冲过头，限幅为纯指数收敛
        if initialVelocity * distance < 0, abs(initialVelocity) > frequency * abs(distance) {
            initialVelocity = -frequency * distance
        }
        let coefficient = initialVelocity + frequency * distance
        let decay = exp(-frequency * dt)
        let remaining = (distance + coefficient * dt) * decay
        velocity = (initialVelocity - frequency * coefficient * dt) * decay
        position = target + remaining
        if abs(remaining) < 0.0005, abs(velocity) < 0.005 {
            position = target
            velocity = 0
            isSettling = false
        }
    }
}
