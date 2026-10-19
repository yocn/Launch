import Foundation

public struct AppCatalog {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(roots: [URL]) throws -> [CatalogApp] {
        var discovered = [CatalogApp]()

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else {
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                // Safari 的入口是带 hidden 标志的符号链接，.skipsHiddenFiles 会把它跳过
                if url.lastPathComponent.hasPrefix(".") {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension == "app" else {
                    continue
                }
                enumerator.skipDescendants()
                if let app = catalogApp(at: url) {
                    discovered.append(app)
                }
            }
        }

        let pathOrdered = discovered.sorted {
            $0.identity.path.localizedStandardCompare($1.identity.path) == .orderedAscending
        }
        var seenBundleIdentifiers = Set<String>()
        let deduplicated = pathOrdered.filter { app in
            guard let bundleIdentifier = app.identity.bundleIdentifier else {
                return true
            }
            return seenBundleIdentifiers.insert(bundleIdentifier).inserted
        }
        return deduplicated.sorted(by: appSort)
    }

    private func catalogApp(at url: URL) -> CatalogApp? {
        guard let bundle = Bundle(url: url) else {
            return nil
        }
        let displayName = (
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ) ?? (
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        ) ?? url.deletingPathExtension().lastPathComponent

        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.path.hasSuffix("/")
            ? String(standardizedURL.path.dropLast())
            : standardizedURL.path
        return CatalogApp(
            identity: AppIdentity(
                bundleIdentifier: bundle.bundleIdentifier,
                path: path
            ),
            displayName: displayName
        )
    }
}

func appSort(_ lhs: CatalogApp, _ rhs: CatalogApp) -> Bool {
    let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
    if nameOrder != .orderedSame {
        return nameOrder == .orderedAscending
    }
    return lhs.identity.path.localizedStandardCompare(rhs.identity.path) == .orderedAscending
}
