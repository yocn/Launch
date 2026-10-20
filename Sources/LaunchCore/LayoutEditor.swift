import Foundation

public enum LayoutItemID: Hashable, Sendable {
    case app(String)
    case folder(String)
}

public enum LayoutDropTarget: Equatable, Sendable {
    case insert(page: Int, before: LayoutItemID?)
    case newPage
    case merge(LayoutItemID)
}

public enum LayoutEdit: Equatable, Sendable {
    case move(LayoutItemID, to: LayoutDropTarget)
    case moveGroup([LayoutItemID], to: LayoutDropTarget)
    case mergeIntoNewFolder([LayoutItemID])
    case moveOutOfFolder(app: String, folder: String, to: LayoutDropTarget)
    case reorderInFolder(folder: String, app: String, before: String?)
    case renameFolder(folder: String, name: String)
}

extension ResolvedItem {
    public var layoutID: LayoutItemID? {
        switch self {
        case .app(let app):
            .app(app.identity.stableKey)
        case .folder(let folder):
            .folder(folder.id)
        case .empty:
            nil
        }
    }
}

public enum LayoutEditor {
    public static let untitledFolderName = "未命名"

    public static func apply(
        _ edit: LayoutEdit,
        to document: LayoutDocument,
        catalog: [CatalogApp],
        pageCapacity: Int,
        makeFolderID: () -> String = { "folder-\(UUID().uuidString)" }
    ) -> LayoutDocument {
        var editor = Editor(document: document, catalog: catalog, capacity: pageCapacity, newFolderID: makeFolderID())
        let base = editor.pages
        guard editor.perform(edit), editor.pages != base else {
            return document
        }
        return LayoutDocument(
            schemaVersion: document.schemaVersion,
            pages: editor.pages.map { LayoutPage(slots: $0) }
        )
    }
}

private struct Editor {
    var pages: [[LayoutSlot]]
    let resolver: CatalogResolver
    let capacity: Int
    let newFolderID: String

    init(document: LayoutDocument, catalog: [CatalogApp], capacity: Int, newFolderID: String) {
        let resolver = CatalogResolver(catalog: catalog)
        self.resolver = resolver
        self.capacity = capacity
        self.newFolderID = newFolderID
        pages = document.pages
            .flatMap { Self.split($0.slots.filter { $0 != .empty }, resolver: resolver, capacity: capacity) }
            .filter { !$0.isEmpty }
    }

    // 可见项超过容量的旧页先拆开，使可见页与界面分页一一对应
    static func split(_ slots: [LayoutSlot], resolver: CatalogResolver, capacity: Int) -> [[LayoutSlot]] {
        var result: [[LayoutSlot]] = [[]]
        var visible = 0
        for slot in slots {
            if itemID(of: slot, resolver: resolver) != nil {
                if visible == capacity {
                    result.append([])
                    visible = 0
                }
                visible += 1
            }
            result[result.count - 1].append(slot)
        }
        return result
    }

    static func itemID(of slot: LayoutSlot, resolver: CatalogResolver) -> LayoutItemID? {
        switch slot {
        case .app(let identity):
            resolver.app(for: identity).map { .app($0.identity.stableKey) }
        case .folder(let folder):
            folder.apps.contains { resolver.app(for: $0) != nil } ? .folder(folder.id) : nil
        case .empty:
            nil
        }
    }

    func itemID(of slot: LayoutSlot) -> LayoutItemID? {
        Self.itemID(of: slot, resolver: resolver)
    }

    func key(of identity: AppIdentity) -> String? {
        resolver.app(for: identity)?.identity.stableKey
    }

    func visibleCount(_ page: Int) -> Int {
        pages[page].filter { itemID(of: $0) != nil }.count
    }

    func locate(_ item: LayoutItemID) -> (page: Int, slot: Int)? {
        for (page, slots) in pages.enumerated() {
            if let slot = slots.firstIndex(where: { itemID(of: $0) == item }) {
                return (page, slot)
            }
        }
        return nil
    }

    func documentPage(for target: LayoutDropTarget) -> Int? {
        guard case .insert(let visiblePage, _) = target else {
            return nil
        }
        let visible = pages.indices.filter { visibleCount($0) > 0 }
        return visible.indices.contains(visiblePage) ? visible[visiblePage] : nil
    }

    mutating func perform(_ edit: LayoutEdit) -> Bool {
        switch edit {
        case .move(let item, let target):
            move(item, to: target)
        case .moveGroup(let items, let target):
            moveGroup(items, to: target)
        case .mergeIntoNewFolder(let items):
            mergeIntoNewFolder(items)
        case .moveOutOfFolder(let app, let folder, let target):
            moveOut(app: app, folder: folder, to: target)
        case .reorderInFolder(let folder, let app, let before):
            reorder(folder: folder, app: app, before: before)
        case .renameFolder(let folder, let name):
            rename(folder: folder, name: name)
        }
    }

    mutating func move(_ item: LayoutItemID, to target: LayoutDropTarget) -> Bool {
        guard let source = locate(item) else {
            return false
        }
        if case .merge(let into) = target {
            guard case .app = item, into != item, locate(into) != nil else {
                return false
            }
        }
        let page = documentPage(for: target)
        let slot = pages[source.page].remove(at: source.slot)
        return place(slot, at: target, page: page)
    }

    mutating func place(_ slot: LayoutSlot, at target: LayoutDropTarget, page: Int?) -> Bool {
        switch target {
        case .newPage:
            pages.append([slot])
        case .insert(_, let before):
            guard let page else {
                pages.append([slot])
                break
            }
            if let before, let anchor = locate(before), anchor.page == page {
                pages[page].insert(slot, at: anchor.slot)
            } else {
                pages[page].append(slot)
            }
            cascade(from: page)
        case .merge(let into):
            guard let anchor = locate(into), case .app(let identity) = slot else {
                return false
            }
            switch pages[anchor.page][anchor.slot] {
            case .app(let targetIdentity):
                pages[anchor.page][anchor.slot] = .folder(LayoutFolder(
                    id: newFolderID,
                    name: LayoutEditor.untitledFolderName,
                    apps: [targetIdentity, identity]
                ))
            case .folder(let folder):
                pages[anchor.page][anchor.slot] = .folder(LayoutFolder(
                    id: folder.id,
                    name: folder.name,
                    apps: folder.apps + [identity]
                ))
            case .empty:
                return false
            }
        }
        pages = pages.filter { !$0.isEmpty }
        return true
    }

    mutating func cascade(from start: Int) {
        var page = start
        while page < pages.count, visibleCount(page) > capacity {
            var overflow: [LayoutSlot] = []
            while visibleCount(page) > capacity, let last = pages[page].lastIndex(where: { itemID(of: $0) != nil }) {
                overflow.insert(pages[page].remove(at: last), at: 0)
            }
            if page + 1 == pages.count {
                pages.append([])
            }
            pages[page + 1].insert(contentsOf: overflow, at: 0)
            page += 1
        }
    }

    mutating func moveOut(app: String, folder folderID: String, to target: LayoutDropTarget) -> Bool {
        guard let location = locate(.folder(folderID)),
              case .folder(let folder) = pages[location.page][location.slot],
              let member = folder.apps.firstIndex(where: { key(of: $0) == app }) else {
            return false
        }
        if target == .merge(.folder(folderID)) {
            return reorder(folder: folderID, app: app, before: nil)
        }
        let page = documentPage(for: target)
        var apps = folder.apps
        let identity = apps.remove(at: member)
        var target = target
        switch apps.count {
        case 0:
            pages[location.page].remove(at: location.slot)
        case 1:
            pages[location.page][location.slot] = .app(apps[0])
            // 文件夹解散后，以它为插入锚点的目标改由剩下的应用接替
            if case .insert(let visiblePage, .folder(folderID)?) = target {
                target = .insert(page: visiblePage, before: key(of: apps[0]).map(LayoutItemID.app))
            }
        default:
            pages[location.page][location.slot] = .folder(LayoutFolder(id: folder.id, name: folder.name, apps: apps))
        }
        return place(.app(identity), at: target, page: page)
    }

    mutating func reorder(folder folderID: String, app: String, before: String?) -> Bool {
        guard let location = locate(.folder(folderID)),
              case .folder(let folder) = pages[location.page][location.slot],
              let member = folder.apps.firstIndex(where: { key(of: $0) == app }) else {
            return false
        }
        var apps = folder.apps
        let identity = apps.remove(at: member)
        let index = before.flatMap { anchor in apps.firstIndex { key(of: $0) == anchor } } ?? apps.endIndex
        apps.insert(identity, at: index)
        pages[location.page][location.slot] = .folder(LayoutFolder(id: folder.id, name: folder.name, apps: apps))
        return true
    }

    mutating func rename(folder folderID: String, name: String) -> Bool {
        guard let location = locate(.folder(folderID)),
              case .folder(let folder) = pages[location.page][location.slot] else {
            return false
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pages[location.page][location.slot] = .folder(LayoutFolder(
            id: folder.id,
            name: trimmed.isEmpty ? LayoutEditor.untitledFolderName : trimmed,
            apps: folder.apps
        ))
        return true
    }

    mutating func moveGroup(_ items: [LayoutItemID], to target: LayoutDropTarget) -> Bool {
        switch target {
        case .merge(let into):
            return merge(items.filter { $0 != into }, into: into)
        case .insert(_, let before?) where items.contains(before):
            return false
        default:
            break
        }
        let page = documentPage(for: target)
        let slots = remove(items)
        guard !slots.isEmpty else {
            return false
        }
        let start: Int
        if let page {
            var index = pages[page].endIndex
            if case .insert(_, let before?) = target, let anchor = locate(before), anchor.page == page {
                index = anchor.slot
            }
            pages[page].insert(contentsOf: slots, at: index)
            start = page
        } else {
            pages.append(slots)
            start = pages.count - 1
        }
        cascade(from: start)
        pages = pages.filter { !$0.isEmpty }
        return true
    }

    mutating func mergeIntoNewFolder(_ items: [LayoutItemID]) -> Bool {
        let present = items.filter { locate($0) != nil }
        guard present.count >= 2, let first = locate(present[0]) else {
            return false
        }
        let head = Self.apps(in: pages[first.page][first.slot])
        let members = head + remove(Array(present.dropFirst())).flatMap(Self.apps(in:))
        guard let anchor = locate(present[0]) else {
            return false
        }
        pages[anchor.page][anchor.slot] = .folder(LayoutFolder(
            id: newFolderID,
            name: LayoutEditor.untitledFolderName,
            apps: members
        ))
        pages = pages.filter { !$0.isEmpty }
        return true
    }

    // 选中的文件夹拆开，成员（含未安装应用）并入目标
    mutating func merge(_ items: [LayoutItemID], into target: LayoutItemID) -> Bool {
        guard locate(target) != nil else {
            return false
        }
        let members = remove(items).flatMap(Self.apps(in:))
        guard !members.isEmpty, let anchor = locate(target) else {
            return false
        }
        switch pages[anchor.page][anchor.slot] {
        case .app(let identity):
            pages[anchor.page][anchor.slot] = .folder(LayoutFolder(
                id: newFolderID,
                name: LayoutEditor.untitledFolderName,
                apps: [identity] + members
            ))
        case .folder(let folder):
            pages[anchor.page][anchor.slot] = .folder(LayoutFolder(
                id: folder.id,
                name: folder.name,
                apps: folder.apps + members
            ))
        case .empty:
            return false
        }
        pages = pages.filter { !$0.isEmpty }
        return true
    }

    mutating func remove(_ items: [LayoutItemID]) -> [LayoutSlot] {
        var removed: [LayoutSlot] = []
        for item in items {
            if let location = locate(item) {
                removed.append(pages[location.page].remove(at: location.slot))
            }
        }
        return removed
    }

    static func apps(in slot: LayoutSlot) -> [AppIdentity] {
        switch slot {
        case .app(let identity):
            [identity]
        case .folder(let folder):
            folder.apps
        case .empty:
            []
        }
    }
}
