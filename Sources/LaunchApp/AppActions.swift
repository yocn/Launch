import AppKit
import LaunchCore

@MainActor
struct AppActions {
    private static let notPermitted = -1743

    func revealInFinder(_ app: CatalogApp) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.identity.path)])
    }

    // 访达没有公开的显示简介接口，只能用 Apple 事件，首次会弹出自动化授权
    func showInfo(_ app: CatalogApp) {
        var error: NSDictionary?
        NSAppleScript(source: Self.infoScript(path: app.identity.path))?.executeAndReturnError(&error)
        guard let error else {
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法显示简介"
        if error[NSAppleScript.errorNumber] as? Int == Self.notPermitted {
            alert.informativeText = "Launch 没有控制访达的权限，请在“系统设置 → 隐私与安全性 → 自动化”中允许 Launch 控制“访达”。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runAboveLauncher() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.informativeText = error[NSAppleScript.errorMessage] as? String ?? "访达没有响应。"
            _ = alert.runAboveLauncher()
        }
    }

    nonisolated static func infoScript(path: String) -> String {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Finder"
            activate
            open information window of (POSIX file "\(escaped)" as alias)
        end tell
        """
    }
}
