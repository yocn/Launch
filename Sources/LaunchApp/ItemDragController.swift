import AppKit
import LaunchCore

// 图标上的鼠标事件全部由这里接管：点击自行执行，移动超过阈值即发起系统拖拽会话
@MainActor
final class ItemDragController: NSObject, NSDraggingSource {
    private static let dragThreshold: CGFloat = 4

    private let model: LauncherModel
    private let presenter: ScreenPresenter
    private let onActivate: (ResolvedItem) -> Void
    private let makeDragImage: (ResolvedItem) -> NSImage?
    private var monitors: [Any] = []
    private var press: LauncherModel.ItemPress?
    private var pressPoint: CGPoint = .zero
    private var lastPoint: CGPoint = .zero
    private var timer: Timer?

    init(
        model: LauncherModel,
        presenter: ScreenPresenter,
        onActivate: @escaping (ResolvedItem) -> Void,
        makeDragImage: @escaping (ResolvedItem) -> NSImage?
    ) {
        self.model = model
        self.presenter = presenter
        self.onActivate = onActivate
        self.makeDragImage = makeDragImage
    }

    func start() {
        let down = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.mouseDown(event) ?? event
        }
        let drag = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.mouseDragged(event) ?? event
        }
        let up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.mouseUp(event) ?? event
        }
        monitors = [down, drag, up].compactMap { $0 }
    }

    private func globalPoint(of event: NSEvent) -> CGPoint? {
        guard presenter.isLauncherWindow(event.window), let view = presenter.contentView else {
            return nil
        }
        return LauncherCoordinates.global(fromWindow: event.locationInWindow, contentHeight: view.bounds.height)
    }

    private func mouseDown(_ event: NSEvent) -> NSEvent? {
        press = nil
        guard let point = globalPoint(of: event), let hit = model.itemPress(at: point) else {
            return event
        }
        press = hit
        pressPoint = point
        return nil
    }

    private func mouseDragged(_ event: NSEvent) -> NSEvent? {
        guard let press else {
            return event
        }
        guard let point = globalPoint(of: event),
              hypot(point.x - pressPoint.x, point.y - pressPoint.y) > Self.dragThreshold else {
            return nil
        }
        // 拖拽被 Esc 取消后仍会收到松开事件，提前清掉点击候选
        self.press = nil
        if model.canDragItems {
            beginSession(press, event: event)
        }
        return nil
    }

    private func mouseUp(_ event: NSEvent) -> NSEvent? {
        guard let press else {
            return event
        }
        self.press = nil
        onActivate(press.item)
        return nil
    }

    private func beginSession(_ press: LauncherModel.ItemPress, event: NSEvent) {
        guard let view = presenter.contentView, let frame = model.frame(of: press.origin) else {
            return
        }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("item", forType: ScreenPresenter.itemDragType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let windowFrame = LauncherCoordinates.window(fromGlobal: frame, contentHeight: view.bounds.height)
        draggingItem.setDraggingFrame(view.convert(windowFrame, from: nil), contents: makeDragImage(press.item))
        let session = view.beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
        lastPoint = pressPoint
        model.beginItemDrag(press, at: pressPoint)
        // 指针停住时没有移动回调，停留计时靠定时器推进；拖拽期间处于事件跟踪模式
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        model.updateItemDrag(at: lastPoint, now: ProcessInfo.processInfo.systemUptime)
    }

    private func moved(to screenPoint: CGPoint) {
        guard let point = presenter.globalPoint(fromScreen: screenPoint) else {
            return
        }
        lastPoint = point
        model.updateItemDrag(at: point, now: ProcessInfo.processInfo.systemUptime)
    }

    private func ended(at screenPoint: CGPoint, operation: NSDragOperation) {
        timer?.invalidate()
        timer = nil
        guard operation.contains(.move), let point = presenter.globalPoint(fromScreen: screenPoint) else {
            model.cancelItemDrag()
            return
        }
        model.endItemDrag(at: point, now: ProcessInfo.processInfo.systemUptime)
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        MainActor.assumeIsolated {
            moved(to: screenPoint)
        }
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        MainActor.assumeIsolated {
            ended(at: screenPoint, operation: operation)
        }
    }
}
