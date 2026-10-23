import Foundation

// 布局文件与导出的备份同一格式
public enum LayoutBackup {
    // 固定键顺序并缩进：同样的布局每次写出的字节相同，可直接阅读与对比
    public static func encode(_ document: LayoutDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> LayoutDocument {
        let document = try JSONDecoder().decode(LayoutDocument.self, from: data)
        guard document.schemaVersion == LayoutDocument.currentVersion else {
            throw LayoutStoreError.unsupportedSchema(document.schemaVersion)
        }
        var ids = Set<UUID>()
        var identities = Set<ItemIdentity>()
        for entry in document.extraItems {
            guard ids.insert(entry.id).inserted, identities.insert(entry.identity).inserted,
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (entry.customIconData?.count ?? 0) <= 1_048_576,
                  (entry.cachedIconData?.count ?? 0) <= 1_048_576 else {
                throw LayoutStoreError.invalidItems
            }
            if case .website(let url) = entry.target {
                guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      url.host?.isEmpty == false, url.user == nil, url.password == nil else {
                    throw LayoutStoreError.invalidItems
                }
            }
        }
        return document
    }

    // 未安装的应用保留位置；本机有而备份里没有的排在最后
    public static func makeImport(from backup: LayoutDocument, catalog: [LaunchItem], pageCapacity: Int) -> LaunchpadImport {
        let resolver = CatalogResolver(catalog: catalog)
        var apps: [ItemIdentity] = []
        var folderCount = 0
        for slot in backup.pages.flatMap(\.slots) {
            switch slot {
            case .item(let identity):
                apps.append(identity)
            case .folder(let folder):
                folderCount += 1
                apps += folder.items
            case .empty:
                break
            }
        }
        let reconciled = LayoutEngine.reconcile(layout: backup, catalog: catalog, pageCapacity: pageCapacity)
        return LaunchpadImport(
            document: reconciled.document,
            summary: LaunchpadImportSummary(
                pageCount: backup.pages.filter { !$0.slots.allSatisfy { $0 == .empty } }.count,
                folderCount: folderCount,
                appCount: apps.count,
                installedCount: apps.filter { resolver.item(for: $0) != nil }.count,
                newAppCount: reconciled.appendedApps.count
            )
        )
    }
}
