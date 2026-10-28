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

    // 找不到所选屏幕时退回鼠标所在屏幕，再退回第一块
    static func screenIndex(
        for choice: LauncherScreenChoice,
        screens: [CGRect],
        mouse: CGPoint,
        active: CGRect?,
        dock: CGRect?
    ) -> Int {
        let pointer = screenIndex(containing: mouse, in: screens) ?? 0
        switch choice {
        case .mouse:
            return pointer
        case .active:
            return active.flatMap { screens.firstIndex(of: $0) } ?? pointer
        case .dock:
            return dock.flatMap { screenIndex(containing: CGPoint(x: $0.midX, y: $0.midY), in: screens) } ?? pointer
        case .main:
            return 0
        }
    }

    // 程序坞让所在屏幕的可用区域在底部、左侧或右侧内缩；自动隐藏时没有内缩
    static func dockScreenIndex(frames: [CGRect], visibleFrames: [CGRect]) -> Int? {
        zip(frames, visibleFrames).enumerated().first { _, pair in
            let (frame, visible) = pair
            return visible.minY > frame.minY || visible.minX > frame.minX || visible.maxX < frame.maxX
        }?.offset
    }

    // 窗口服务器的坐标以主屏左上角为原点、向下为正
    static func screenRect(fromWindowServer rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

// 显示程序坞时，屏幕切成启动器区域和程序坞那一条（AppKit 坐标）；菜单栏不算
enum DockStrip {
    static func split(screen: CGRect, visible: CGRect) -> (panel: CGRect, strip: CGRect?) {
        let bottom = visible.minY - screen.minY
        let left = visible.minX - screen.minX
        let right = screen.maxX - visible.maxX
        if bottom > 0 {
            return (
                CGRect(x: screen.minX, y: screen.minY + bottom, width: screen.width, height: screen.height - bottom),
                CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: bottom)
            )
        }
        if left > 0 {
            return (
                CGRect(x: screen.minX + left, y: screen.minY, width: screen.width - left, height: screen.height),
                CGRect(x: screen.minX, y: screen.minY, width: left, height: screen.height)
            )
        }
        if right > 0 {
            return (
                CGRect(x: screen.minX, y: screen.minY, width: screen.width - right, height: screen.height),
                CGRect(x: screen.maxX - right, y: screen.minY, width: right, height: screen.height)
            )
        }
        return (screen, nil)
    }

    // 两块窗口各自模糊，接缝处会出硬边；这一条往启动器底下多垫一段，启动器背景在这段里渐隐
    static let blendLength: CGFloat = 64

    static func underlay(_ strip: CGRect, panel: CGRect, by length: CGFloat) -> CGRect {
        switch fadeEdge(strip: strip, panel: panel) {
        case .leading: CGRect(x: strip.minX, y: strip.minY, width: strip.width + length, height: strip.height)
        case .trailing: CGRect(x: strip.minX - length, y: strip.minY, width: strip.width + length, height: strip.height)
        default: CGRect(x: strip.minX, y: strip.minY, width: strip.width, height: strip.height + length)
        }
    }

    // 启动器靠程序坞的那条边
    static func fadeEdge(strip: CGRect, panel: CGRect) -> Edge {
        if strip.maxX <= panel.minX {
            return .leading
        }
        if strip.minX >= panel.maxX {
            return .trailing
        }
        return .bottom
    }

    // 整块屏幕在窗口里的位置（SwiftUI 左上原点），两块窗口的壁纸据此对齐
    static func canvas(_ screen: CGRect, in window: CGRect) -> CGRect {
        CGRect(x: screen.minX - window.minX, y: window.maxY - screen.maxY, width: screen.width, height: screen.height)
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
    // 显示程序坞时垫在程序坞下面的那一条背景
    private let stripPanel: NSPanel
    private let mainCanvas = BackgroundCanvas()
    private let stripCanvas = BackgroundCanvas()
    private var screen: NSScreen?
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
        // 启动器打开时触发角靠本地鼠标移动事件
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        stripPanel = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        stripPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        stripPanel.collectionBehavior = panel.collectionBehavior
        stripPanel.backgroundColor = .clear
        stripPanel.isOpaque = false
        stripPanel.hasShadow = false
        stripPanel.hidesOnDeactivate = false
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
    var screenChoice = LauncherScreenChoice.mouse
    var showsDock = false {
        didSet { relayoutIfVisible(changed: showsDock != oldValue) }
    }
    // 窗口模式窗口外本来就透明，不垫程序坞那一条
    var isWindowMode = false {
        didSet { relayoutIfVisible(changed: isWindowMode != oldValue) }
    }

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
        let view = LauncherHostingView(rootView: content.environment(mainCanvas))
        view.skipsCursorUpdate = skipsCursorUpdate
        view.registerForDraggedTypes([Self.itemDragType])
        // 启动器按深色设计，系统控件（如搜索框占位文字）在浅色外观下会取成灰色，固定用深色外观
        view.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = view
    }

    func setStripContent(_ content: some View) {
        stripPanel.contentView = LauncherHostingView(rootView: content.environment(stripCanvas))
    }

    func present() {
        dismissal.cancel()
        panel.ignoresMouseEvents = false
        guard let screen = targetScreen() else {
            return
        }
        onPresent?(screen)
        self.screen = screen
        layout(on: screen)
        // 第一次显示时窗口还没按新尺寸布局，会先出现一块局部矩形再铺满；显示前先布局并绘制好
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func layout(on screen: NSScreen) {
        let split = showsDock ? DockStrip.split(screen: screen.frame, visible: screen.visibleFrame) : (panel: screen.frame, strip: nil)
        panel.setFrame(split.panel, display: true)
        mainCanvas.screenFrame = DockStrip.canvas(screen.frame, in: split.panel)
        guard let strip = split.strip, !isWindowMode else {
            mainCanvas.fadeEdge = nil
            stripPanel.orderOut(nil)
            return
        }
        mainCanvas.fadeEdge = DockStrip.fadeEdge(strip: strip, panel: split.panel)
        let underlay = DockStrip.underlay(strip, panel: split.panel, by: DockStrip.blendLength)
        stripPanel.setFrame(underlay, display: true)
        stripCanvas.screenFrame = DockStrip.canvas(screen.frame, in: underlay)
        stripPanel.orderFront(nil)
    }

    private func relayoutIfVisible(changed: Bool) {
        guard changed, isVisible, let screen else {
            return
        }
        layout(on: screen)
    }

    // 等隐藏动画播完再收起；立即切回之前的应用会把动画打断
    func dismiss(restoringPreviousApp: Bool) {
        panel.ignoresMouseEvents = true
        dismissal.start(after: PresentationTransition.hideDuration) { [weak self] in
            guard let self else {
                return
            }
            panel.orderOut(nil)
            stripPanel.orderOut(nil)
            panel.ignoresMouseEvents = false
            if restoringPreviousApp {
                NSApp.hide(nil)
            }
        }
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }
        let index = ScreenSelectionPolicy.screenIndex(
            for: screenChoice,
            screens: screens.map(\.frame),
            mouse: NSEvent.mouseLocation,
            active: screenChoice == .active ? NSScreen.main?.frame : nil,
            dock: screenChoice == .dock ? dockFrame(primaryHeight: screens[0].frame.height) : nil
        )
        return screens[index]
    }

    // 程序坞窗口不一定标为在屏幕上，所以自动隐藏时查全部窗口
    private func dockFrame(primaryHeight: CGFloat) -> CGRect? {
        let screens = NSScreen.screens
        if let index = ScreenSelectionPolicy.dockScreenIndex(frames: screens.map(\.frame), visibleFrames: screens.map(\.visibleFrame)) {
            return screens[index].frame
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let level = Int(CGWindowLevelForKey(.dockWindow))
        let bounds = windows.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == dock.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == level
        }?[kCGWindowBounds as String] as CFTypeRef?
        guard let bounds, let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else {
            return nil
        }
        return ScreenSelectionPolicy.screenRect(fromWindowServer: rect, primaryHeight: primaryHeight)
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

    // 设置窗口浮在上面时面板不是主窗口，不接第一下点击的话点空白处要点两次才关
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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
