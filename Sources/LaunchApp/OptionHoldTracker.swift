import AppKit

// 单独按住 Option 的开始与结束；唤起时仍按着的 Option（如 ⌥Space）要先松开
struct OptionHoldTracker {
    enum Change: Equatable {
        case began
        case ended
    }

    private var waitsForRelease = false
    private var isHolding = false

    mutating func reset(optionDown: Bool) {
        waitsForRelease = optionDown
        isHolding = false
    }

    mutating func update(_ flags: NSEvent.ModifierFlags) -> Change? {
        let pressed = flags.intersection([.command, .option, .control, .shift])
        if waitsForRelease {
            waitsForRelease = pressed.contains(.option)
            return nil
        }
        let optionAlone = pressed == [.option]
        if !isHolding, optionAlone {
            isHolding = true
            return .began
        }
        if isHolding, !optionAlone {
            isHolding = false
            return .ended
        }
        return nil
    }
}
