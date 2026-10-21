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
    var isHidden = false
}

struct FolderMenuContent: Equatable {
    let folder: ResolvedFolder
    let canEdit: Bool
}

struct MainMenuContent: Equatable {
    let canSelectAll: Bool
    let canArrange: Bool
    var sort = DisplaySort()
    var browsingStyle = BrowsingStyle.paged
    var displayMode = DisplayMode.fullScreen
}

enum ItemMenuContent: Equatable {
    case selection(SelectionMenuContent)
    case app(AppMenuContent)
    case folder(FolderMenuContent)
    case main(MainMenuContent)
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
    case openSettings
    case unhide(CatalogApp)
    case selectAll
    case arrangeLayout
    case sortField(SortField)
    case sortDescending(Bool)
    case sortsFolderContents(Bool)
    case folderPlacement(FolderPlacement)
    case browsingStyle(BrowsingStyle)
    case displayMode(DisplayMode)
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
        case .main(let main):
            let selectAll = item("全选", .selectAll, isEnabled: main.canSelectAll)
            selectAll.keyEquivalent = "a"
            menu.addItem(selectAll)
            menu.addItem(item("整理布局…", .arrangeLayout, isEnabled: main.canArrange))
            menu.addItem(sortItem(main.sort))
            menu.addItem(browsingItem(main.browsingStyle))
            menu.addItem(displayModeItem(main.displayMode))
            menu.addItem(.separator())
            menu.addItem(item("设置…", .openSettings))
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
        if content.isHidden {
            menu.addItem(item("取消隐藏", .unhide(app), isEnabled: content.canEdit))
        } else {
            menu.addItem(item("隐藏", .hide(.app(app.identity.stableKey)), isEnabled: content.canEdit))
        }
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

    private func displayModeItem(_ mode: DisplayMode) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("全屏", .displayMode(.fullScreen), checked: mode == .fullScreen))
        menu.addItem(item("窗口", .displayMode(.window), checked: mode == .window))
        let display = NSMenuItem(title: "显示方式", action: nil, keyEquivalent: "")
        display.submenu = menu
        return display
    }

    private func browsingItem(_ style: BrowsingStyle) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("分页", .browsingStyle(.paged), checked: style == .paged))
        menu.addItem(item("滚动", .browsingStyle(.scroll), checked: style == .scroll))
        let browsing = NSMenuItem(title: "浏览方式", action: nil, keyEquivalent: "")
        browsing.submenu = menu
        return browsing
    }

    private func sortItem(_ sort: DisplaySort) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let fields: [(String, SortField)] = [("自定义", .custom), ("名称", .name), ("添加日期", .dateAdded), ("上次使用", .lastUsed)]
        for (title, field) in fields {
            menu.addItem(item(title, .sortField(field), checked: sort.field == field))
        }
        // 自定义时方向与文件夹选项不起作用
        let sorted = sort.field != .custom
        menu.addItem(.separator())
        menu.addItem(item("升序", .sortDescending(false), isEnabled: sorted, checked: !sort.descending))
        menu.addItem(item("降序", .sortDescending(true), isEnabled: sorted, checked: sort.descending))
        menu.addItem(.separator())
        menu.addItem(item("同时排序文件夹内应用", .sortsFolderContents(!sort.sortsFolderContents), isEnabled: sorted, checked: sort.sortsFolderContents))
        let placements: [(String, FolderPlacement)] = [("与应用混排", .mixed), ("其他应用前", .first), ("其他应用后", .last)]
        let placementMenu = NSMenu()
        placementMenu.autoenablesItems = false
        for (title, placement) in placements {
            placementMenu.addItem(item(title, .folderPlacement(placement), checked: sort.folderPlacement == placement))
        }
        let placementItem = NSMenuItem(title: "文件夹位置", action: nil, keyEquivalent: "")
        placementItem.submenu = placementMenu
        placementItem.isEnabled = sorted
        menu.addItem(placementItem)
        let sortItem = NSMenuItem(title: "排序方式", action: nil, keyEquivalent: "")
        sortItem.submenu = menu
        return sortItem
    }

    private func item(_ title: String, _ command: ItemMenuCommand, isEnabled: Bool = true, checked: Bool) -> NSMenuItem {
        let item = item(title, command, isEnabled: isEnabled)
        item.state = checked ? .on : .off
        return item
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
