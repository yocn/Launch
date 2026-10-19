import Foundation

public enum LayoutSourceStatus: String, Codable, Equatable, Sendable {
    case missing
    case readableRegularFile
    case readableDirectory
    case unreadable
}

public struct LayoutSourceReport: Codable, Equatable, Sendable {
    public let path: String
    public let status: LayoutSourceStatus
    public let byteCount: Int?

    public init(path: String, status: LayoutSourceStatus, byteCount: Int?) {
        self.path = path
        self.status = status
        self.byteCount = byteCount
    }
}

public struct LaunchpadProbe {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(candidateURLs: [URL]) -> [LayoutSourceReport] {
        candidateURLs.map { url in
            guard fileManager.fileExists(atPath: url.path()) else {
                return LayoutSourceReport(
                    path: url.path(),
                    status: .missing,
                    byteCount: nil
                )
            }

            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
            ) else {
                return LayoutSourceReport(
                    path: url.path(),
                    status: .unreadable,
                    byteCount: nil
                )
            }

            if values.isRegularFile == true {
                return LayoutSourceReport(
                    path: url.path(),
                    status: .readableRegularFile,
                    byteCount: values.fileSize
                )
            }
            if values.isDirectory == true {
                return LayoutSourceReport(
                    path: url.path(),
                    status: .readableDirectory,
                    byteCount: nil
                )
            }
            return LayoutSourceReport(
                path: url.path(),
                status: .unreadable,
                byteCount: nil
            )
        }
    }
}
