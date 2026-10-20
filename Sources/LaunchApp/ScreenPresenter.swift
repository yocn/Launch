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
    static let itemDragType = NSPasteboard.PasteboardType("dev.yocn.launch.item")
    var onResignActive: (() -> Void)?
    private let panel: LauncherPanel
    private var resignObserver: NSObjectProtocol?
    private let dismissal = DelayedDismissal()

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

    var onPresent: ((NSScreen) -> Void)?

    // 隐藏动画进行中视为已关闭，此时再次唤起会从当前状态反向
    var isVisible: Bool {
        panel.isVisible && !dismissal.isPending
    }

    func isLauncherWindow(_ window: NSWindow?) -> Bool {
        window === panel
    }

    func makeDisplayLink(target: Any, selector: Selector) -> CADisplayLink? {
        panel.contentView?.displayLink(target: target, selector: selector)
    }

    var contentView: NSView? {
        panel.contentView
    }

    var backingScaleFactor: CGFloat {
        panel.backingScaleFactor
    }

    func globalPoint(fromScreen point: CGPoint) -> CGPoint? {
        guard let contentView else {
            return nil
        }
        return LauncherCoordinates.global(
            fromWindow: panel.convertPoint(fromScreen: point),
            contentHeight: contentView.bounds.height
        )
    }

    var isComposingText: Bool {
        (panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    func setContent(_ content: some View, skipsCursorUpdate: @escaping () -> Bool = { false }) {
        let view = LauncherHostingView(rootView: content)
        view.skipsCursorUpdate = skipsCursorUpdate
        view.registerForDraggedTypes([Self.itemDragType])
        panel.contentView = view
    }

    func present() {
        dismissal.cancel()
        panel.ignoresMouseEvents = false
        guard let screen = targetScreen() else {
            return
        }
        onPresent?(screen)
        panel.setFrame(screen.frame, display: true)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    // 等隐藏动画播完再收起；立即切回之前的应用会把动画打断
    func dismiss(restoringPreviousApp: Bool) {
        panel.ignoresMouseEvents = true
        dismissal.start(after: PresentationTransition.hideDuration) { [weak self] in
            guard let self else {
                return
            }
            panel.orderOut(nil)
            panel.ignoresMouseEvents = false
            if restoringPreviousApp {
                NSApp.hide(nil)
            }
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

// 开了辅助功能自定义指针时，每次设置光标都要同步注册到 WindowServer；内容逐帧移动时 AppKit 每帧都会触发
private final class LauncherHostingView<Content: View>: NSHostingView<Content> {
    var skipsCursorUpdate: () -> Bool = { false }

    override func cursorUpdate(with event: NSEvent) {
        guard !skipsCursorUpdate() else {
            return
        }
        super.cursorUpdate(with: event)
    }

    // 只接受启动器内部的图标拖拽，拖到面板外或按 Esc 时系统会把图标飞回原位
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.carriesItem(sender) ? .move : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.carriesItem(sender) ? .move : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.carriesItem(sender) ? true : super.performDragOperation(sender)
    }

    private static func carriesItem(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.availableType(from: [ScreenPresenter.itemDragType]) != nil
    }
}
