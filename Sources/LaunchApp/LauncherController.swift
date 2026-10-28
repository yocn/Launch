import Foundation
import LaunchCore

enum LauncherHideReason: Equatable {
    case toggle
    case escape
    case backgroundClick
    case launchedApp
    case resignedActive

    var restoresPreviousApp: Bool {
        switch self {
        case .toggle, .escape, .backgroundClick:
            true
        case .launchedApp, .resignedActive:
            false
        }
    }
}

@MainActor
protocol LauncherPresenting: AnyObject {
    var isVisible: Bool { get }
    func present()
    func dismiss(restoringPreviousApp: Bool)
}

@MainActor
final class LauncherController {
    let model: LauncherModel
    private let presenter: LauncherPresenting
    private let iconCache: IconCache
    // 只发出启动请求，不等应用启动完成
    private let openApplication: (URL) -> Void
    var onUndoLayoutEdit: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onHide: (() -> Void)?
    var onOpenWebsite: ((URL) -> Void)?
    var onRunShortcut: ((UUID) -> Void)?
    // 设置窗口开着时关启动器不切回之前的应用，免得设置窗口被那个应用盖住
    var isSettingsOpen: () -> Bool = { false }
    // 快捷键等切换关闭启动器时，浮在它上面的设置窗口一起关
    var closeSettings: () -> Void = {}

    init(
        model: LauncherModel,
        presenter: LauncherPresenting,
        iconCache: IconCache,
        openApplication: @escaping (URL) -> Void
    ) {
        self.model = model
        self.presenter = presenter
        self.iconCache = iconCache
        self.openApplication = openApplication
    }

    func show() {
        guard !presenter.isVisible else {
            return
        }
        let start = ContinuousClock.now
        Task { await iconCache.reloadChanged() }
        model.prepareForPresentation()
        presenter.present()
        model.setPresented(true)
        let elapsed = ContinuousClock.now - start
        DebugLog.log("show() 合计 \(Int(elapsed / .milliseconds(1))) 毫秒")
        if elapsed > .milliseconds(300) {
            AppLog.shared.warning("唤起时主线程耗时 \(Int(elapsed / .milliseconds(1))) 毫秒")
        }
    }

    func toggle() {
        if presenter.isVisible {
            closeSettings()
            hide(.toggle)
        } else {
            show()
        }
    }

    func hide(_ reason: LauncherHideReason) {
        guard presenter.isVisible else {
            return
        }
        model.setPresented(false)
        presenter.dismiss(restoringPreviousApp: reason.restoresPreviousApp && !isSettingsOpen())
        onHide?()
    }

    func handleEscape() {
        if model.handleEscape() == .close {
            hide(.escape)
        }
    }

    func handleBackgroundClick() {
        DebugLog.log("handleBackgroundClick modified=\(model.isModifiedClick) folder=\(model.openFolderID ?? "-") multi=\(model.multiSelection.isEmpty) jiggle=\(model.isJiggling)")
        guard !model.isModifiedClick else {
            return
        }
        if model.openFolderID != nil {
            model.closeFolder()
        } else if !model.multiSelection.isEmpty {
            model.clearMultiSelection()
        } else if model.isJiggling {
            model.endJiggling()
        } else {
            hide(.backgroundClick)
        }
    }

    func handle(_ command: LauncherCommand) {
        guard presenter.isVisible else {
            return
        }
        switch command {
        case .move(let direction):
            model.moveSelection(direction)
        case .activate:
            if let app = model.activateSelection() {
                launch(app)
            }
        case .nextPage:
            model.turnPage(.next)
        case .previousPage:
            model.turnPage(.previous)
        case .dragPage(let translation):
            model.dragPage(by: translation)
        case .endPageDrag(let predictedTranslation, let velocity):
            model.endPageDrag(predictedTranslation: predictedTranslation, velocity: velocity)
        case .undoLayoutEdit:
            onUndoLayoutEdit?()
        case .openSettings:
            onOpenSettings?()
        case .selectAll:
            model.selectAllOnPage()
        }
    }

    func launch(_ item: LaunchItem) {
        guard !model.isJiggling, item.isAvailable else {
            return
        }
        switch item.target {
        case .application(let application):
            openApplication(URL(fileURLWithPath: application.identity.path))
        case .website(let url):
            guard let onOpenWebsite else { return }
            onOpenWebsite(url)
        case .shortcut(let id):
            guard let onRunShortcut else { return }
            onRunShortcut(id)
        }
        hide(.launchedApp)
    }

    func updateCatalog(_ items: [LaunchItem]) {
        Task { await iconCache.reloadChanged() }
        guard items != model.catalog else {
            return
        }
        // 网址、快捷指令的增改不影响应用图标，清缓存会让全部应用图标闪成占位
        if items.compactMap(\.application) != model.catalog.compactMap(\.application) {
            iconCache.removeAll()
        }
        model.updateCatalog(items)
    }
}
