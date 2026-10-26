import AppKit
import LaunchCore
import SwiftUI
import XCTest
@testable import LaunchApp

/// Opt-in manual acceptance harness. No user defaults, layout, system shortcuts or app files are changed.
@MainActor final class ExtraItemsUIPreviewTests: XCTestCase {
    func testInteractiveTemporaryLayout() throws {
        guard ProcessInfo.processInfo.environment["LAUNCH_EXTRA_ITEMS_PREVIEW"] == "1" else {
            throw XCTSkip("交互验收需显式设置 LAUNCH_EXTRA_ITEMS_PREVIEW=1")
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let root = try makeTemporaryDirectory()
        print("UI_PREVIEW_DATA: \(root.path)")
        let store = LayoutStore(fileURL: root.appendingPathComponent("layout.json"))
        try store.save(LayoutDocument())
        let layout = LayoutCoordinator(store: store, launchpad: NoEntryLaunchpad(), prompter: EntryPrompter(), log: makeTestLog())
        layout.start()
        let id = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let extras = ExtraItemsController(layout: layout, shortcuts: ShortcutService(execute: { args, _ in
            args.first == "list" ? "预览指令 (88888888-8888-8888-8888-888888888888)" : ""
        }), fetchIcon: { _ in nil })
        let presenter = ScreenPresenter()
        let model = LauncherModel()
        let controller = LauncherController(model: model, presenter: presenter, iconCache: .shared, openApplication: { _ in })
        let suite = "dev.yocn.launch.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = LauncherSettings(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        layout.onLayoutChange = { pages in model.canEditLayout = layout.isEditable; model.updateHiddenItems(layout.hiddenItems); model.updateLayout(pages) }
        layout.onDocumentChange = { extras.layoutDidChange() }
        extras.onCatalogChange = { items in controller.updateCatalog(items); Task { await layout.catalogDidChange(items) } }
        model.onEdit = { layout.apply($0) }
        controller.onUndoLayoutEdit = { layout.undo() }
        controller.onOpenWebsite = { _ in model.showHint("预览不打开外部网址") }
        controller.onRunShortcut = { id in Task { _ = try? await extras.runShortcut(id: id) } }
        Task {
            await layout.catalogDidChange([])
            do {
                _ = try extras.saveWebsite(name: "示例网站", address: "example.com", existing: nil, toPage: 0, customIconData: nil)
            } catch {
                XCTFail("预览数据准备失败：\(error.localizedDescription)")
            }
            await extras.refreshShortcuts()
            extras.pin(.shortcut(id), toPage: 0)
            extras.setApplications(makeLaunchItems(count: 8).compactMap(\.application))
            await layout.catalogDidChange(extras.items)
        }
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 520, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Launch 扩展条目验收（临时布局）"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: VStack(spacing: 0) {
            ExtraItemsSettingsView(controller: extras, currentPage: { model.currentPage }).frame(width: 520, height: 440)
            HStack {
                Button("启动器") { controller.show() }
                Button("浅色") { NSApp.appearance = NSAppearance(named: .aqua) }
                Button("深色") { NSApp.appearance = NSAppearance(named: .darkAqua) }
                Button("结束验收") { NSApp.stop(nil) }
            }.padding()
        })
        controller.isSettingsOpen = { window.isVisible }
        let perform: (ItemMenuCommand) -> Void = { command in
            switch command {
            case .addWebsite(let page): ExtraItemEditor.showWebsite(controller: extras, toPage: page)
            case .addBookmarks: break
            case .editWebsite(let identity): ExtraItemEditor.showWebsite(controller: extras, existing: extras.definitions.first { $0.identity == identity })
            case .pinEntry(let identity, let page): extras.pin(identity, toPage: page)
            case .unpinEntry(let identity): extras.unpin(identity)
            case .deleteWebsite(let identity):
                if let item = extras.items.first(where: { $0.identity == identity }) { ExtraItemEditor.confirmDelete(item, controller: extras) }
            case .editEntryAppearance(let identity):
                if let item = extras.items.first(where: { $0.identity == identity }) { ExtraItemEditor.showAppearance(item: item, controller: extras) }
            case .open(let item): if case .item(let item) = item { controller.launch(item) }
            case .openSettings: window.makeKeyAndOrderFront(nil)
            default: model.performMenuCommand(command)
            }
        }
        let drag = ItemDragController(model: model, presenter: presenter, onActivate: { item in
            if case .item(let item) = item { controller.launch(item) }
            else if case .folder(let folder) = item { model.showFolder(id: folder.id) }
        }, onUninstall: { _ in XCTFail("非应用不能进入卸载") }, onMenuCommand: perform, makeDragImage: { _, _ in nil })
        presenter.setContent(LauncherView(model: model, settings: settings, onEscape: { controller.handleEscape() },
                                          onBackgroundClick: { controller.handleBackgroundClick() }, onLaunch: { controller.launch($0) },
                                          onMainMenu: { drag.showMainMenu() }))
        drag.start()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.finishLaunching()
        let timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { _ in MainActor.assumeIsolated { NSApp.stop(nil) } }
        NSApp.run()
        timer.invalidate()
        controller.hide(.escape)
        window.close()
        XCTAssertNotNil(try store.load())
    }
}
