import Foundation

public struct ReconciledLayout: Equatable, Sendable {
    public let pages: [[ResolvedItem]]
    public let document: LayoutDocument
    public let appendedApps: [CatalogApp]
    public let hiddenApps: [CatalogApp]
}

struct CatalogResolver {
    private let byBundleIdentifier: [String: CatalogApp]
    private let byPath: [String: CatalogApp]

    init(catalog: [CatalogApp]) {
        let ordered = catalog.sorted {
            $0.identity.path.localizedStandardCompare($1.identity.path) == .orderedAscending
        }
        byBundleIdentifier = Dictionary(
            ordered.compactMap { app in app.identity.bundleIdentifier.map { ($0, app) } },
            uniquingKeysWith: { first, _ in first }
        )
        byPath = Dictionary(
            ordered.map { ($0.identity.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func app(for identity: AppIdentity) -> CatalogApp? {
        identity.bundleIdentifier.flatMap { byBundleIdentifier[$0] } ?? byPath[identity.path]
    }

    func keys(of identities: [AppIdentity]) -> Set<String> {
        Set(identities.compactMap { app(for: $0)?.identity.stableKey })
    }
}

public enum LayoutEngine {
    public static func reconcile(
        layout: LayoutDocument,
        catalog: [CatalogApp],
        pageCapacity: Int
    ) -> ReconciledLayout {
        let resolver = CatalogResolver(catalog: catalog)
        let hidden = resolver.keys(of: layout.hiddenApps)
        let hiddenApps = catalog
            .filter { hidden.contains($0.identity.stableKey) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        let initial = resolve(layout, with: resolver, hidden: hidden)
        let unplaced = catalog.filter { !initial.placedKeys.contains($0.identity.stableKey) }
        guard !unplaced.isEmpty else {
            return ReconciledLayout(pages: initial.pages, document: layout, appendedApps: [], hiddenApps: hiddenApps)
        }
        let document = appending(unplaced.map(\.identity), to: layout, pageCapacity: pageCapacity)
        return ReconciledLayout(
            pages: resolve(document, with: resolver, hidden: hidden).pages,
            document: document,
            appendedApps: unplaced,
            hiddenApps: hiddenApps
        )
    }

    public static func appending(
        _ identities: [AppIdentity],
        to document: LayoutDocument,
        pageCapacity: Int
    ) -> LayoutDocument {
        var pages = document.pages.map(\.slots)
        for identity in identities {
            if let last = pages.indices.last, pages[last].count < pageCapacity {
                pages[last].append(.app(identity))
            } else {
                pages.append([.app(identity)])
            }
        }
        return LayoutDocument(
            schemaVersion: document.schemaVersion,
            pages: pages.map { LayoutPage(slots: $0) },
            hiddenApps: document.hiddenApps
        )
    }

    public static func defaultDocument(catalog: [CatalogApp], pageCapacity: Int) -> LayoutDocument {
        appending(catalog.map(\.identity), to: LayoutDocument(), pageCapacity: pageCapacity)
    }

    private static func resolve(
        _ document: LayoutDocument,
        with resolver: CatalogResolver,
        hidden: Set<String>
    ) -> (pages: [[ResolvedItem]], placedKeys: Set<String>) {
        var placedKeys = Set<String>()
        let pages: [[ResolvedItem]] = document.pages.compactMap { page in
            let items: [ResolvedItem] = page.slots.compactMap { slot in
                switch slot {
                case .empty:
                    return .empty
                case .app(let identity):
                    guard let app = resolver.app(for: identity) else {
                        return nil
                    }
                    placedKeys.insert(app.identity.stableKey)
                    return hidden.contains(app.identity.stableKey) ? nil : .app(app)
                case .folder(let folder):
                    let apps = folder.apps.compactMap { resolver.app(for: $0) }
                    placedKeys.formUnion(apps.map(\.identity.stableKey))
                    let visible = apps.filter { !hidden.contains($0.identity.stableKey) }
                    guard !visible.isEmpty else {
                        return nil
                    }
                    return .folder(ResolvedFolder(id: folder.id, name: folder.name, apps: visible))
                }
            }
            return items.contains { $0 != .empty } ? items : nil
        }
        return (pages, placedKeys)
    }
}
