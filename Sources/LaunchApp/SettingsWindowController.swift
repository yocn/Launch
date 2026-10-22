import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: LauncherSettings
    private let isLauncherVisible: () -> Bool
    private let makeContent: () -> AnyView
    private var window: NSWindow?
    private let glass = NSGlassEffectView()

    init(settings: LauncherSettings, isLauncherVisible: @escaping () -> Bool, makeContent: @escaping () -> AnyView) {
        self.settings = settings
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

    func closeIfAboveLauncher() -> Bool {
        guard let window, window.isVisible, window.level == .aboveLauncher else {
            return false
        }
        window.close()
        return true
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
        // 标题栏透明，玻璃或窗口底色铺满整个窗口；切换样式时不改，免得窗口跳动
        window.titlebarAppearsTransparent = true
        let hosting = NSHostingView(rootView: makeContent())
        // 不是窗口的直接内容视图时，要显式打开桥接，标签页才会进标题栏
        hosting.sceneBridgingOptions = .all
        // 玻璃垫在内容下面，切换样式只显隐玻璃，不搬动内容视图（搬动后内容不再绘制）
        let container = NSView()
        for view in [glass, hosting] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
        window.contentView = container
        applyStyle(to: window)
        return window
    }

    // 设置窗口打开期间改样式或拖滑块立即生效
    private func applyStyle(to window: NSWindow) {
        withObservationTracking {
            let isGlass = settings.settingsWindowStyle == .glass
            glass.isHidden = !isGlass
            glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(settings.settingsGlassOpacity)
            window.isOpaque = !isGlass
            window.backgroundColor = isGlass ? .clear : .windowBackgroundColor
        } onChange: { [weak self, weak window] in
            Task { @MainActor in
                guard let self, let window else {
                    return
                }
                self.applyStyle(to: window)
            }
        }
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
