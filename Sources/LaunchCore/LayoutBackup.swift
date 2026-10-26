import Foundation
import ImageIO

// 布局文件与导出的备份同一格式
public enum LayoutBackup {
    // 固定键顺序并缩进：同样的布局每次写出的字节相同，可直接阅读与对比
    public static func encode(_ document: LayoutDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    // 图片解码较慢：读取外部文件时校验；保存自己生成的布局时图片已规范化，可跳过
    public static func decode(_ data: Data, checksArtwork: Bool = true) throws -> LayoutDocument {
        let document = try JSONDecoder().decode(LayoutDocument.self, from: data)
        guard document.schemaVersion == LayoutDocument.currentVersion else {
            throw LayoutStoreError.unsupportedSchema(document.schemaVersion)
        }
        var ids = Set<UUID>()
        var identities = Set<ItemIdentity>()
        for entry in document.extraItems {
            guard ids.insert(entry.id).inserted, identities.insert(entry.identity).inserted,
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !checksArtwork || (entry.customIconData.map(validArtwork) ?? true),
                  !checksArtwork || (entry.cachedIconData.map(validArtwork) ?? true) else {
                throw LayoutStoreError.invalidItems
            }
            if case .website(let url) = entry.target {
                guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      url.host?.isEmpty == false, url.user == nil, url.password == nil else {
                    throw LayoutStoreError.invalidItems
                }
            }
        }
        var placed = Set<String>()
        var folders = Set<String>()
        func validateReference(_ identity: ItemIdentity) throws {
            guard placed.insert(identity.stableKey).inserted,
                  identity.applicationIdentity != nil || identities.contains(identity) else {
                throw LayoutStoreError.invalidItems
            }
        }
        for slot in document.pages.flatMap(\.slots) {
            switch slot {
            case .empty: break
            case .item(let identity): try validateReference(identity)
            case .folder(let folder):
                guard !folder.id.isEmpty, folders.insert(folder.id).inserted else { throw LayoutStoreError.invalidItems }
                for identity in folder.items { try validateReference(identity) }
            }
        }
        for identity in document.hiddenItems where identity.applicationIdentity == nil && !identities.contains(identity) {
            throw LayoutStoreError.invalidItems
        }
        return document
    }

    // Check headers before bounded thumbnail decoding; never hand imported bytes straight to NSImage.
    private static func validArtwork(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= 1_048_576,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              (1 ... 32).contains(CGImageSourceGetCount(source)) else { return false }
        for index in 0 ..< CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1 ... 8192).contains(width), (1 ... 8192).contains(height),
                  CGImageSourceCreateThumbnailAtIndex(source, index, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else { return false }
        }
        return true
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
