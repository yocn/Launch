import AppKit
import LaunchCore

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
        prompter: AlertLayoutPrompter()
    )
    private var statusItemController: StatusItemController?
    private var catalogWatcher: CatalogWatcher?
    private let inputMonitor = LauncherInputMonitor()
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
        makeDragImage: { [weak self] item in self?.dragImage(for: item) }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        presenter.setContent(
            LauncherView(
                model: controller.model,
                onEscape: { [weak self] in self?.controller.handleEscape() },
                onBackgroundClick: { [weak self] in self?.controller.handleBackgroundClick() },
                onLaunch: { [weak self] app in self?.controller.launch(app) }
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
            controller.model.updateLayout(pages)
        }
        controller.model.onEdit = { [weak self] edit in
            self?.layoutCoordinator.apply(edit)
        }
        controller.onUndoLayoutEdit = { [weak self] in
            self?.layoutCoordinator.undo()
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
                restoreLayout: { [weak self] in self?.layoutCoordinator.restoreBackup() }
            ),
            hasHotKeyConflict: { [weak self] in self?.hasHotKeyConflict() ?? false },
            onOpen: { [weak self] in self?.controller.show() }
        )
        let watcher = CatalogWatcher(roots: ApplicationSources.defaultRoots()) { [weak self] apps in
            self?.controller.updateCatalog(apps)
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

    private func dragImage(for item: ResolvedItem) -> NSImage? {
        guard let layout = controller.model.homeLayout else {
            return nil
        }
        return DragCardRenderer.image(for: item, layout: layout, scale: presenter.backingScaleFactor)
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
