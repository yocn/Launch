import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let isLauncherVisible: () -> Bool
    private let makeContent: () -> AnyView
    private var window: NSWindow?

    init(isLauncherVisible: @escaping () -> Bool, makeContent: @escaping () -> AnyView) {
        self.isLauncherVisible = isLauncherVisible
        self.makeContent = makeContent
    }

    var isOpen: Bool {
        window?.isVisible ?? false
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            center(window)
        }
        // 启动器开着时设置窗口要在它上面一层，关掉后恢复普通窗口，免得一直浮在其他应用上
        window.level = isLauncherVisible() ? .aboveLauncher : .normal
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func launcherDidHide() {
        window?.level = .normal
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Launch 设置"
        window.isReleasedWhenClosed = false
        // 窗口透明，内容嵌在液态玻璃里，标题栏透明让玻璃铺满整个窗口
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: makeContent())
        // 不是窗口的直接内容视图时，要显式打开桥接，标签页才会进标题栏
        hosting.sceneBridgingOptions = .all
        let glass = NSGlassEffectView()
        glass.contentView = hosting
        window.contentView = glass
        return window
    }

    private func center(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }
}
