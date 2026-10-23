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
    let app: LaunchItem
    let canOpen: Bool
    let canEdit: Bool
    let canUninstall: Bool
    var isHidden = false
    var canManageExtraItems = false
    var isPinned = false
    var pinPage = 0
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
    var canAddWebsite = false
    var pageIndex = 0
}

enum ItemMenuContent: Equatable {
    case selection(SelectionMenuContent)
    case item(AppMenuContent)
    case folder(FolderMenuContent)
    case main(MainMenuContent)
}

enum ItemMenuCommand: Equatable {
    case addWebsite(page: Int)
    case editWebsite(ItemIdentity)
    case editEntryAppearance(ItemIdentity)
    case resetEntryIcon(ItemIdentity)
    case refreshWebsiteIcon(ItemIdentity)
    case pinEntry(ItemIdentity, page: Int)
    case unpinEntry(ItemIdentity)
    case deleteWebsite(ItemIdentity)
    case mergeIntoNewFolder
    case mergeInto(folder: String)
    case moveToPage(Int)
    case moveToNewPage
    case hideSelection
    case open(ResolvedItem)
    case revealInFinder(LaunchItem)
    case showInfo(LaunchItem)
    case hide(LayoutItemID)
    case moveToTrash(LaunchItem)
    case rename(folder: String)
    case ungroup(folder: String)
    case openSettings
    case unhide(LaunchItem)
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
        case .item(let app):
            addAppItems(app, to: menu)
        case .folder(let folder):
            addFolderItems(folder, to: menu)
        case .main(let main):
            if main.canAddWebsite {
                menu.addItem(item("添加网址…", .addWebsite(page: main.pageIndex)))
                menu.addItem(.separator())
            }
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
        let title: String = if case .shortcut = app.target { "运行快捷指令" } else { "打开" }
        menu.addItem(item(title, .open(.item(app)), isEnabled: content.canOpen && app.isAvailable))
        guard app.application != nil else {
            menu.addItem(.separator())
            let id = app.identity
            if content.isPinned {
                menu.addItem(item("从网格移除", .unpinEntry(id), isEnabled: content.canManageExtraItems))
            } else {
                menu.addItem(item("添加到网格", .pinEntry(id, page: content.pinPage), isEnabled: content.canManageExtraItems))
            }
            if case .website = app.target {
                menu.addItem(item("编辑网址…", .editWebsite(id), isEnabled: content.canManageExtraItems))
                menu.addItem(item("刷新网站图标", .refreshWebsiteIcon(id), isEnabled: content.canManageExtraItems))
            }
            menu.addItem(item("更换图标…", .editEntryAppearance(id), isEnabled: content.canManageExtraItems))
            menu.addItem(item("恢复默认图标", .resetEntryIcon(id), isEnabled: content.canManageExtraItems))
            if content.isPinned {
                menu.addItem(item(content.isHidden ? "取消隐藏" : "隐藏",
                                  content.isHidden ? .unhide(app) : .hide(.item(id.stableKey)),
                                  isEnabled: content.canManageExtraItems))
            }
            if case .website = app.target {
                menu.addItem(.separator())
                menu.addItem(item("删除网址入口…", .deleteWebsite(id), isEnabled: content.canManageExtraItems))
            }
            return
        }
        menu.addItem(.separator())
        menu.addItem(item("在访达中显示", .revealInFinder(app)))
        menu.addItem(item("显示简介", .showInfo(app)))
        menu.addItem(.separator())
        if content.isHidden {
            menu.addItem(item("取消隐藏", .unhide(app), isEnabled: content.canEdit))
        } else {
            menu.addItem(item("隐藏", .hide(.item(app.identity.stableKey)), isEnabled: content.canEdit))
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
