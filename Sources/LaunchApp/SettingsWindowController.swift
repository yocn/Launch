import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: LauncherSettings
    // 启动器开着时返回它的窗口
    private let launcherWindow: () -> NSWindow?
    private let makeContent: () -> AnyView
    private var window: NSWindow?
    private let glass = NSGlassEffectView()
    private var appearanceObservation: NSKeyValueObservation?

    init(settings: LauncherSettings, launcherWindow: @escaping () -> NSWindow?, makeContent: @escaping () -> AnyView) {
        self.settings = settings
        self.launcherWindow = launcherWindow
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
        if let launcher = launcherWindow() {
            window.level = .aboveLauncher
            // 显示在程序坞时普通窗口进不去其他应用的全屏空间；挂成启动器的子窗口才能跟它在同一空间
            if window.parent !== launcher {
                launcher.addChildWindow(window, ordered: .above)
            }
        } else {
            window.level = .normal
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // 重新打开时焦点会落到快捷键录制框并直接进入录制，随手按的组合键会被录成新快捷键
        window.makeFirstResponder(nil)
    }

    func launcherDidHide() {
        detachFromLauncher()
        window?.level = .normal
    }

    // 不摘下的话，下次启动器出现会把已关的设置窗口一起带出来
    private func detachFromLauncher() {
        guard let window, let parent = window.parent else {
            return
        }
        parent.removeChildWindow(window)
    }

    func closeIfAboveLauncher() -> Bool {
        // 挂成子窗口后层级会被改成与启动器相同，只能按是否挂在启动器上判断
        guard let window, window.isVisible, window.parent != nil else {
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
        // 系统在浅色与深色之间切换时重新取色
        appearanceObservation = window.observe(\.effectiveAppearance) { [weak self, weak window] _, _ in
            Task { @MainActor in
                guard let self, let window else { return }
                self.updateTint(of: window)
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.detachFromLauncher()
            }
        }
        return window
    }

    // 设置窗口打开期间改样式或拖滑块立即生效
    private func applyStyle(to window: NSWindow) {
        withObservationTracking {
            let isGlass = settings.settingsWindowStyle == .glass
            glass.isHidden = !isGlass
            updateTint(of: window)
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

    // 动态颜色要按窗口当前外观取成固定值，否则深色模式下仍按浅色解析，玻璃会灰蒙蒙
    private func updateTint(of window: NSWindow) {
        var tint = NSColor.windowBackgroundColor
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            tint = NSColor(cgColor: NSColor.windowBackgroundColor.cgColor) ?? tint
        }
        glass.tintColor = tint.withAlphaComponent(settings.settingsGlassOpacity)
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
