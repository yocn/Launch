import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let onWillShow: () -> Void
    private let makeContent: () -> AnyView
    private var window: NSWindow?

    init(onWillShow: @escaping () -> Void, makeContent: @escaping () -> AnyView) {
        self.onWillShow = onWillShow
        self.makeContent = makeContent
    }

    func show() {
        onWillShow()
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            center(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Launch 设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: makeContent())
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
