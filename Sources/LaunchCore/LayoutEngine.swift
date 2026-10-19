import Foundation

public struct ReconciledLayout: Equatable, Sendable {
    public let pages: [LayoutPage]
    public let unplacedApps: [CatalogApp]

    public init(pages: [LayoutPage], unplacedApps: [CatalogApp]) {
        self.pages = pages
        self.unplacedApps = unplacedApps
    }
}

public enum LayoutEngine {
    public static func reconcile(
        layout: LayoutDocument,
        catalog: [CatalogApp]
    ) -> ReconciledLayout {
        let orderedCatalog = catalog.sorted {
            $0.identity.path.localizedStandardCompare($1.identity.path) == .orderedAscending
        }
        let byBundleIdentifier = Dictionary(
            orderedCatalog.compactMap { app in
                app.identity.bundleIdentifier.map { ($0, app) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let byPath = Dictionary(
            orderedCatalog.map { ($0.identity.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var matchedKeys = Set<String>()

        let pages = layout.pages.map { page in
            LayoutPage(
                slots: page.slots.map { slot in
                    switch slot {
                    case .empty:
                        return .empty
                    case .app(let identity), .missing(let identity):
                        let app = identity.bundleIdentifier.flatMap { byBundleIdentifier[$0] }
                            ?? byPath[identity.path]
                        guard let app else {
                            return .missing(identity)
                        }
                        matchedKeys.insert(app.identity.stableKey)
                        return .app(app.identity)
                    }
                }
            )
        }

        let unplacedApps = orderedCatalog.filter {
            !matchedKeys.contains($0.identity.stableKey)
        }
        return ReconciledLayout(pages: pages, unplacedApps: unplacedApps)
    }
}
