import Foundation

public struct ReconciledLayout: Equatable, Sendable {
    public let pages: [[ResolvedItem]]
    public let document: LayoutDocument
    public let appendedApps: [LaunchItem]
    public let hiddenItems: [LaunchItem]
}

struct CatalogResolver {
    private let byKey: [String: LaunchItem]
    private let byPath: [String: LaunchItem]

    init(catalog: [LaunchItem]) {
        let ordered = catalog.sorted {
            $0.identity.stableKey < $1.identity.stableKey
        }
        byKey = Dictionary(
            ordered.map { ($0.identity.stableKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        byPath = Dictionary(
            ordered.compactMap { item in item.application.map { ($0.identity.path, item) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func item(for identity: ItemIdentity) -> LaunchItem? {
        byKey[identity.stableKey] ?? identity.applicationIdentity.flatMap { byPath[$0.path] }
    }

    func keys(of identities: [ItemIdentity]) -> Set<String> {
        Set(identities.compactMap { item(for: $0)?.identity.stableKey })
    }
}

public enum LayoutEngine {
    public static func reconcile(
        layout: LayoutDocument,
        catalog: [LaunchItem],
        pageCapacity: Int
    ) -> ReconciledLayout {
        let resolver = CatalogResolver(catalog: catalog)
        let hidden = resolver.keys(of: layout.hiddenItems)
        let hiddenItems = catalog
            .filter { hidden.contains($0.identity.stableKey) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        let initial = resolve(layout, with: resolver, hidden: hidden)
        let unplaced = catalog.filter { $0.application != nil && !initial.placedKeys.contains($0.identity.stableKey) }
        guard !unplaced.isEmpty else {
            return ReconciledLayout(pages: initial.pages, document: layout, appendedApps: [], hiddenItems: hiddenItems)
        }
        let document = appending(unplaced.map(\.identity), to: layout, pageCapacity: pageCapacity)
        return ReconciledLayout(
            pages: resolve(document, with: resolver, hidden: hidden).pages,
            document: document,
            appendedApps: unplaced,
            hiddenItems: hiddenItems
        )
    }

    public static func appending(
        _ identities: [ItemIdentity],
        to document: LayoutDocument,
        pageCapacity: Int
    ) -> LayoutDocument {
        var pages = document.pages.map(\.slots)
        for identity in identities {
            if let last = pages.indices.last, pages[last].count < pageCapacity {
                pages[last].append(.item(identity))
            } else {
                pages.append([.item(identity)])
            }
        }
        return LayoutDocument(
            schemaVersion: document.schemaVersion,
            pages: pages.map { LayoutPage(slots: $0) },
            hiddenItems: document.hiddenItems,
            extraItems: document.extraItems
        )
    }

    public static func defaultDocument(catalog: [LaunchItem], pageCapacity: Int) -> LayoutDocument {
        appending(catalog.filter { $0.application != nil }.map(\.identity), to: LayoutDocument(), pageCapacity: pageCapacity)
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
                case .item(let identity):
                    guard let app = resolver.item(for: identity) else {
                        return nil
                    }
                    placedKeys.insert(app.identity.stableKey)
                    return hidden.contains(app.identity.stableKey) ? nil : .item(app)
                case .folder(let folder):
                    let apps = folder.items.compactMap { resolver.item(for: $0) }
                    placedKeys.formUnion(apps.map(\.identity.stableKey))
                    let visible = apps.filter { !hidden.contains($0.identity.stableKey) }
                    guard !visible.isEmpty else {
                        return nil
                    }
                    return .folder(ResolvedFolder(id: folder.id, name: folder.name, items: visible))
                }
            }
            return items.contains { $0 != .empty } ? items : nil
        }
        return (pages, placedKeys)
    }
}
