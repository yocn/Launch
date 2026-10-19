import Foundation
import SQLite3

public enum LaunchpadReadError: Error, Equatable, Sendable {
    case databaseNotFound
    case openFailed(String)
    case queryFailed(String)
    case missingRoot
}

extension LaunchpadReadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            "未找到旧 Launchpad 数据库"
        case .openFailed(let message):
            "无法打开旧 Launchpad 数据库：\(message)"
        case .queryFailed(let message):
            "读取旧 Launchpad 数据库失败：\(message)"
        case .missingRoot:
            "旧 Launchpad 数据库中没有布局根节点"
        }
    }
}

public struct LaunchpadSnapshotReader {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public static func defaultDatabaseURL() -> URL? {
        let length = confstr(_CS_DARWIN_USER_DIR, nil, 0)
        guard length > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_DIR, &buffer, length) > 0 else {
            return nil
        }
        let directory = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return URL(fileURLWithPath: directory, isDirectory: true)
            .appending(path: "com.apple.dock.launchpad/db/db")
    }

    public func read(databaseURL: URL) throws -> LaunchpadSnapshot {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LaunchpadReadError.databaseNotFound
        }
        let workDirectory = fileManager.temporaryDirectory
            .appending(path: "launch-launchpad-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        let copy = workDirectory.appending(path: "db")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: databaseURL.path + suffix)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }
        let database = try SQLiteDatabase(readOnlyAt: copy)
        return try LaunchpadSnapshotQuery(database: database).snapshot()
    }
}

final class SQLiteDatabase {
    private let handle: OpaquePointer

    init(readOnlyAt url: URL) throws {
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite \(status)"
            sqlite3_close(handle)
            throw LaunchpadReadError.openFailed(message)
        }
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }

    func rows(_ sql: String, _ parameter: Int64? = nil) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LaunchpadReadError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        if let parameter {
            sqlite3_bind_int64(statement, 1, parameter)
        }
        var result: [[String?]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                return result
            }
            guard step == SQLITE_ROW else {
                throw LaunchpadReadError.queryFailed(String(cString: sqlite3_errmsg(handle)))
            }
            result.append((0 ..< sqlite3_column_count(statement)).map { index in
                sqlite3_column_text(statement, index).map { String(cString: $0) }
            })
        }
    }
}

struct LaunchpadSnapshotQuery {
    let database: SQLiteDatabase

    func snapshot() throws -> LaunchpadSnapshot {
        let rootRows = try database.rows("SELECT value FROM dbinfo WHERE key = 'launchpad_root'")
        guard let rootText = rootRows.first?.first ?? nil, let root = Int64(rootText) else {
            throw LaunchpadReadError.missingRoot
        }
        return LaunchpadSnapshot(pages: try pageIDs(parent: root).map { try items(page: $0) })
    }

    private func pageIDs(parent: Int64) throws -> [Int64] {
        try database
            .rows("SELECT rowid FROM items WHERE parent_id = ? AND type = 3 ORDER BY ordering", parent)
            .compactMap { row in row.first.flatMap { $0 }.flatMap { Int64($0) } }
    }

    private func items(page: Int64) throws -> [LaunchpadItem] {
        let rows = try database.rows("""
            SELECT items.rowid, items.type, apps.bundleid, apps.title, groups.title
            FROM items
            LEFT JOIN apps ON apps.item_id = items.rowid
            LEFT JOIN groups ON groups.item_id = items.rowid
            WHERE items.parent_id = ?
            ORDER BY items.ordering
            """, page)
        return try rows.compactMap { row in
            guard let id = row[0].flatMap({ Int64($0) }) else {
                return nil
            }
            switch row[1] {
            case "4":
                guard let bundleIdentifier = row[2], !bundleIdentifier.isEmpty else {
                    return nil
                }
                return .app(LaunchpadApp(bundleIdentifier: bundleIdentifier, title: row[3] ?? bundleIdentifier))
            case "2":
                let apps = try pageIDs(parent: id).flatMap { try items(page: $0) }.compactMap { item in
                    if case .app(let app) = item {
                        return app
                    }
                    return nil
                }
                return .folder(id: id, name: row[4] ?? "", apps: apps)
            default:
                return nil
            }
        }
    }
}
