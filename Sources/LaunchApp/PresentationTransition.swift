import SwiftUI

// 参数按 LaunchOS 录屏逐帧测量
enum PresentationTransition {
    static let hiddenScale: CGFloat = 1.04
    static let hideDuration: TimeInterval = 0.22

    static func backgroundAnimation(presented: Bool) -> Animation {
        presented ? .easeOut(duration: 0.25) : .easeIn(duration: hideDuration)
    }

    static func scaleAnimation(presented: Bool) -> Animation {
        presented ? .easeOut(duration: 0.25) : .easeIn(duration: 0.16)
    }

    static func opacityAnimation(presented: Bool) -> Animation {
        presented ? .easeOut(duration: 0.15) : .easeIn(duration: 0.16)
    }
}

@MainActor
final class DelayedDismissal {
    typealias Schedule = (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    private let schedule: Schedule
    private var generation = 0
    private(set) var isPending = false

    init(schedule: @escaping Schedule = { delay, action in
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            action()
        }
    }) {
        self.schedule = schedule
    }

    func start(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
        generation += 1
        let token = generation
        isPending = true
        schedule(delay) { [weak self] in
            guard let self, generation == token else {
                return
            }
            isPending = false
            action()
        }
    }

    func cancel() {
        generation += 1
        isPending = false
    }
}
