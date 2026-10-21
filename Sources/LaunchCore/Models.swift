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
    // Info.plist 的 LSApplicationCategoryType
    public let category: String?

    public init(identity: AppIdentity, displayName: String, category: String? = nil) {
        self.identity = identity
        self.displayName = displayName
        self.category = category
    }
}

public struct LayoutFolder: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let apps: [AppIdentity]

    public init(id: String, name: String, apps: [AppIdentity]) {
        self.id = id
        self.name = name
        self.apps = apps
    }
}

public enum LayoutSlot: Codable, Equatable, Sendable {
    case app(AppIdentity)
    case folder(LayoutFolder)
    case empty
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
    public let hiddenApps: [AppIdentity]

    public init(
        schemaVersion: Int = LayoutDocument.currentVersion,
        pages: [LayoutPage] = [],
        hiddenApps: [AppIdentity] = []
    ) {
        self.schemaVersion = schemaVersion
        self.pages = pages
        self.hiddenApps = hiddenApps
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case pages
        case hiddenApps
    }

    // 早期文件没有 hiddenApps
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        pages = try container.decode([LayoutPage].self, forKey: .pages)
        hiddenApps = try container.decodeIfPresent([AppIdentity].self, forKey: .hiddenApps) ?? []
    }
}

public struct ResolvedFolder: Equatable, Sendable {
    public let id: String
    public let name: String
    public let apps: [CatalogApp]

    public init(id: String, name: String, apps: [CatalogApp]) {
        self.id = id
        self.name = name
        self.apps = apps
    }
}

public enum ResolvedItem: Equatable, Sendable {
    case app(CatalogApp)
    case folder(ResolvedFolder)
    case empty
}
