import Foundation

public struct AppIdentity: Codable, Equatable, Hashable, Sendable {
    public let bundleIdentifier: String?
    public let path: String

    public init(bundleIdentifier: String?, path: String) {
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }

    public var stableKey: String {
        if let bundleIdentifier {
            return "bundle:\(bundleIdentifier)"
        }
        return "path:\(path)"
    }
}

public struct CatalogApp: Codable, Equatable, Hashable, Sendable {
    public let identity: AppIdentity
    public let displayName: String

    public init(identity: AppIdentity, displayName: String) {
        self.identity = identity
        self.displayName = displayName
    }
}

public enum LayoutSlot: Codable, Equatable, Sendable {
    case app(AppIdentity)
    case empty
    case missing(AppIdentity)
}

public struct LayoutPage: Codable, Equatable, Sendable {
    public let slots: [LayoutSlot]

    public init(slots: [LayoutSlot]) {
        self.slots = slots
    }
}

public struct LayoutDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let schemaVersion: Int
    public let pages: [LayoutPage]

    public init(
        schemaVersion: Int = LayoutDocument.currentVersion,
        pages: [LayoutPage] = []
    ) {
        self.schemaVersion = schemaVersion
        self.pages = pages
    }
}
