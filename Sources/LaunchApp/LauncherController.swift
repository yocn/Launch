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
    private let openApplication: (URL) -> Bool

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
        model.prepareForPresentation()
        presenter.present()
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
        presenter.dismiss(restoringPreviousApp: reason.restoresPreviousApp)
    }

    func handleEscape() {
        if model.handleEscape() == .close {
            hide(.escape)
        }
    }

    func handleBackgroundClick() {
        if model.openFolderID != nil {
            model.closeFolder()
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
        case .endPageDrag(let predictedTranslation):
            model.endPageDrag(predictedTranslation: predictedTranslation)
        }
    }

    func launch(_ app: CatalogApp) {
        guard openApplication(URL(fileURLWithPath: app.identity.path)) else {
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
