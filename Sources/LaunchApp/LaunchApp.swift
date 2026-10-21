import AppKit
import LaunchCore
import SwiftUI

public enum LauncherPlacement: Equatable, Sendable {
    case mouseScreen

    public static let defaultTarget = LauncherPlacement.mouseScreen
}

@main
struct LaunchApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = LaunchAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
private final class LaunchAppDelegate: NSObject, NSApplicationDelegate {
    private let presenter = ScreenPresenter()
    private let loginItemService = LoginItemService()
    private lazy var controller = LauncherController(
        model: LauncherModel(),
        presenter: presenter,
        iconCache: .shared,
        openApplication: { NSWorkspace.shared.open($0) }
    )
    private lazy var layoutCoordinator = LayoutCoordinator(
        store: LayoutStore(fileURL: LayoutCoordinator.defaultLayoutURL),
        launchpad: LiveLaunchpadSource(databaseURL: LaunchpadSnapshotReader.defaultDatabaseURL()),
        prompter: AlertLayoutPrompter(),
        pageCapacity: settings.grid.capacity
    )
    private var statusItemController: StatusItemController?
    private var catalogWatcher: CatalogWatcher?
    private let inputMonitor = LauncherInputMonitor()
    private let appActions = AppActions()
    private let settings = LauncherSettings()
    private let wallpaperProvider = WallpaperProvider()
    private var appliedSortField: SortField?
    private lazy var settingsWindow = SettingsWindowController(
        onWillShow: { [weak self] in self?.controller.hide(.settings) },
        makeContent: { [unowned self] in
            AnyView(SettingsView(
                settings: settings,
                model: controller.model,
                loginItemService: loginItemService,
                hasHotKeyConflict: { [weak self] in self?.hasHotKeyConflict() ?? false },
                onUnhide: { [weak self] app in self?.layoutCoordinator.unhide(app) },
                onUnhideAll: { [weak self] in self?.layoutCoordinator.unhideAll() }
            ))
        }
    )
    private lazy var pagerDriver = PagerDriver(model: controller.model) { [weak self] target, selector in
        self?.presenter.makeDisplayLink(target: target, selector: selector)
    }
    private lazy var uninstallCoordinator = UninstallCoordinator(
        uninstaller: AppUninstaller(),
        prompter: AlertUninstallPrompter(),
        onRemoved: { [weak self] in self?.catalogWatcher?.rescan() }
    )
    private lazy var itemDragController = ItemDragController(
        model: controller.model,
        presenter: presenter,
        onActivate: { [weak self] item in self?.activate(item) },
        onUninstall: { [weak self] app in self?.uninstall(app) },
        onMenuCommand: { [weak self] command in self?.performMenuCommand(command) },
        makeDragImage: { [weak self] item, count in self?.dragImage(for: item, count: count) }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        presenter.setContent(
            LauncherView(
                model: controller.model,
                settings: settings,
                onEscape: { [weak self] in self?.controller.handleEscape() },
                onBackgroundClick: { [weak self] in self?.controller.handleBackgroundClick() },
                onLaunch: { [weak self] app in self?.controller.launch(app) },
                onMainMenu: { [weak self] in self?.itemDragController.showMainMenu() }
            ),
            skipsCursorUpdate: { [weak self] in self?.controller.model.needsPagerFrames ?? false }
        )
        controller.model.onNeedsFrames = { [weak self] in
            self?.pagerDriver.start()
        }
        presenter.onResignActive = { [weak self] in
            self?.controller.hide(.resignedActive)
        }
        layoutCoordinator.onLayoutChange = { [weak self] pages in
            guard let self else {
                return
            }
            controller.model.canEditLayout = layoutCoordinator.isEditable
            controller.model.updateHiddenApps(layoutCoordinator.hiddenApps)
            controller.model.updateLayout(pages)
        }
        controller.model.onEdit = { [weak self] edit in
            self?.layoutCoordinator.apply(edit)
        }
        controller.onUndoLayoutEdit = { [weak self] in
            self?.layoutCoordinator.undo()
        }
        controller.onOpenSettings = { [weak self] in
            self?.settingsWindow.show()
        }
        // 关闭后刷新日期，打开期间不重排
        controller.onHide = { [weak self] in
            self?.refreshAppDates()
        }
        presenter.onPresent = { [weak self] screen in
            guard let self else {
                return
            }
            let wallpaper = settings.background == .glass
                ? nil
                : wallpaperProvider.wallpaper(for: screen, blurred: settings.background == .blurredWallpaper)
            controller.model.updateWallpaper(wallpaper)
        }
        controller.model.canUninstall = { [weak self] app in
            self?.uninstallCoordinator.canUninstall(app) ?? false
        }
        layoutCoordinator.start()
        inputMonitor.start(
            isLauncherWindow: { [weak self] window in self?.presenter.isLauncherWindow(window) ?? false },
            isComposingText: { [weak self] in self?.presenter.isComposingText ?? false },
            isEditingText: { [weak self] in self?.controller.model.renamingFolderID != nil },
            canUndoLayout: { [weak self] in self?.controller.model.query.isEmpty ?? false },
            canSelectAll: { [weak self] in self?.controller.model.mainMenu.canSelectAll ?? false },
            onCommand: { [weak self] command in self?.controller.handle(command) }
        )
        itemDragController.start()
        HotKeyService.register { [weak self] in
            self?.controller.toggle()
        }
        statusItemController = StatusItemController(
            loginItemService: loginItemService,
            layoutMenu: LayoutMenuActions(
                canImport: { [weak self] in self?.layoutCoordinator.canImport ?? false },
                importLayout: { [weak self] in
                    Task { await self?.layoutCoordinator.importFromLaunchpad() }
                },
                canRestore: { [weak self] in self?.layoutCoordinator.canRestore ?? false },
                restoreLayout: { [weak self] in self?.layoutCoordinator.restoreBackup() },
                hiddenApps: { [weak self] in self?.layoutCoordinator.hiddenApps ?? [] },
                unhide: { [weak self] app in self?.layoutCoordinator.unhide(app) },
                unhideAll: { [weak self] in self?.layoutCoordinator.unhideAll() }
            ),
            hasHotKeyConflict: { [weak self] in self?.hasHotKeyConflict() ?? false },
            onOpen: { [weak self] in self?.controller.show() },
            onOpenSettings: { [weak self] in self?.settingsWindow.show() }
        )
        applySettings()
        let watcher = CatalogWatcher(roots: ApplicationSources.defaultRoots()) { [weak self] apps in
            self?.controller.updateCatalog(apps)
            self?.refreshAppDates()
            Task { await self?.layoutCoordinator.catalogDidChange(apps) }
        }
        watcher.start()
        catalogWatcher = watcher
        warnIfHotKeyConflicts()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return false
    }

    private func uninstall(_ app: CatalogApp) {
        Task {
            await uninstallCoordinator.uninstall(app)
        }
    }

    private func activate(_ item: ResolvedItem) {
        switch item {
        case .app(let app):
            controller.launch(app)
        case .folder(let folder):
            controller.model.showFolder(id: folder.id)
        case .empty:
            break
        }
    }

    private func performMenuCommand(_ command: ItemMenuCommand) {
        switch command {
        case .open(let item):
            activate(item)
        case .revealInFinder(let app):
            appActions.revealInFinder(app)
        case .showInfo(let app):
            appActions.showInfo(app)
        case .moveToTrash(let app):
            uninstall(app)
        case .unhide(let app):
            layoutCoordinator.unhide(app)
        case .openSettings:
            settingsWindow.show()
        case .arrangeLayout:
            arrangeLayout()
        case .sortField(let field):
            settings.sortField = field
        case .sortDescending(let descending):
            settings.sortDescending = descending
        case .sortsFolderContents(let sorts):
            settings.sortsFolderContents = sorts
        case .folderPlacement(let placement):
            settings.folderPlacement = placement
        default:
            controller.model.performMenuCommand(command)
        }
    }

    private func refreshAppDates() {
        guard settings.sortField == .dateAdded || settings.sortField == .lastUsed else {
            return
        }
        AppDatesProvider.load(controller.model.apps) { [weak self] dates in
            self?.controller.model.updateAppDates(dates)
        }
    }

    private func arrangeLayout() {
        let model = controller.model
        guard model.mainMenu.canArrange,
              let arrangement = ArrangeLayoutDialog.run(pageCount: model.pages.count, currentPage: model.currentPage) else {
            return
        }
        layoutCoordinator.apply(.arrange(arrangement))
    }

    private func dragImage(for item: ResolvedItem, count: Int) -> NSImage? {
        guard let layout = controller.model.homeLayout else {
            return nil
        }
        return DragCardRenderer.image(
            for: item,
            count: count,
            showsName: !settings.hidesNames,
            layout: layout,
            scale: presenter.backingScaleFactor
        )
    }

    // 设置变化时同步到模型与菜单栏；观察只触发一次，需要重新登记
    private func applySettings() {
        withObservationTracking {
            controller.model.reopensAtFirstPage = settings.reopenBehavior == .firstPage
            controller.model.showsHiddenAppsInSearch = settings.showsHiddenAppsInSearch
            controller.model.updateGrid(settings.grid)
            layoutCoordinator.updatePageCapacity(settings.grid.capacity)
            controller.model.updateDisplaySort(settings.displaySort)
            statusItemController?.setIconVisible(settings.showsMenuBarIcon)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySettings()
            }
        }
        if settings.sortField != appliedSortField {
            appliedSortField = settings.sortField
            refreshAppDates()
        }
    }

    private func hasHotKeyConflict() -> Bool {
        HotKeyConflictDetector.live.conflictsWithLaunchOS(HotKeyService.currentCombination)
    }

    private func warnIfHotKeyConflicts() {
        guard hasHotKeyConflict() else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "快捷键与 LaunchOS 冲突"
        alert.informativeText = "LaunchOS 正在使用相同的快捷键。请在 LaunchOS 中关闭它的快捷键或退出 LaunchOS，之后即可用该快捷键打开 Launch。"
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
