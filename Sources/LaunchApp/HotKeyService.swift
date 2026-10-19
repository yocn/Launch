import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleLauncher = Self("toggleLauncher", initial: .init(.space, modifiers: [.option]))
}

@MainActor
enum HotKeyService {
    static func register(onToggle: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .toggleLauncher, action: onToggle)
    }

    static var currentCombination: HotKeyCombination? {
        KeyboardShortcuts.getShortcut(for: .toggleLauncher).map {
            HotKeyCombination(keyCode: $0.carbonKeyCode, modifiers: $0.carbonModifiers)
        }
    }
}
