import Foundation

struct DiagnosticsSources: Sendable {
    var logFiles: [URL]
    var crashReportsDirectory: URL
    var layoutFiles: [URL]
    var settings: Data?
    var systemInfo: String
}

enum DiagnosticsExportError: LocalizedError {
    case packingFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .packingFailed(let status):
            "打包失败（ditto 退出码 \(status)）"
        }
    }
}

// 收集到临时目录后用 ditto 打成 zip；缺少的来源跳过。包内用英文名：ditto 写的中文名在其他解压工具里会乱码
enum DiagnosticsExporter {
    static func export(_ sources: DiagnosticsSources, to zipURL: URL) throws {
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let root = staging.appending(path: "Launch Diagnostics", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: staging) }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        try copy(sources.logFiles, into: root.appending(path: "logs", directoryHint: .isDirectory))
        let crashes = ((try? manager.contentsOfDirectory(at: sources.crashReportsDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("LaunchApp") }
        try copy(crashes, into: root.appending(path: "crash-reports", directoryHint: .isDirectory))
        try copy(sources.layoutFiles, into: root.appending(path: "layout", directoryHint: .isDirectory))
        if let settings = sources.settings {
            try settings.write(to: root.appending(path: "settings.plist"))
        }
        try Data(sources.systemInfo.utf8).write(to: root.appending(path: "system-info.txt"))

        try? manager.removeItem(at: zipURL)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // 不带扩展属性，否则包里多出 __MACOSX/._ 文件
        ditto.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", root.path, zipURL.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw DiagnosticsExportError.packingFailed(ditto.terminationStatus)
        }
    }

    private static func copy(_ files: [URL], into folder: URL) throws {
        let existing = files.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else {
            return
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in existing {
            try FileManager.default.copyItem(at: file, to: folder.appending(path: file.lastPathComponent))
        }
    }
}
