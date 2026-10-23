import Foundation

func itemSort(_ lhs: LaunchItem, _ rhs: LaunchItem) -> Bool {
    let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
    return order == .orderedSame ? lhs.identity.stableKey < rhs.identity.stableKey : order == .orderedAscending
}

/// Only application identities contain file paths. Other targets never masquerade as .app bundles.
public enum ItemIdentity: Codable, Equatable, Hashable, Sendable {
    case application(AppIdentity)
    case website(UUID)
    case shortcut(UUID)

    public var applicationIdentity: AppIdentity? {
        guard case .application(let identity) = self else { return nil }
        return identity
    }

    public var stableKey: String {
        switch self {
        case .application(let identity): identity.stableKey
        case .website(let id): "website:\(id.uuidString.lowercased())"
        case .shortcut(let id): "shortcut:\(id.uuidString.lowercased())"
        }
    }
}

public enum ExtraItemTarget: Codable, Equatable, Hashable, Sendable {
    case website(URL)
    case shortcut(UUID)
}

public struct ExtraItemDefinition: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var target: ExtraItemTarget
    public var customIconData: Data?
    public var cachedIconData: Data?
    public var nameOverride: String?

    public init(id: UUID = UUID(), name: String, target: ExtraItemTarget,
                customIconData: Data? = nil, cachedIconData: Data? = nil, nameOverride: String? = nil) {
        self.id = id
        self.name = name
        self.target = target
        self.customIconData = customIconData
        self.cachedIconData = cachedIconData
        self.nameOverride = nameOverride
    }

    public var identity: ItemIdentity {
        switch target {
        case .website: .website(id)
        case .shortcut(let uuid): .shortcut(uuid)
        }
    }
}

public enum LaunchTarget: Equatable, Hashable, Sendable {
    case application(CatalogApp)
    case website(URL)
    case shortcut(UUID)
}

public struct LaunchItem: Equatable, Hashable, Sendable, Identifiable {
    public let identity: ItemIdentity
    public let displayName: String
    public let target: LaunchTarget
    public let iconData: Data?
    public let unavailableReason: String?
    public var id: ItemIdentity { identity }
    public var isAvailable: Bool { unavailableReason == nil }
    public var application: CatalogApp? {
        guard case .application(let app) = target else { return nil }
        return app
    }
    public var category: String? { application?.category }

    public init(application: CatalogApp) {
        identity = .application(application.identity)
        displayName = application.displayName
        target = .application(application)
        iconData = nil
        unavailableReason = nil
    }

    public init(definition: ExtraItemDefinition, unavailableReason: String? = nil) {
        identity = definition.identity
        displayName = definition.nameOverride ?? definition.name
        switch definition.target {
        case .website(let url): target = .website(url)
        case .shortcut(let id): target = .shortcut(id)
        }
        iconData = definition.customIconData ?? definition.cachedIconData
        self.unavailableReason = unavailableReason
    }

    // Convenient application adapter for existing callers and fixtures.
    public init(identity: AppIdentity, displayName: String, category: String? = nil) {
        self.init(application: CatalogApp(identity: identity, displayName: displayName, category: category))
    }
}
