import AppKit
import LaunchCore

@MainActor
struct AppActions {
    func revealInFinder(_ app: CatalogApp) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.identity.path)])
    }

    // 访达没有公开的显示简介接口，只能用 Apple 事件，首次会弹出自动化授权
    // NSAppleScript 只能在主线程用且会一直等访达回复，交给 osascript 进程执行，主线程不等
    func showInfo(_ app: CatalogApp) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", Self.infoScript(path: app.identity.path)]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { process in
            guard process.terminationStatus != 0 else {
                return
            }
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            Task { @MainActor in
                Self.reportInfoFailure(message)
            }
        }
        do {
            try process.run()
        } catch {
            Self.reportInfoFailure(error.localizedDescription)
        }
    }

    nonisolated static func isNotPermitted(_ message: String) -> Bool {
        message.contains("(-1743)")
    }

    private static func reportInfoFailure(_ message: String) {
        AppLog.shared.warning("显示简介失败：\(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法显示简介"
        if isNotPermitted(message) {
            alert.informativeText = "Launch 没有控制访达的权限，请在“系统设置 → 隐私与安全性 → 自动化”中允许 Launch 控制“访达”。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runAboveLauncher() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                // 同步的 open 会等系统设置启动完成，把启动器卡住
                NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            }
        } else {
            alert.informativeText = message.isEmpty ? "访达没有响应。" : message
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
