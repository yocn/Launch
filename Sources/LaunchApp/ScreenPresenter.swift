import AppKit
import CoreGraphics
import SwiftUI

public enum ScreenSelectionPolicy {
    public static func screenIndex(
        containing point: CGPoint,
        in screenFrames: [CGRect]
    ) -> Int? {
        screenFrames.firstIndex(where: { $0.contains(point) })
    }
}

public enum LauncherPanelConfiguration {
    public static let styleMask: NSWindow.StyleMask = [.borderless]
}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class ScreenPresenter: LauncherPresenting {
    var onResignActive: (() -> Void)?
    private let panel: LauncherPanel
    private var resignObserver: NSObjectProtocol?

    init() {
        panel = LauncherPanel(
            contentRect: .zero,
            styleMask: LauncherPanelConfiguration.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onResignActive?()
            }
        }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func isLauncherWindow(_ window: NSWindow?) -> Bool {
        window === panel
    }

    func makeDisplayLink(target: Any, selector: Selector) -> CADisplayLink? {
        panel.contentView?.displayLink(target: target, selector: selector)
    }

    var isComposingText: Bool {
        (panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    func setContent(_ content: some View) {
        panel.contentView = NSHostingView(rootView: content)
    }

    func present() {
        guard let screen = targetScreen() else {
            return
        }
        panel.setFrame(screen.frame, display: true)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss(restoringPreviousApp: Bool) {
        panel.orderOut(nil)
        if restoringPreviousApp {
            NSApp.hide(nil)
        }
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let index = ScreenSelectionPolicy.screenIndex(
            containing: NSEvent.mouseLocation,
            in: screens.map(\.frame)
        ) ?? 0
        return screens.indices.contains(index) ? screens[index] : nil
    }
}

