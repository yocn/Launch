import AppKit
import LaunchCore

enum LayoutPromptText {
    static func summary(_ summary: LaunchpadImportSummary) -> String {
        var text = "旧 Launchpad 布局：\(summary.pageCount) 页、\(summary.folderCount) 个文件夹、\(summary.appCount) 个应用。已安装 \(summary.installedCount) 个"
        if summary.missingCount > 0 {
            text += "；未安装 \(summary.missingCount) 个，会保留位置，重新安装后回到原处"
        }
        text += "。"
        if summary.newAppCount > 0 {
            text += "另有 \(summary.newAppCount) 个新应用会排在最后。"
        }
        return text
    }
}

@MainActor
final class AlertLayoutPrompter: LayoutPrompting {
    func confirmFirstImport(_ summary: LaunchpadImportSummary) -> Bool {
        ask(
            title: "导入旧 Launchpad 布局？",
            message: LayoutPromptText.summary(summary),
            confirm: "导入",
            cancel: "暂不"
        )
    }

    func confirmReimport(_ summary: LaunchpadImportSummary) -> Bool {
        ask(
            title: "从 Launchpad 重新导入布局？",
            message: LayoutPromptText.summary(summary) + "\n\n会覆盖当前布局，覆盖前自动备份。",
            confirm: "导入",
            cancel: "取消"
        )
    }

    func confirmRestore() -> Bool {
        ask(
            title: "恢复导入前的布局？",
            message: "当前布局会与备份互换，再次恢复即可换回。",
            confirm: "恢复",
            cancel: "取消"
        )
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "布局"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func ask(title: String, message: String, confirm: String, cancel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

struct LiveLaunchpadSource: LaunchpadSource {
    let databaseURL: URL?

    var isAvailable: Bool {
        databaseURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func readSnapshot() async throws -> LaunchpadSnapshot {
        guard let databaseURL else {
            throw LaunchpadReadError.databaseNotFound
        }
        return try LaunchpadSnapshotReader().read(databaseURL: databaseURL)
    }
}
