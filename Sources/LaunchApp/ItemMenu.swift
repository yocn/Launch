import AppKit
import LaunchCore

struct SelectionMenuContent: Equatable {
    struct Folder: Equatable {
        let id: String
        let name: String
    }

    let count: Int
    let folders: [Folder]
    let pageCount: Int

    var canMerge: Bool {
        count >= 2
    }
}

struct AppMenuContent: Equatable {
    let app: CatalogApp
    let canOpen: Bool
    let canEdit: Bool
    let canUninstall: Bool
}

struct FolderMenuContent: Equatable {
    let folder: ResolvedFolder
    let canEdit: Bool
}

enum ItemMenuContent: Equatable {
    case selection(SelectionMenuContent)
    case app(AppMenuContent)
    case folder(FolderMenuContent)
}

enum ItemMenuCommand: Equatable {
    case mergeIntoNewFolder
    case mergeInto(folder: String)
    case moveToPage(Int)
    case moveToNewPage
    case hideSelection
    case open(ResolvedItem)
    case revealInFinder(CatalogApp)
    case showInfo(CatalogApp)
    case hide(LayoutItemID)
    case moveToTrash(CatalogApp)
    case rename(folder: String)
    case ungroup(folder: String)
}

@MainActor
final class ItemMenu: NSObject {
    private let onCommand: (ItemMenuCommand) -> Void
    private var commands: [ItemMenuCommand] = []

    init(onCommand: @escaping (ItemMenuCommand) -> Void) {
        self.onCommand = onCommand
    }

    func makeMenu(_ content: ItemMenuContent) -> NSMenu {
        commands = []
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch content {
        case .selection(let selection):
            addSelectionItems(selection, to: menu)
        case .app(let app):
            addAppItems(app, to: menu)
        case .folder(let folder):
            addFolderItems(folder, to: menu)
        }
        return menu
    }

    private func addSelectionItems(_ content: SelectionMenuContent, to menu: NSMenu) {
        let header = NSMenuItem(title: "已选中 \(content.count) 个项目", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item("合并到新文件夹", .mergeIntoNewFolder, isEnabled: content.canMerge))
        if content.canMerge {
            for folder in content.folders {
                menu.addItem(item("合并到“\(folder.name)”", .mergeInto(folder: folder.id)))
            }
        }
        menu.addItem(.separator())
        let pages = NSMenu()
        pages.autoenablesItems = false
        for page in 0 ..< content.pageCount {
            pages.addItem(item("第 \(page + 1) 页", .moveToPage(page)))
        }
        pages.addItem(.separator())
        pages.addItem(item("新页面", .moveToNewPage))
        let move = NSMenuItem(title: "移动到", action: nil, keyEquivalent: "")
        move.submenu = pages
        menu.addItem(move)
        menu.addItem(item("隐藏", .hideSelection))
    }

    private func addAppItems(_ content: AppMenuContent, to menu: NSMenu) {
        let app = content.app
        menu.addItem(item("打开", .open(.app(app)), isEnabled: content.canOpen))
        menu.addItem(.separator())
        menu.addItem(item("在访达中显示", .revealInFinder(app)))
        menu.addItem(item("显示简介", .showInfo(app)))
        menu.addItem(.separator())
        menu.addItem(item("隐藏", .hide(.app(app.identity.stableKey)), isEnabled: content.canEdit))
        if content.canUninstall {
            menu.addItem(item("移到废纸篓…", .moveToTrash(app)))
        }
    }

    private func addFolderItems(_ content: FolderMenuContent, to menu: NSMenu) {
        let folder = content.folder
        menu.addItem(item("打开", .open(.folder(folder))))
        menu.addItem(.separator())
        menu.addItem(item("重命名", .rename(folder: folder.id), isEnabled: content.canEdit))
        menu.addItem(item("取消分组", .ungroup(folder: folder.id), isEnabled: content.canEdit))
        menu.addItem(item("隐藏", .hide(.folder(folder.id)), isEnabled: content.canEdit))
    }

    private func item(_ title: String, _ command: ItemMenuCommand, isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.tag = commands.count
        item.isEnabled = isEnabled
        commands.append(command)
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        onCommand(commands[sender.tag])
    }
}
