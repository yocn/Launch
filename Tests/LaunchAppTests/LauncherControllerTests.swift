import AppKit
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
private final class FakePresenter: LauncherPresenting {
    private(set) var isVisible = false
    private(set) var presentCount = 0
    private(set) var dismissals: [Bool] = []

    func present() {
        isVisible = true
        presentCount += 1
    }

    func dismiss(restoringPreviousApp: Bool) {
        isVisible = false
        dismissals.append(restoringPreviousApp)
    }
}

final class LauncherControllerTests: XCTestCase {
    @MainActor
    func testToggleShowsThenHidesRestoringPreviousApp() {
        let (controller, presenter) = makeController()

        controller.toggle()
        controller.toggle()

        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertEqual(presenter.dismissals, [true])
    }

    @MainActor
    func testShowClearsQueryAndIgnoresRepeatWhileVisible() {
        let (controller, presenter) = makeController()
        controller.model.setQuery("App")

        controller.show()
        XCTAssertEqual(controller.model.query, "")

        controller.model.setQuery("Ap")
        controller.show()

        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertEqual(controller.model.query, "Ap")
    }

    @MainActor
    func testEscapeClearsQueryBeforeHiding() {
        let (controller, presenter) = makeController()
        controller.show()
        controller.model.setQuery("App")

        controller.handleEscape()
        XCTAssertTrue(presenter.isVisible)

        controller.handleEscape()
        XCTAssertEqual(presenter.dismissals, [true])
    }

    func testHideReasonsDecideFocusRestoration() {
        let reasons: [LauncherHideReason] = [
            .toggle, .escape, .backgroundClick, .launchedApp, .resignedActive,
        ]

        XCTAssertEqual(
            reasons.map(\.restoresPreviousApp),
            [true, true, true, false, false]
        )
    }

    @MainActor
    func testHideWhenNotVisibleDoesNothing() {
        let (controller, presenter) = makeController()

        controller.hide(.resignedActive)

        XCTAssertEqual(presenter.dismissals, [])
    }

    @MainActor
    func testSuccessfulLaunchHidesWithoutRestoringPreviousApp() {
        var openedPaths: [String] = []
        let (controller, presenter) = makeController { url in
            openedPaths.append(url.path)
            return true
        }
        let app = makeApps(count: 1)[0]
        controller.show()

        controller.launch(app)

        XCTAssertEqual(openedPaths, [app.identity.path])
        XCTAssertEqual(presenter.dismissals, [false])
    }

    @MainActor
    func testFailedLaunchKeepsLauncherVisible() {
        let (controller, presenter) = makeController { _ in false }
        controller.show()

        controller.launch(makeApps(count: 1)[0])

        XCTAssertTrue(presenter.isVisible)
        XCTAssertEqual(presenter.dismissals, [])
    }

    @MainActor
    func testUpdateCatalogKeepsIconsWhenAppsAreUnchanged() {
        var loads = 0
        let iconCache = IconCache { _ in
            loads += 1
            return NSImage()
        }
        let apps = makeApps(count: 2)
        let (controller, _) = makeController(apps: apps, iconCache: iconCache)
        _ = iconCache.icon(for: apps[0].identity.path)

        controller.updateCatalog(apps)
        _ = iconCache.icon(for: apps[0].identity.path)
        XCTAssertEqual(loads, 1)

        controller.updateCatalog(makeApps(count: 3))
        _ = iconCache.icon(for: apps[0].identity.path)
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(controller.model.apps.count, 3)
    }

    @MainActor
    func testBackgroundClickClosesOpenFolderBeforeLauncher() {
        let apps = makeApps(count: 1)
        let (controller, presenter) = makeController(apps: apps)
        controller.model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])
        controller.show()
        controller.model.showFolder(id: "f")

        controller.handleBackgroundClick()
        XCTAssertTrue(presenter.isVisible)
        XCTAssertNil(controller.model.openFolderID)

        controller.handleBackgroundClick()
        XCTAssertEqual(presenter.dismissals, [true])
    }

    @MainActor
    func testEscapeClosesFolderBeforeHiding() {
        let apps = makeApps(count: 1)
        let (controller, presenter) = makeController(apps: apps)
        controller.model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])
        controller.show()
        controller.model.showFolder(id: "f")

        controller.handleEscape()
        XCTAssertTrue(presenter.isVisible)

        controller.handleEscape()
        XCTAssertEqual(presenter.dismissals, [true])
    }

    @MainActor
    func testActivateCommandLaunchesSelectedApp() {
        var openedPaths: [String] = []
        let apps = makeApps(count: 2)
        let (controller, presenter) = makeController(apps: apps) { url in
            openedPaths.append(url.path)
            return true
        }
        controller.show()
        controller.model.setQuery("App 1")

        controller.handle(.activate)

        XCTAssertEqual(openedPaths, [apps[1].identity.path])
        XCTAssertEqual(presenter.dismissals, [false])
    }

    @MainActor
    func testCommandsAreIgnoredWhileHidden() {
        let (controller, _) = makeController(apps: makeApps(count: 2))

        controller.handle(.move(.right))

        XCTAssertNil(controller.model.selectedIndex)
    }

    @MainActor
    func testPageCommandsTurnPages() {
        let (controller, _) = makeController(apps: makeApps(count: 40))
        controller.show()

        controller.handle(.nextPage)
        XCTAssertEqual(controller.model.currentPage, 1)
        controller.handle(.previousPage)
        XCTAssertEqual(controller.model.currentPage, 0)
    }

    @MainActor
    func testDragCommandsFollowAndTurnPages() {
        let (controller, _) = makeController(apps: makeApps(count: 40))
        controller.show()
        controller.model.updatePageWidth(1000)

        controller.handle(.dragPage(-500))
        XCTAssertEqual(controller.model.pageDragOffset, -500)
        controller.handle(.endPageDrag(predictedTranslation: -500, velocity: 0))

        XCTAssertEqual(controller.model.currentPage, 1)
    }

    @MainActor
    private func makeController(
        apps: [CatalogApp] = [],
        iconCache: IconCache = IconCache { _ in NSImage() },
        openApplication: @escaping (URL) -> Bool = { _ in true }
    ) -> (LauncherController, FakePresenter) {
        let presenter = FakePresenter()
        let controller = LauncherController(
            model: LauncherModel(apps: apps),
            presenter: presenter,
            iconCache: iconCache,
            openApplication: openApplication
        )
        return (controller, presenter)
    }
}
