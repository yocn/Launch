import AppKit

enum LauncherCommand: Equatable {
    case move(MoveDirection)
    case activate
    case nextPage
    case previousPage
    case dragPage(CGFloat)
    case endPageDrag(predictedTranslation: CGFloat, velocity: CGFloat)
    case undoLayoutEdit
}

enum KeyCommandMapper {
    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isComposingText: Bool,
        canUndoLayout: Bool = false
    ) -> LauncherCommand? {
        guard !isComposingText else {
            return nil
        }
        // 方向键事件自带数字键盘与功能键标志，只比较用户按下的修饰键
        let pressed = modifiers.intersection([.command, .option, .control, .shift])
        switch (keyCode, pressed) {
        case (123, []):
            return .move(.left)
        case (124, []):
            return .move(.right)
        case (125, []):
            return .move(.down)
        case (126, []):
            return .move(.up)
        case (36, []), (76, []):
            return .activate
        case (123, [.command]):
            return .previousPage
        case (124, [.command]):
            return .nextPage
        case (6, [.command]) where canUndoLayout:
            return .undoLayoutEdit
        default:
            return nil
        }
    }
}
