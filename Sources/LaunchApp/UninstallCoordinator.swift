import AppKit
import LaunchCore

@MainActor
protocol UninstallPrompting: AnyObject {
    func confirmUninstall(appName: String, isRunning: Bool) -> Bool
    func showUninstallError(_ message: String)
}

@MainActor
final class UninstallCoordinator {
    private let uninstaller: AppUninstaller
    private let prompter: UninstallPrompting
    private let onRemoved: () -> Void

    init(uninstaller: AppUninstaller, prompter: UninstallPrompting, onRemoved: @escaping () -> Void) {
        self.uninstaller = uninstaller
        self.prompter = prompter
        self.onRemoved = onRemoved
    }

    func canUninstall(_ app: CatalogApp) -> Bool {
        uninstaller.canUninstall(app)
    }

    func uninstall(_ app: CatalogApp) async {
        guard uninstaller.canUninstall(app) else {
            return
        }
        let running = uninstaller.runningInstance(of: app)
        guard prompter.confirmUninstall(appName: app.displayName, isRunning: running != nil) else {
            return
        }
        if let running {
            let didQuit = await uninstaller.quit(running)
            guard didQuit else {
                prompter.showUninstallError("“\(app.displayName)”没有退出，未移到废纸篓。")
                return
            }
        }
        do {
            try uninstaller.moveToTrash(app)
            onRemoved()
        } catch {
            prompter.showUninstallError("无法将“\(app.displayName)”移到废纸篓：\(error.localizedDescription)")
        }
    }
}

@MainActor
final class AlertUninstallPrompter: UninstallPrompting {
    func confirmUninstall(appName: String, isRunning: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = isRunning ? "“\(appName)”正在运行" : "要将“\(appName)”移到废纸篓吗？"
        alert.informativeText = isRunning ? "退出后移到废纸篓，可以在废纸篓中恢复。" : "可以在废纸篓中恢复。"
        alert.addButton(withTitle: isRunning ? "退出并移到废纸篓" : "移到废纸篓")
        alert.addButton(withTitle: "取消")
        return alert.runAboveLauncher() == .alertFirstButtonReturn
    }

    func showUninstallError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "卸载失败"
        alert.informativeText = message
        _ = alert.runAboveLauncher()
    }
}

extension NSWindow.Level {
    // 启动器面板在 statusBar 层级
    static let aboveLauncher = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
}

extension NSAlert {
    // 启动器面板在 statusBar 层级；runModal 会把层级重设为模态面板层级，要在模态会话里再调高
    // 主线程 Task 内模态期间主队列不会重入，只能用运行循环的模态模式执行
    func runAboveLauncher() -> NSApplication.ModalResponse {
        RunLoop.main.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated {
                self.window.level = .aboveLauncher
            }
        }
        return runModal()
    }
}

extension NSSavePanel {
    // 同 NSAlert.runAboveLauncher：设置窗口可能浮在启动器上，从设置里弹的打开、存储面板也要跟上
    func runAboveLauncher() -> NSApplication.ModalResponse {
        RunLoop.main.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated {
                self.level = .aboveLauncher
            }
        }
        return runModal()
    }
}
