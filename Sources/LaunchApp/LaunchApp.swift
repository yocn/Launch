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
    private var statusItemController: StatusItemController?
    private var catalogWatcher: CatalogWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        presenter.setContent(
            LauncherView(
                model: controller.model,
                onEscape: { [weak self] in self?.controller.handleEscape() },
                onBackgroundClick: { [weak self] in self?.controller.hide(.backgroundClick) },
                onLaunch: { [weak self] app in self?.controller.launch(app) }
            )
        )
        presenter.onResignActive = { [weak self] in
            self?.controller.hide(.resignedActive)
        }
        HotKeyService.register { [weak self] in
            self?.controller.toggle()
        }
        statusItemController = StatusItemController(
            loginItemService: loginItemService,
            hasHotKeyConflict: { [weak self] in self?.hasHotKeyConflict() ?? false },
            onOpen: { [weak self] in self?.controller.show() }
        )
        let watcher = CatalogWatcher(roots: ApplicationSources.defaultRoots()) { [weak self] apps in
            self?.controller.updateCatalog(apps)
        }
        watcher.start()
        catalogWatcher = watcher
        warnIfHotKeyConflicts()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return false
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
