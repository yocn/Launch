import Foundation

public enum LayoutStoreError: Error, Equatable {
    case unsupportedSchema(Int)
}

public struct LayoutStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> LayoutDocument? {
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return nil
        }
        return try decode(try Data(contentsOf: fileURL))
    }

    public func save(_ document: LayoutDocument) throws {
        let data = try JSONEncoder().encode(document)
        _ = try decode(data)
        try writeValidatedData(data, createBackup: false)
    }

    public func replaceFromImport(_ data: Data) throws {
        _ = try decode(data)
        try writeValidatedData(data, createBackup: true)
    }

    private func decode(_ data: Data) throws -> LayoutDocument {
        let document = try JSONDecoder().decode(LayoutDocument.self, from: data)
        guard document.schemaVersion == LayoutDocument.currentVersion else {
            throw LayoutStoreError.unsupportedSchema(document.schemaVersion)
        }
        return document
    }

    private func writeValidatedData(_ data: Data, createBackup: Bool) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if createBackup, fileManager.fileExists(atPath: fileURL.path()) {
            let backupURL = fileURL.appendingPathExtension("backup")
            try? fileManager.removeItem(at: backupURL)
            try fileManager.copyItem(at: fileURL, to: backupURL)
        }
        try data.write(to: fileURL, options: .atomic)
    }
}
