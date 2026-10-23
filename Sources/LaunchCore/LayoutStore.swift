import Foundation

public enum LayoutStoreError: Error, Equatable {
    case unsupportedSchema(Int)
    case invalidItems
}

extension LayoutStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "布局文件版本 \(version) 不受支持"
        case .invalidItems:
            "布局中的条目定义无效、重复或图标过大"
        }
    }
}

public struct LayoutStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public var backupURL: URL {
        fileURL.appendingPathExtension("backup")
    }

    public var migrationBackupURL: URL { fileURL.appendingPathExtension("v1-backup") }

    public var hasBackup: Bool {
        fileManager.fileExists(atPath: backupURL.path(percentEncoded: false))
    }

    public func load() throws -> LayoutDocument? {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }
        return try decode(try Data(contentsOf: fileURL))
    }

    public func save(_ document: LayoutDocument) throws {
        let data = try LayoutBackup.encode(document)
        _ = try decode(data)
        try writeValidatedData(data, createBackup: false)
    }

    public func replaceFromImport(_ data: Data) throws {
        _ = try decode(data)
        try writeValidatedData(data, createBackup: true)
    }

    public func replace(with document: LayoutDocument) throws {
        try replaceFromImport(try LayoutBackup.encode(document))
    }

    public func swapWithBackup() throws {
        let backupData = try Data(contentsOf: backupURL)
        _ = try decode(backupData)
        let currentData = try? Data(contentsOf: fileURL)
        try backupData.write(to: fileURL, options: .atomic)
        if let currentData {
            try currentData.write(to: backupURL, options: .atomic)
        } else {
            try fileManager.removeItem(at: backupURL)
        }
    }

    private func decode(_ data: Data) throws -> LayoutDocument {
        try LayoutBackup.decode(data)
    }

    private func writeValidatedData(_ data: Data, createBackup: Bool) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: migrationBackupURL.path),
           let original = try? Data(contentsOf: fileURL),
           let json = try? JSONSerialization.jsonObject(with: original) as? [String: Any],
           json["schemaVersion"] as? Int == 1 {
            // Independent of the import/restore backup; never replace a migration snapshot.
            try fileManager.copyItem(at: fileURL, to: migrationBackupURL)
        }
        if createBackup, fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try? fileManager.removeItem(at: backupURL)
            try fileManager.copyItem(at: fileURL, to: backupURL)
        }
        try data.write(to: fileURL, options: .atomic)
    }
}
