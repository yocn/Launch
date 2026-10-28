import Foundation

// 排查问题用的调试日志：debug 构建，或打包时设置 LAUNCH_DEBUG_LOG=1 才编译进去，正常发布包不含
enum DebugLog {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG || LAUNCH_DEBUG_LOG
        AppLog.shared.info("[调试] \(message())")
        #endif
    }
}

#if DEBUG || LAUNCH_DEBUG_LOG
import AppKit

// 唤起后记录前几十帧的间隔，看动画开始前有没有卡顿
@MainActor
final class FrameProbe: NSObject {
    private var link: CADisplayLink?
    private var start = ProcessInfo.processInfo.systemUptime
    private var last = ProcessInfo.processInfo.systemUptime
    private var intervals: [String] = []

    static func begin(on view: NSView?) {
        guard let view else { return }
        let probe = FrameProbe()
        probe.link = view.displayLink(target: probe, selector: #selector(tick))
        probe.link?.add(to: .main, forMode: .common)
        objc_setAssociatedObject(view, Unmanaged.passUnretained(probe).toOpaque(), probe, .OBJC_ASSOCIATION_RETAIN)
    }

    @objc private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        intervals.append(String(format: "%.0f", (now - last) * 1000))
        last = now
        if intervals.count >= 45 {
            link?.invalidate()
            DebugLog.log("帧间隔(ms，首个是显示到第一帧)：\(intervals.joined(separator: " "))；共 \(Int((now - start) * 1000))ms")
        }
    }
}
#endif
