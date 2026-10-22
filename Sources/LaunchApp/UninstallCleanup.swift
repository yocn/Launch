import Foundation
import LaunchCore

struct UninstallRecord: Codable, Sendable {
    struct Entry: Codable, Sendable {
        enum State: String, Codable, Sendable { case pending, moving, trashed, skipped, failed }
        let originalPath: String
        var state: State = .pending
        var trashPath: String?
        var message: String?
    }

    let createdAt: Date
    let application: String
    let bundleIdentifier: String?
    var entries: [Entry]
    let recovery = "请按 originalPath 和 trashPath 在访达中找到文件，从废纸篓放回原位置。不要清空废纸篓。运行状态和个人设置可能无法完整恢复。moving 表示操作中断，需同时检查原位置和废纸篓。"

    private enum CodingKeys: CodingKey { case createdAt, application, bundleIdentifier, entries, recovery }
}

struct UninstallCleanupResult: Sendable {
    let recordURL: URL
    let record: UninstallRecord
    let recordError: String?
    var appRemoved: Bool { record.entries.first?.state == .trashed }
    var problems: [String] {
        record.entries.filter { $0.state == .failed || $0.state == .skipped || $0.state == .moving }
            .map { "\($0.originalPath)：\($0.message ?? "操作未完成，请检查原位置与废纸篓")" }
            + (recordError.map { ["操作记录保存失败，已停止后续移动：\($0)"] } ?? [])
    }
}

struct UninstallCleanup: Sendable {
    let scanner: ResidualScanner
    let recordDirectory: URL
    var trash: @Sendable (URL) throws -> URL? = { url in
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }
    var writeRecord: @Sendable (Data, URL) throws -> Void = { data, url in
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static var defaultRecordDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Launch/UninstallRecords")
    }

    func execute(_ plan: ResidualPlan, selection: Set<String>) throws -> UninstallCleanupResult {
        let permitted = Set(plan.items.filter(\.isSelectable).map(\.id))
        guard selection.isSubset(of: permitted) else { throw ResidualSafetyError.unsafe("所选项目不在已确认的可清理清单内") }
        try scanner.revalidateApp(plan, needsResiduals: !selection.isEmpty)
        let selected = plan.items.filter { selection.contains($0.id) }
        let recordURL = recordDirectory.appending(path: "\(UUID().uuidString).json")
        var record = UninstallRecord(createdAt: Date(), application: plan.app.displayName,
                                     bundleIdentifier: plan.app.identity.bundleIdentifier,
                                     entries: [.init(originalPath: plan.app.identity.path)] + selected.map { .init(originalPath: $0.url.path) })
        func persist() throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try writeRecord(encoder.encode(record), recordURL)
        }
        // 记录写入失败时，任何文件都不移动。
        try persist()
        for index in record.entries.indices {
            let url = URL(fileURLWithPath: record.entries[index].originalPath)
            do {
                // 应用本体已在写记录前复核过，其间只写了记录
                if index > 0 {
                    guard scanner.residualsStillExclusive(plan) else { throw ResidualSafetyError.unsafe("应用来源变化，无法排除共享使用") }
                    try scanner.revalidate(selected[index - 1])
                }
            } catch {
                record.entries[index].state = index == 0 ? .failed : .skipped
                record.entries[index].message = error.localizedDescription
                do { try persist() } catch { return .init(recordURL: recordURL, record: record, recordError: error.localizedDescription) }
                if index == 0 { break }
                continue
            }
            record.entries[index].state = .moving
            do { try persist() } catch { return .init(recordURL: recordURL, record: record, recordError: error.localizedDescription) }
            do {
                let destination = try trash(url)
                record.entries[index].state = .trashed
                record.entries[index].trashPath = destination?.path
            } catch {
                record.entries[index].state = .failed
                record.entries[index].message = error.localizedDescription
            }
            do { try persist() } catch { return .init(recordURL: recordURL, record: record, recordError: error.localizedDescription) }
            if index == 0, record.entries[0].state != .trashed { break }
        }
        return .init(recordURL: recordURL, record: record, recordError: nil)
    }
}
