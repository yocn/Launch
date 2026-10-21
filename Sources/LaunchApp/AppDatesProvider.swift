import CoreServices
import Foundation
import LaunchCore

enum AppDatesProvider {
    // 添加日期取文件系统（与访达一致，Spotlight 对系统应用没有）；上次使用取 Spotlight。查询可能慢，放在后台
    static func load(_ apps: [CatalogApp], completion: @escaping @MainActor @Sendable ([String: AppDates]) -> Void) {
        let entries = apps.map { ($0.identity.stableKey, $0.identity.path) }
        DispatchQueue.global(qos: .utility).async {
            var dates: [String: AppDates] = [:]
            for (key, path) in entries {
                let added = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
                let lastUsed = MDItemCreate(nil, path as CFString).flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
                dates[key] = AppDates(added: added, lastUsed: lastUsed)
            }
            Task { @MainActor in
                completion(dates)
            }
        }
    }
}
