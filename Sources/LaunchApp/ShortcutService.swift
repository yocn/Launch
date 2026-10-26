import Foundation
import Darwin

struct ShortcutRecord: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
}

enum ShortcutError: LocalizedError {
    case invalidList, failed(String), timedOut, tooMuchOutput
    var errorDescription: String? {
        switch self {
        case .invalidList: "快捷指令清单格式无法识别"
        case .failed(let message): "快捷指令执行失败：\(message)"
        case .timedOut: "快捷指令等待超时，请检查执行状态，不会自动重试。"
        case .tooMuchOutput: "快捷指令输出过多，已停止等待。"
        }
    }
}

struct ShortcutService: Sendable {
    typealias Execute = @Sendable ([String], TimeInterval) async throws -> String
    private let execute: Execute
    init(execute: @escaping Execute = ShortcutProcess.execute) { self.execute = execute }

    func list() async throws -> [ShortcutRecord] {
        try Self.parseList(await execute(["list", "--show-identifiers"], 10))
    }

    func run(id: UUID) async throws { _ = try await execute(["run", id.uuidString], 300) }

    static func parseList(_ output: String) throws -> [ShortcutRecord] {
        let pattern = #"^(.+)\s+\(([0-9A-Fa-f-]{36})\)\s*$"#
        let regex = try NSRegularExpression(pattern: pattern)
        var result: [ShortcutRecord] = []
        var seen = Set<UUID>()
        let rows = output.split(whereSeparator: \.isNewline)
        // 输出里混着错误输出，单行对不上就跳过；一行都解析不出才算清单无法识别
        for row in rows {
            let line = String(row)
            let text = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: text.length)),
                  let id = UUID(uuidString: text.substring(with: match.range(at: 2))) else { continue }
            let name = text.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if seen.insert(id).inserted { result.append(ShortcutRecord(id: id, name: name)) }
        }
        if result.isEmpty, !rows.isEmpty { throw ShortcutError.invalidList }
        return result
    }
}

// 直接启动进程不经 shell，有超时和输出上限，失败不自动重试
enum ShortcutProcess {
    static func execute(_ arguments: [String], timeout: TimeInterval) async throws -> String {
        try await run(executable: URL(fileURLWithPath: "/usr/bin/shortcuts"), arguments: arguments, timeout: timeout)
    }

    static func run(executable: URL, arguments: [String], timeout: TimeInterval, outputLimit: Int = 1_048_576) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let process = Process()
                    let pipe = Pipe()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.standardOutput = pipe
                    process.standardError = pipe
                    process.standardInput = FileHandle.nullDevice
                    try process.run()
                    try? pipe.fileHandleForWriting.close()
                    let fd = pipe.fileHandleForReading.fileDescriptor
                    let flags = fcntl(fd, F_GETFL)
                    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                    var output = Data()
                    var buffer = [UInt8](repeating: 0, count: 8192)
                    let deadline = Date().addingTimeInterval(timeout)
                    var failure: ShortcutError?
                    while true {
                        let count = read(fd, &buffer, buffer.count)
                        if count > 0 {
                            if output.count + count > outputLimit { failure = .tooMuchOutput; break }
                            output.append(contentsOf: buffer.prefix(count))
                            continue
                        }
                        if !process.isRunning { break }
                        if Date() >= deadline { failure = .timedOut; break }
                        usleep(10_000)
                    }
                    if failure != nil, process.isRunning {
                        process.terminate()
                        usleep(100_000)
                        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
                    }
                    process.waitUntilExit()
                    try? pipe.fileHandleForReading.close()
                    if let failure { throw failure }
                    let text = String(decoding: output, as: UTF8.self)
                    guard process.terminationStatus == 0 else { throw ShortcutError.failed(String(text.prefix(1000))) }
                    continuation.resume(returning: text)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
