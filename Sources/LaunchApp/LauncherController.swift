import Foundation
import LaunchCore

enum LauncherHideReason: Equatable {
    case toggle
    case escape
    case backgroundClick
    case launchedApp
    case resignedActive
    case settings

    var restoresPreviousApp: Bool {
        switch self {
        case .toggle, .escape, .backgroundClick:
            true
        case .launchedApp, .resignedActive, .settings:
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
    private let openApplication: (URL) -> Bool
    var onUndoLayoutEdit: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onHide: (() -> Void)?

    init(
        model: LauncherModel,
        presenter: LauncherPresenting,
        iconCache: IconCache,
        openApplication: @escaping (URL) -> Bool
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
        model.prepareForPresentation()
        presenter.present()
        model.setPresented(true)
        let elapsed = ContinuousClock.now - start
        if elapsed > .milliseconds(300) {
            AppLog.shared.warning("唤起时主线程耗时 \(Int(elapsed / .milliseconds(1))) 毫秒")
        }
    }

    func toggle() {
        if presenter.isVisible {
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
        presenter.dismiss(restoringPreviousApp: reason.restoresPreviousApp)
        onHide?()
    }

    func handleEscape() {
        if model.handleEscape() == .close {
            hide(.escape)
        }
    }

    func handleBackgroundClick() {
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

    func launch(_ app: CatalogApp) {
        guard !model.isJiggling, openApplication(URL(fileURLWithPath: app.identity.path)) else {
            return
        }
        hide(.launchedApp)
    }

    func updateCatalog(_ apps: [CatalogApp]) {
        guard apps != model.apps else {
            return
        }
        iconCache.removeAll()
        model.updateApps(apps)
    }
}
