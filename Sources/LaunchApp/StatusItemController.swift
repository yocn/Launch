import AppKit
import LaunchCore

struct LayoutMenuActions {
    let canImport: () -> Bool
    let importLayout: () -> Void
    let canRestore: () -> Bool
    let restoreLayout: () -> Void
    let hiddenItems: () -> [LaunchItem]
    let unhide: (LaunchItem) -> Void
    let unhideAll: () -> Void
}

enum StatusItemClick: Equatable {
    case open
    case menu

    // ⌃ 单击按 macOS 惯例等同右键；辅助功能「按下」没有鼠标事件，按左键处理
    init(type: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags) {
        self = type == .rightMouseUp || modifiers.contains(.control) ? .menu : .open
    }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let conflictItem = NSMenuItem(title: "⚠︎ 快捷键与 LaunchOS 冲突", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "开机启动", action: nil, keyEquivalent: "")
    private let importItem = NSMenuItem(title: "从 Launchpad 导入布局…", action: nil, keyEquivalent: "")
    private let restoreItem = NSMenuItem(title: "恢复导入前的布局", action: nil, keyEquivalent: "")
    private let hiddenItem = NSMenuItem(title: "隐藏的应用", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "设置…", action: nil, keyEquivalent: ",")
    private let guideItem = NSMenuItem(title: "使用说明", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "退出 Launch", action: nil, keyEquivalent: "q")
    private let menu = NSMenu()
    private let loginItemService: LoginItemService
    private let layoutMenu: LayoutMenuActions
    private let hasHotKeyConflict: () -> Bool
    private let onOpen: () -> Void
    private let onOpenSettings: () -> Void
    private var hiddenItems: [LaunchItem] = []

    init(
        loginItemService: LoginItemService,
        layoutMenu: LayoutMenuActions,
        hasHotKeyConflict: @escaping () -> Bool,
        onOpen: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.loginItemService = loginItemService
        self.layoutMenu = layoutMenu
        self.hasHotKeyConflict = hasHotKeyConflict
        self.onOpen = onOpen
        self.onOpenSettings = onOpenSettings
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "square.grid.3x3.fill",
            accessibilityDescription: "Launch"
        )
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        conflictItem.isEnabled = false
        loginItem.action = #selector(toggleLoginItem)
        loginItem.target = self
        importItem.action = #selector(importLayout)
        importItem.target = self
        restoreItem.action = #selector(restoreLayout)
        restoreItem.target = self
        quitItem.action = #selector(quit)
        quitItem.target = self
        settingsItem.action = #selector(openSettings)
        settingsItem.target = self
        guideItem.action = #selector(openGuide)
        guideItem.target = self
        guideItem.isEnabled = UserGuide.url != nil
        guideItem.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)

        menu.autoenablesItems = false
        menu.delegate = self
        menu.items = [
            settingsItem, guideItem, conflictItem, .separator(), loginItem, importItem, restoreItem, hiddenItem, .separator(), quitItem,
        ]
    }

    @objc private func openGuide() {
        UserGuide.open()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        switch StatusItemClick(type: event?.type, modifiers: event?.modifierFlags ?? []) {
        case .open:
            onOpen()
        case .menu:
            // 常挂菜单会让左键也弹菜单，只在弹出时临时挂上；performClick 会等菜单关闭才返回
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        conflictItem.isHidden = !hasHotKeyConflict()
        let available = loginItemService.isAvailable
        loginItem.isEnabled = available
        loginItem.title = available ? "开机启动" : "开机启动（需安装到 ~/Applications）"
        loginItem.state = loginItemService.isEnabled ? .on : .off
        importItem.isEnabled = layoutMenu.canImport()
        restoreItem.isEnabled = layoutMenu.canRestore()
        hiddenItems = layoutMenu.hiddenItems()
        hiddenItem.isEnabled = !hiddenItems.isEmpty
        hiddenItem.submenu = hiddenItemsMenu()
    }

    private func hiddenItemsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, app) in hiddenItems.enumerated() {
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
        layoutMenu.unhide(hiddenItems[sender.tag])
    }

    @objc private func unhideAll() {
        layoutMenu.unhideAll()
    }

    // 与程序坞上的应用图标同一张；不用模板图，保持原来的颜色
    func setIcon(_ image: NSImage) {
        let icon = image.copy() as? NSImage ?? image
        icon.size = NSSize(width: 20, height: 20)
        icon.isTemplate = false
        icon.accessibilityDescription = "Launch"
        statusItem.button?.image = icon
    }

    func setIconVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    @objc private func openSettings() {
        onOpenSettings()
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
