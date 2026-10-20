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
            guard let last = pages[page].lastIndex(where: { itemID(of: $0) != nil }) else {
                break
            }
            let overflow = pages[page].remove(at: last)
            if page + 1 == pages.count {
                pages.append([])
            }
            pages[page + 1].insert(overflow, at: 0)
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
}
