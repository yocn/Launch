import Foundation

public enum SortField: String, CaseIterable, Sendable {
    case custom
    case name
    case dateAdded
    case lastUsed
}

public enum FolderPlacement: String, CaseIterable, Sendable {
    case mixed
    case first
    case last
}

public struct DisplaySort: Equatable, Sendable {
    public var field: SortField
    public var descending: Bool
    public var sortsFolderContents: Bool
    public var folderPlacement: FolderPlacement

    public init(
        field: SortField = .custom,
        descending: Bool = false,
        sortsFolderContents: Bool = false,
        folderPlacement: FolderPlacement = .mixed
    ) {
        self.field = field
        self.descending = descending
        self.sortsFolderContents = sortsFolderContents
        self.folderPlacement = folderPlacement
    }
}

public struct AppDates: Equatable, Sendable {
    public var added: Date?
    public var lastUsed: Date?

    public init(added: Date? = nil, lastUsed: Date? = nil) {
        self.added = added
        self.lastUsed = lastUsed
    }
}

// 非自定义排序只改显示：各页连成一串排序，保存的布局不变
public enum DisplaySorter {
    public static func sorted(_ pages: [[ResolvedItem]], by sort: DisplaySort, dates: [String: AppDates]) -> [ResolvedItem] {
        let items = pages.joined().compactMap { item -> ResolvedItem? in
            guard sort.sortsFolderContents, case .folder(let folder) = item else {
                return item == .empty ? nil : item
            }
            let apps = order(folder.items.map(ResolvedItem.item), by: sort, dates: dates).compactMap { item -> LaunchItem? in
                if case .item(let app) = item {
                    return app
                }
                return nil
            }
            return .folder(ResolvedFolder(id: folder.id, name: folder.name, items: apps))
        }
        let isFolder = { (item: ResolvedItem) -> Bool in
            if case .folder = item {
                return true
            }
            return false
        }
        switch sort.folderPlacement {
        case .mixed:
            return order(items, by: sort, dates: dates)
        case .first:
            return order(items.filter(isFolder), by: sort, dates: dates) + order(items.filter { !isFolder($0) }, by: sort, dates: dates)
        case .last:
            return order(items.filter { !isFolder($0) }, by: sort, dates: dates) + order(items.filter(isFolder), by: sort, dates: dates)
        }
    }

    private struct Key {
        let item: ResolvedItem
        let name: String
        let spelled: String
        let date: Date?
    }

    private static func order(_ items: [ResolvedItem], by sort: DisplaySort, dates: [String: AppDates]) -> [ResolvedItem] {
        let keys = items.map { item in
            let name = displayName(of: item)
            return Key(item: item, name: name, spelled: SearchName.syllables(of: name).joined(), date: date(of: item, sort.field, dates))
        }
        return keys.sorted { lhs, rhs in
            if sort.field == .dateAdded || sort.field == .lastUsed {
                // 没有日期的总在最后
                switch (lhs.date, rhs.date) {
                case let (left?, right?) where left != right:
                    return sort.descending ? left > right : left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return nameAscending(lhs, rhs)
                }
            }
            return sort.descending ? nameAscending(rhs, lhs) : nameAscending(lhs, rhs)
        }
        .map(\.item)
    }

    // 拼音与字母混排，系统的中文排序会把中文名全放在英文名前
    private static func nameAscending(_ lhs: Key, _ rhs: Key) -> Bool {
        if lhs.spelled != rhs.spelled {
            return lhs.spelled < rhs.spelled
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func displayName(of item: ResolvedItem) -> String {
        switch item {
        case .item(let app):
            app.displayName
        case .folder(let folder):
            folder.name
        case .empty:
            ""
        }
    }

    private static func date(of item: ResolvedItem, _ field: SortField, _ dates: [String: AppDates]) -> Date? {
        let pick = { (app: LaunchItem) -> Date? in
            let entry = dates[app.identity.stableKey]
            return field == .dateAdded ? entry?.added : entry?.lastUsed
        }
        switch item {
        case .item(let app):
            return pick(app)
        case .folder(let folder):
            return folder.items.compactMap(pick).max()
        case .empty:
            return nil
        }
    }
}
