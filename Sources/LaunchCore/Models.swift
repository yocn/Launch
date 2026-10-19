import Foundation

public struct LayoutDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let schemaVersion: Int

    public init(schemaVersion: Int = LayoutDocument.currentVersion) {
        self.schemaVersion = schemaVersion
    }
}
