import AppKit
import LaunchCore
import SwiftUI
import UniformTypeIdentifiers

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
        openApplication: { LaunchAppDelegate.openApplication(at: $0) }
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
    private lazy var hotCornerMonitor = HotCornerMonitor { [weak self] in
        self?.controller.toggle()
    }
    private lazy var inputTap = SystemInputTap { [weak self] in
        self?.controller.toggle()
    }
    private let appActions = AppActions()
    private let settings = LauncherSettings()
    private let wallpaperProvider = WallpaperProvider()
    private var appliedSortField: SortField?
    private var optionHold = OptionHoldTracker()
    private var watchedSourcePaths: [String]?
    private var catalogGeneration = 0
    private var isJigglingFromOption = false
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        isLauncherVisible: { [weak self] in self?.presenter.isVisible ?? false },
        makeContent: { [unowned self] in
            AnyView(SettingsView(
                settings: settings,
                model: controller.model,
                loginItemService: loginItemService,
                hasHotKeyConflict: { [weak self] in self?.hasHotKeyConflict() ?? false },
                onUnhide: { [weak self] app in self?.layoutCoordinator.unhide(app) },
                onUnhideAll: { [weak self] in self?.layoutCoordinator.unhideAll() },
                data: DataSettingsActions(
                    exportLayout: { [weak self] in self?.exportLayout() },
                    exportDiagnostics: { [weak self] in await self?.exportDiagnostics() },
                    importLayout: { [weak self] in self?.importLayout() },
                    canImportLaunchpad: { [weak self] in self?.layoutCoordinator.canImport ?? false },
                    importLaunchpad: { [weak self] in
                        Task { await self?.layoutCoordinator.importFromLaunchpad() }
                    },
                    canRestore: { [weak self] in self?.layoutCoordinator.canRestore ?? false },
                    restoreLayout: { [weak self] in self?.layoutCoordinator.restoreBackup() }
                )
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
        AppLog.shared.info("启动 Launch \(Self.appVersion)，\(ProcessInfo.processInfo.operatingSystemVersionString)")
        presenter.setContent(
            LauncherView(
                model: controller.model,
                settings: settings,
                onEscape: { [weak self] in self?.controller.handleEscape() },
                onBackgroundClick: { [weak self] in self?.controller.handleBackgroundClick() },
                onLaunch: { [weak self] app in self?.controller.launch(app) },
                // 在 SwiftUI 按钮动作里同步弹菜单时，从菜单首次打开的设置窗口开关圆钮画不出来，等按钮动作结束再弹
                onMainMenu: { [weak self] in
                    DispatchQueue.main.async { self?.itemDragController.showMainMenu() }
                }
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
            self?.settingsWindow.launcherDidHide()
        }
        controller.isSettingsOpen = { [weak self] in self?.settingsWindow.isOpen ?? false }
        presenter.onPresent = { [weak self] screen in
            guard let self else {
                return
            }
            let wallpaper = settings.background == .glass
                ? nil
                : wallpaperProvider.wallpaper(for: screen, blurred: settings.background == .blurredWallpaper)
            controller.model.updateWallpaper(wallpaper)
            optionHold.reset(optionDown: NSEvent.modifierFlags.contains(.option))
            isJigglingFromOption = false
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
            passesScrollWheel: { [weak self] in
                guard let model = self?.controller.model else {
                    return false
                }
                return model.browsingStyle == .scroll && model.openFolder == nil
            },
            onCommand: { [weak self] command in self?.controller.handle(command) },
            onModifiersChanged: { [weak self] flags in self?.handleModifiers(flags) }
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
        startCatalogWatcher()
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

    // 同步的 NSWorkspace.open 会等目标应用启动完成才返回，启动慢的应用（QQ 约 30 秒）会把启动器卡住
    private static func openApplication(at url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else {
                return
            }
            let message = error.localizedDescription
            Task { @MainActor in
                AppLog.shared.error("启动应用失败：\(url.path)，\(message)")
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "无法打开「\(url.deletingPathExtension().lastPathComponent)」"
                alert.informativeText = message
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
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
        case .browsingStyle(let style):
            settings.browsingStyle = style
        case .displayMode(let mode):
            settings.displayMode = mode
        default:
            controller.model.performMenuCommand(command)
        }
    }

    // 按住 Option 进入抖动，松开只结束由 Option 开始的抖动
    private func handleModifiers(_ flags: NSEvent.ModifierFlags) {
        let model = controller.model
        switch optionHold.update(flags) {
        case .began:
            guard settings.optionEntersUninstallMode, !model.isJiggling, model.canDragItems else {
                return
            }
            model.beginJiggling()
            isJigglingFromOption = true
        case .ended:
            if isJigglingFromOption {
                isJigglingFromOption = false
                model.endJiggling()
            }
        case nil:
            break
        }
    }

    // 来源目录变化时换一个新的监听器，旧监听器迟到的扫描结果丢掉
    private func startCatalogWatcher() {
        catalogGeneration += 1
        let generation = catalogGeneration
        watchedSourcePaths = settings.customSourcePaths
        let watcher = CatalogWatcher(
            roots: ApplicationSources.roots(custom: settings.customSourcePaths),
            scan: { roots in
                let start = Date()
                let apps = (try? AppCatalog().scan(roots: roots)) ?? []
                AppLog.shared.info(String(format: "扫描 %d 个目录，找到 %d 个应用，耗时 %.0f 毫秒", roots.count, apps.count, Date().timeIntervalSince(start) * 1000))
                return apps
            }
        ) { [weak self] apps in
            guard let self, generation == catalogGeneration else {
                return
            }
            controller.updateCatalog(apps)
            refreshAppDates()
            Task { await self.layoutCoordinator.catalogDidChange(apps) }
        }
        watcher.start()
        catalogWatcher = watcher
    }

    private func refreshAppDates() {
        guard settings.sortField == .dateAdded || settings.sortField == .lastUsed else {
            return
        }
        AppDatesProvider.load(controller.model.apps) { [weak self] dates in
            self?.controller.model.updateAppDates(dates)
        }
    }

    private func exportLayout() -> String? {
        let data: Data
        do {
            data = try layoutCoordinator.exportBackup()
        } catch {
            _ = NSAlert(error: error).runAboveLauncher()
            return nil
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Launch 布局 \(Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())).json"
        guard panel.runAboveLauncher() == .OK, let url = panel.url else {
            return nil
        }
        do {
            try data.write(to: url, options: .atomic)
            return "已导出到 \((url.path as NSString).abbreviatingWithTildeInPath)"
        } catch {
            _ = NSAlert(error: error).runAboveLauncher()
            return nil
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?")（\(info?["CFBundleVersion"] as? String ?? "?")）"
    }

    // 收集与打包放到后台，保存对话框仍在主线程
    private func exportDiagnostics() async -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Launch 诊断 \(Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())).zip"
        guard panel.runAboveLauncher() == .OK, let url = panel.url else {
            return nil
        }
        AppLog.shared.flush()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let layout = LayoutCoordinator.defaultLayoutURL
        let sources = DiagnosticsSources(
            logFiles: [AppLog.shared.fileURL, AppLog.shared.rotatedURL],
            crashReportsDirectory: home.appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory),
            layoutFiles: [layout, layout.appendingPathExtension("backup")],
            settings: UserDefaults.standard.persistentDomain(forName: "dev.yocn.launch").flatMap {
                try? PropertyListSerialization.data(fromPropertyList: $0, format: .xml, options: 0)
            },
            systemInfo: systemInfo()
        )
        do {
            try await Task.detached(priority: .userInitiated) {
                try DiagnosticsExporter.export(sources, to: url)
            }.value
            return "已导出到 \((url.path as NSString).abbreviatingWithTildeInPath)"
        } catch {
            AppLog.shared.error("导出诊断信息失败：\(error.localizedDescription)")
            _ = NSAlert(error: error).runAboveLauncher()
            return nil
        }
    }

    private func systemInfo() -> String {
        let screens = NSScreen.screens.map { screen in
            "  \(screen.localizedName)：\(Int(screen.frame.width))×\(Int(screen.frame.height)) @\(screen.backingScaleFactor)x，位置 \(Int(screen.frame.minX)),\(Int(screen.frame.minY))"
        }
        return ([
            "Launch \(Self.appVersion)",
            ProcessInfo.processInfo.operatingSystemVersionString,
            "应用数：\(controller.model.apps.count)，隐藏：\(controller.model.hiddenApps.count)",
            "来源目录：\(ApplicationSources.roots(custom: settings.customSourcePaths).map(\.path).joined(separator: "、"))",
            "网格：\(settings.grid.columns)×\(settings.grid.rows)，排序：\(settings.sortField.rawValue)，背景：\(settings.background.rawValue)",
            "屏幕：",
        ] + screens).joined(separator: "\n") + "\n"
    }

    private func importLayout() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runAboveLauncher() == .OK, let url = panel.url else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            _ = NSAlert(error: error).runAboveLauncher()
            return nil
        }
        return layoutCoordinator.importBackup(data).map {
            "已导入：\($0.pageCount) 页、\($0.folderCount) 个文件夹、\($0.appCount) 个应用"
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
        var sourcePaths: [String] = []
        withObservationTracking {
            sourcePaths = settings.customSourcePaths
            controller.model.returnToFirstPageDelay = settings.returnToFirstPage.delay
            presenter.screenChoice = settings.screenChoice
            controller.model.showsHiddenAppsInSearch = settings.showsHiddenAppsInSearch
            controller.model.updateGrid(settings.grid)
            layoutCoordinator.updatePageCapacity(settings.grid.capacity)
            controller.model.updateDisplaySort(settings.displaySort)
            controller.model.updateBrowsingStyle(settings.browsingStyle)
            controller.model.updateDisplayMode(settings.displayMode)
            hotCornerMonitor.corner = settings.hotCorner
            inputTap.f4Enabled = settings.f4Launches
            inputTap.pinch = settings.pinchGesture
            statusItemController?.setIconVisible(settings.showsMenuBarIcon)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySettings()
            }
        }
        if catalogWatcher != nil, sourcePaths != watchedSourcePaths {
            startCatalogWatcher()
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
