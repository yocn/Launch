import AppKit
import LaunchCore

@MainActor
protocol UninstallPrompting: AnyObject {
    func confirmUninstall(appName: String, isRunning: Bool) -> Bool
    func reviewCleanup(_ plan: ResidualPlan, isRunning: Bool) -> Set<String>?
    func showCleanupResult(_ result: UninstallCleanupResult)
    func showUninstallError(_ message: String)
}

extension UninstallPrompting {
    func reviewCleanup(_ plan: ResidualPlan, isRunning: Bool) -> Set<String>? {
        confirmUninstall(appName: plan.app.displayName, isRunning: isRunning) ? [] : nil
    }
    func showCleanupResult(_ result: UninstallCleanupResult) {}
}

@MainActor
final class UninstallCoordinator {
    private let uninstaller: AppUninstaller
    private let prompter: UninstallPrompting
    private let onRemoved: () -> Void
    private let makeCleanup: (() -> UninstallCleanup)?
    // 后台检查或移动较慢时显示的提示，nil 表示收起
    private let onProgress: (String?) -> Void
    private var isBusy = false
    private var isShowingProgress = false

    init(uninstaller: AppUninstaller, prompter: UninstallPrompting,
         makeCleanup: (() -> UninstallCleanup)? = nil, onProgress: @escaping (String?) -> Void = { _ in },
         onRemoved: @escaping () -> Void) {
        self.uninstaller = uninstaller
        self.prompter = prompter
        self.onRemoved = onRemoved
        self.makeCleanup = makeCleanup
        self.onProgress = onProgress
    }

    func canUninstall(_ app: CatalogApp) -> Bool {
        uninstaller.canUninstall(app)
    }

    func uninstall(_ app: CatalogApp) async {
        guard !isBusy, uninstaller.canUninstall(app) else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        if let cleanup = makeCleanup?() {
            await uninstallWithCleanup(app, cleanup: cleanup)
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

    private func uninstallWithCleanup(_ app: CatalogApp, cleanup: UninstallCleanup) async {
        do {
            let plan = try await withProgress("正在检查关联文件…") { try cleanup.scanner.scan(app) }
            guard let selection = prompter.reviewCleanup(plan, isRunning: uninstaller.runningInstance(of: app) != nil) else { return }
            // 确认窗口打开期间应用可能启动，因此此处重新查询。
            for running in uninstaller.runningInstances(of: app) {
                guard await uninstaller.quit(running) else {
                    prompter.showUninstallError("“\(app.displayName)”没有退出，未移动任何文件。")
                    return
                }
            }
            guard uninstaller.canUninstall(app), uninstaller.runningInstances(of: app).isEmpty else {
                prompter.showUninstallError("应用的运行状态或权限已变化，未移动任何文件。")
                return
            }
            let result = try await withProgress("正在移到废纸篓…") { try cleanup.execute(plan, selection: selection) }
            if result.appRemoved { onRemoved() }
            prompter.showCleanupResult(result)
        } catch {
            prompter.showUninstallError("未能完成卸载检查：\(error.localizedDescription)")
        }
    }

    // 超过半秒才提示，免得快的时候一闪而过
    private func withProgress<T: Sendable>(_ text: String, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        let notice = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else {
                return
            }
            isShowingProgress = true
            onProgress(text)
        }
        defer {
            notice.cancel()
            if isShowingProgress {
                isShowingProgress = false
                onProgress(nil)
            }
        }
        return try await Task.detached(priority: .userInitiated, operation: work).value
    }
}

@MainActor
final class AlertUninstallPrompter: UninstallPrompting {
    func reviewCleanup(_ plan: ResidualPlan, isRunning: Bool) -> Set<String>? {
        UninstallReview(plan: plan, isRunning: isRunning).run()
    }

    func showCleanupResult(_ result: UninstallCleanupResult) {
        let alert = NSAlert()
        alert.messageText = result.appRemoved ? (result.problems.isEmpty ? "已移到废纸篓" : "应用已移到废纸篓，部分项目已保留") : "应用未移到废纸篓"
        let count = result.record.entries.filter { $0.state == .trashed }.count
        alert.informativeText = "已移动 \(count) 项。可按操作记录中的原路径与废纸篓位置找回文件。\n"
            + result.problems.prefix(6).joined(separator: "\n")
            + "\n操作记录：\(result.recordURL.path)"
        alert.addButton(withTitle: "完成")
        alert.addButton(withTitle: "在访达中显示记录")
        if alert.runAboveLauncher() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([result.recordURL])
        }
    }

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

extension NSWindow {
    // 启动器可能开在其他应用的全屏空间上，独立弹出的窗口进不去、打开了也看不见；挂成启动器的子窗口才跟它在同一空间
    func attachToLauncher() {
        guard let launcher = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }), parent !== launcher else {
            return
        }
        launcher.addChildWindow(self, ordered: .above)
        // runModal 总把窗口居中到主屏
        if let screen = launcher.screen, screen != self.screen {
            let area = screen.visibleFrame
            setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
        }
    }

    // 不摘下的话，下次启动器出现会把已关的窗口一起带出来
    func detachFromLauncher() {
        parent?.removeChildWindow(self)
    }
}

extension NSAlert {
    // 启动器面板在 statusBar 层级；runModal 会把层级重设为模态面板层级，要在模态会话里再调高
    // 主线程 Task 内模态期间主队列不会重入，只能用运行循环的模态模式执行
    func runAboveLauncher() -> NSApplication.ModalResponse {
        RunLoop.main.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated {
                self.window.level = .aboveLauncher
                self.window.attachToLauncher()
            }
        }
        defer { window.detachFromLauncher() }
        return runModal()
    }
}

extension NSSavePanel {
    // 同 NSAlert.runAboveLauncher：设置窗口可能浮在启动器上，从设置里弹的打开、存储面板也要跟上
    func runAboveLauncher() -> NSApplication.ModalResponse {
        RunLoop.main.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated {
                self.level = .aboveLauncher
                self.attachToLauncher()
            }
        }
        defer { detachFromLauncher() }
        return runModal()
    }
}
