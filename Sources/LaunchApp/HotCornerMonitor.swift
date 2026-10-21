import AppKit

// 其他应用在前台时用全局监听；启动器打开时鼠标事件归本应用，用本地监听
@MainActor
final class HotCornerMonitor {
    var corner = HotCorner.off {
        didSet {
            detector.corner = corner
            updateMonitors()
        }
    }

    private var detector = HotCornerDetector()
    private var monitors: [Any] = []
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    private func updateMonitors() {
        if corner == .off {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            return
        }
        guard monitors.isEmpty else {
            return
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.check()
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    private func check() {
        if detector.update(NSEvent.mouseLocation, screens: NSScreen.screens.map(\.frame)) {
            onTrigger()
        }
    }
}
