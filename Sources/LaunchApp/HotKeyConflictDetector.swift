import AppKit

struct HotKeyCombination: Equatable, Sendable {
    let keyCode: Int
    let modifiers: Int
}

@MainActor
struct HotKeyConflictDetector {
    static let launchOSBundleIdentifier = "app.remixdesign.LaunchOS"
    static let launchOSShortcutKey = "KeyboardShortcuts_launchApp"

    let isLaunchOSRunning: () -> Bool
    let launchOSShortcutValue: () -> String?

    static var live: HotKeyConflictDetector {
        HotKeyConflictDetector(
            isLaunchOSRunning: {
                !NSRunningApplication.runningApplications(
                    withBundleIdentifier: launchOSBundleIdentifier
                ).isEmpty
            },
            launchOSShortcutValue: {
                CFPreferencesCopyAppValue(
                    launchOSShortcutKey as CFString,
                    launchOSBundleIdentifier as CFString
                ) as? String
            }
        )
    }

    func conflictsWithLaunchOS(_ combination: HotKeyCombination?) -> Bool {
        guard let combination,
              isLaunchOSRunning(),
              let value = launchOSShortcutValue(),
              let launchOSCombination = Self.parse(value) else {
            return false
        }
        return launchOSCombination == combination
    }

    private static func parse(_ value: String) -> HotKeyCombination? {
        struct StoredShortcut: Decodable {
            let carbonKeyCode: Int
            let carbonModifiers: Int
        }
        guard let data = value.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredShortcut.self, from: data) else {
            return nil
        }
        return HotKeyCombination(keyCode: stored.carbonKeyCode, modifiers: stored.carbonModifiers)
    }
}
