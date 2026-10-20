import AppKit

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

enum SelectionCommand: Equatable {
    case mergeIntoNewFolder
    case mergeInto(folder: String)
    case moveToPage(Int)
    case moveToNewPage
}

@MainActor
final class SelectionMenu: NSObject {
    private let onCommand: (SelectionCommand) -> Void
    private var commands: [SelectionCommand] = []

    init(onCommand: @escaping (SelectionCommand) -> Void) {
        self.onCommand = onCommand
    }

    func makeMenu(_ content: SelectionMenuContent) -> NSMenu {
        commands = []
        let menu = NSMenu()
        menu.autoenablesItems = false
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
        return menu
    }

    private func item(_ title: String, _ command: SelectionCommand, isEnabled: Bool = true) -> NSMenuItem {
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
