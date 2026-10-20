import AppKit
import QuartzCore

@MainActor
final class PagerDriver: NSObject {
    private let model: LauncherModel
    private let makeDisplayLink: (Any, Selector) -> CADisplayLink?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    init(model: LauncherModel, makeDisplayLink: @escaping (Any, Selector) -> CADisplayLink?) {
        self.model = model
        self.makeDisplayLink = makeDisplayLink
    }

    func start() {
        guard link == nil, let link = makeDisplayLink(self, #selector(step(_:))) else {
            return
        }
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = lastTimestamp.map { now - $0 } ?? (link.targetTimestamp - link.timestamp)
        lastTimestamp = now
        model.advancePager(by: CGFloat(min(max(dt, 0), 1.0 / 30)))
        if !model.needsPagerFrames {
            link.invalidate()
            self.link = nil
        }
    }
}
