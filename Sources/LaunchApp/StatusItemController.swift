import AppKit
import LaunchCore

struct LayoutMenuActions {
    let canImport: () -> Bool
    let importLayout: () -> Void
    let canRestore: () -> Bool
    let restoreLayout: () -> Void
    let hiddenApps: () -> [CatalogApp]
    let unhide: (CatalogApp) -> Void
    let unhideAll: () -> Void
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let openItem = NSMenuItem(title: "打开启动器", action: nil, keyEquivalent: " ")
    private let conflictItem = NSMenuItem(title: "⚠︎ 快捷键与 LaunchOS 冲突", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "开机启动", action: nil, keyEquivalent: "")
    private let importItem = NSMenuItem(title: "从 Launchpad 导入布局…", action: nil, keyEquivalent: "")
    private let restoreItem = NSMenuItem(title: "恢复导入前的布局", action: nil, keyEquivalent: "")
    private let hiddenItem = NSMenuItem(title: "隐藏的应用", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "退出 Launch", action: nil, keyEquivalent: "q")
    private let loginItemService: LoginItemService
    private let layoutMenu: LayoutMenuActions
    private let hasHotKeyConflict: () -> Bool
    private let onOpen: () -> Void
    private var hiddenApps: [CatalogApp] = []

    init(
        loginItemService: LoginItemService,
        layoutMenu: LayoutMenuActions,
        hasHotKeyConflict: @escaping () -> Bool,
        onOpen: @escaping () -> Void
    ) {
        self.loginItemService = loginItemService
        self.layoutMenu = layoutMenu
        self.hasHotKeyConflict = hasHotKeyConflict
        self.onOpen = onOpen
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "square.grid.3x3.fill",
            accessibilityDescription: "Launch"
        )
        // Shortcut.description 格式化 Space 时会读取库的资源 bundle，这里直接用 keyEquivalent 显示
        openItem.keyEquivalentModifierMask = [.option]
        openItem.action = #selector(openLauncher)
        openItem.target = self
        conflictItem.isEnabled = false
        loginItem.action = #selector(toggleLoginItem)
        loginItem.target = self
        importItem.action = #selector(importLayout)
        importItem.target = self
        restoreItem.action = #selector(restoreLayout)
        restoreItem.target = self
        quitItem.action = #selector(quit)
        quitItem.target = self

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.items = [openItem, conflictItem, .separator(), loginItem, importItem, restoreItem, hiddenItem, .separator(), quitItem]
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        conflictItem.isHidden = !hasHotKeyConflict()
        let available = loginItemService.isAvailable
        loginItem.isEnabled = available
        loginItem.title = available ? "开机启动" : "开机启动（需安装到 ~/Applications）"
        loginItem.state = loginItemService.isEnabled ? .on : .off
        importItem.isEnabled = layoutMenu.canImport()
        restoreItem.isEnabled = layoutMenu.canRestore()
        hiddenApps = layoutMenu.hiddenApps()
        hiddenItem.isEnabled = !hiddenApps.isEmpty
        hiddenItem.submenu = hiddenAppsMenu()
    }

    private func hiddenAppsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, app) in hiddenApps.enumerated() {
            let item = NSMenuItem(title: app.displayName, action: #selector(unhideApp(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let all = NSMenuItem(title: "全部取消隐藏", action: #selector(unhideAll), keyEquivalent: "")
        all.target = self
        menu.addItem(all)
        return menu
    }

    @objc private func unhideApp(_ sender: NSMenuItem) {
        layoutMenu.unhide(hiddenApps[sender.tag])
    }

    @objc private func unhideAll() {
        layoutMenu.unhideAll()
    }

    @objc private func openLauncher() {
        onOpen()
    }

    @objc private func toggleLoginItem() {
        do {
            try loginItemService.setEnabled(loginItem.state != .on)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func importLayout() {
        layoutMenu.importLayout()
    }

    @objc private func restoreLayout() {
        layoutMenu.restoreLayout()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
