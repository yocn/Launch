public struct LaunchpadImportSummary: Equatable, Sendable {
    public let pageCount: Int
    public let folderCount: Int
    public let appCount: Int
    public let installedCount: Int
    public let newAppCount: Int

    public init(pageCount: Int, folderCount: Int, appCount: Int, installedCount: Int, newAppCount: Int) {
        self.pageCount = pageCount
        self.folderCount = folderCount
        self.appCount = appCount
        self.installedCount = installedCount
        self.newAppCount = newAppCount
    }

    public var missingCount: Int {
        appCount - installedCount
    }
}

public struct LaunchpadImport: Equatable, Sendable {
    public let document: LayoutDocument
    public let summary: LaunchpadImportSummary
}

public enum LaunchpadImporter {
    public static func makeImport(
        from snapshot: LaunchpadSnapshot,
        catalog: [CatalogApp],
        pageCapacity: Int
    ) -> LaunchpadImport {
        let items = catalog.map(LaunchItem.init(application:))
        let resolver = CatalogResolver(catalog: items)
        var seen = Set<String>()
        var installedKeys = Set<String>()
        var folderCount = 0
        var pageCount = 0
        var pages: [[LayoutSlot]] = []

        func identity(for app: LaunchpadApp) -> ItemIdentity? {
            guard seen.insert(app.bundleIdentifier).inserted else {
                return nil
            }
            let saved = ItemIdentity.application(AppIdentity(bundleIdentifier: app.bundleIdentifier, path: ""))
            guard let installed = resolver.item(for: saved) else {
                return saved
            }
            installedKeys.insert(installed.identity.stableKey)
            return installed.identity
        }

        for page in snapshot.pages {
            var slots: [LayoutSlot] = []
            for item in page {
                switch item {
                case .app(let app):
                    if let identity = identity(for: app) {
                        slots.append(.item(identity))
                    }
                case .folder(let id, let name, let apps):
                    let members = apps.compactMap { identity(for: $0) }
                    if !members.isEmpty {
                        folderCount += 1
                        slots.append(.folder(LayoutFolder(id: "launchpad-\(id)", name: name, items: members)))
                    }
                }
            }
            guard !slots.isEmpty else {
                continue
            }
            pageCount += 1
            pages += stride(from: 0, to: slots.count, by: pageCapacity).map {
                Array(slots[$0 ..< min($0 + pageCapacity, slots.count)])
            }
        }

        let imported = LayoutDocument(pages: pages.map { LayoutPage(slots: $0) })
        let reconciled = LayoutEngine.reconcile(layout: imported, catalog: items, pageCapacity: pageCapacity)
        return LaunchpadImport(
            document: reconciled.document,
            summary: LaunchpadImportSummary(
                pageCount: pageCount,
                folderCount: folderCount,
                appCount: seen.count,
                installedCount: installedKeys.count,
                newAppCount: reconciled.appendedApps.count
            )
        )
    }
}
