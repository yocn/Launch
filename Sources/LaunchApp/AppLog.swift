import Foundation
import os

// 写 ~/Library/Logs/Launch/launch.log 与系统日志；超过上限时轮换，只留一份旧文件
final class AppLog: Sendable {
    enum Level: String, Sendable {
        case info = "信息"
        case warning = "警告"
        case error = "错误"
    }

    static let shared = AppLog(
        directory: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Launch", directoryHint: .isDirectory)
    )

    let fileURL: URL
    let rotatedURL: URL
    private let maxBytes: Int
    private let now: @Sendable () -> Date
    private let queue = DispatchQueue(label: "dev.yocn.launch.log")
    private let logger = Logger(subsystem: "dev.yocn.launch", category: "app")

    init(directory: URL, maxBytes: Int = 1_000_000, now: @escaping @Sendable () -> Date = Date.init) {
        fileURL = directory.appending(path: "launch.log")
        rotatedURL = directory.appending(path: "launch.1.log")
        self.maxBytes = maxBytes
        self.now = now
    }

    func info(_ message: String) {
        write(.info, message)
    }

    func warning(_ message: String) {
        write(.warning, message)
    }

    func error(_ message: String) {
        write(.error, message)
    }

    // 等排队的写入完成，导出前与测试中使用
    func flush() {
        queue.sync {}
    }

    private func write(_ level: Level, _ message: String) {
        switch level {
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
        let line = Data("\(Self.timestamp(now())) [\(level.rawValue)] \(message)\n".utf8)
        queue.async { [self] in
            append(line)
        }
    }

    private func append(_ line: Data) {
        let manager = FileManager.default
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = (try? manager.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        if size > 0, size + line.count > maxBytes {
            try? manager.removeItem(at: rotatedURL)
            try? manager.moveItem(at: fileURL, to: rotatedURL)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            try? line.write(to: fileURL)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    private static func timestamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d.%03d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0, (parts.nanosecond ?? 0) / 1_000_000
        )
    }
}
