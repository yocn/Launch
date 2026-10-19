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
            if let direction = interpreter.interpret(ScrollSample(event: event)) {
                onCommand(direction == .next ? .nextPage : .previousPage)
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
            timestamp: event.timestamp
        )
    }
}
