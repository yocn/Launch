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
    public let items: [ItemIdentity]

    public init(id: String, name: String, apps: [AppIdentity]) {
        self.id = id
        self.name = name
        self.items = apps.map(ItemIdentity.application)
    }

    public init(id: String, name: String, items: [ItemIdentity]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

public enum LayoutSlot: Codable, Equatable, Sendable {
    case item(ItemIdentity)
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
    public static let currentVersion = 2

    public let schemaVersion: Int
    public let pages: [LayoutPage]
    public let hiddenItems: [ItemIdentity]
    public let extraItems: [ExtraItemDefinition]

    public init(
        schemaVersion: Int = LayoutDocument.currentVersion,
        pages: [LayoutPage] = [],
        hiddenItems: [ItemIdentity] = [],
        extraItems: [ExtraItemDefinition] = []
    ) {
        self.schemaVersion = schemaVersion
        self.pages = pages
        self.hiddenItems = hiddenItems
        self.extraItems = extraItems
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case pages
        case hiddenItems
        case extraItems
    }

    // v1 按旧格式读入后转成当前格式，最早的 v1 文件没有 hiddenApps
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 || version == Self.currentVersion else {
            throw LayoutStoreError.unsupportedSchema(version)
        }
        schemaVersion = Self.currentVersion
        if version == 1 {
            let old = try LegacyLayoutDocument(from: decoder)
            pages = old.pages.map { LayoutPage(slots: $0.slots.map { $0.converted }) }
            hiddenItems = (old.hiddenApps ?? []).map(ItemIdentity.application)
            extraItems = []
        } else {
            pages = try container.decode([LayoutPage].self, forKey: .pages)
            hiddenItems = try container.decodeIfPresent([ItemIdentity].self, forKey: .hiddenItems) ?? []
            extraItems = try container.decodeIfPresent([ExtraItemDefinition].self, forKey: .extraItems) ?? []
        }
    }
}

public struct ResolvedFolder: Equatable, Sendable {
    public let id: String
    public let name: String
    public let items: [LaunchItem]

    public init(id: String, name: String, items: [LaunchItem]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

public enum ResolvedItem: Equatable, Sendable {
    case item(LaunchItem)
    case folder(ResolvedFolder)
    case empty
}

private struct LegacyLayoutDocument: Decodable {
    struct Page: Decodable { let slots: [Slot] }
    struct Folder: Decodable { let id: String; let name: String; let apps: [AppIdentity] }
    enum Slot: Decodable {
        case app(AppIdentity), folder(Folder), empty
        var converted: LayoutSlot {
            switch self {
            case .app(let app): .item(.application(app))
            case .folder(let folder): .folder(LayoutFolder(id: folder.id, name: folder.name, apps: folder.apps))
            case .empty: .empty
            }
        }
    }
    let pages: [Page]
    let hiddenApps: [AppIdentity]?
}
