import AppKit

@MainActor
final class LauncherInputMonitor {
    private var monitors: [Any] = []
    private var interpreter = PageScrollInterpreter()

    func start(
        isLauncherWindow: @escaping (NSWindow?) -> Bool,
        isComposingText: @escaping () -> Bool,
        onCommand: @escaping (LauncherCommand) -> Void
    ) {
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isLauncherWindow(event.window),
                  let command = KeyCommandMapper.command(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags,
                    isComposingText: isComposingText()
                  ) else {
                return event
            }
            onCommand(command)
            return nil
        }
        let scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, isLauncherWindow(event.window) else {
                return event
            }
            switch interpreter.interpret(ScrollSample(event: event)) {
            case .turn(let direction)?:
                onCommand(direction == .next ? .nextPage : .previousPage)
            case .drag(let translation)?:
                onCommand(.dragPage(translation))
            case .endDrag(let predictedTranslation, let velocity)?:
                onCommand(.endPageDrag(predictedTranslation: predictedTranslation, velocity: velocity))
            case nil:
                break
            }
            return nil
        }
        monitors = [keyMonitor, scrollMonitor].compactMap { $0 }
    }
}

extension ScrollSample {
    init(event: NSEvent) {
        let phase: Phase
        switch event.phase {
        case .began, .mayBegin:
            phase = .began
        case .ended, .cancelled:
            phase = .ended
        case []:
            phase = .none
        default:
            phase = .changed
        }
        self.init(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas,
            phase: phase,
            isMomentum: event.momentumPhase != [],
            // 平滑滚动等工具合成的滚轮事件 timestamp 为 0，用接收时刻计算冷却
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }
}
