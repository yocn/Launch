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
    func testToggleOffClosesSettingsTooAndRestoresPreviousApp() {
        let (controller, presenter) = makeController()
        var settingsOpen = true
        controller.isSettingsOpen = { settingsOpen }
        controller.closeSettings = { settingsOpen = false }
        controller.show()

        controller.toggle()

        XCTAssertFalse(settingsOpen)
        XCTAssertEqual(presenter.dismissals, [true])
    }

    @MainActor
    func testHideKeepsAppActiveWhileSettingsOpen() {
        let (controller, presenter) = makeController()
        controller.isSettingsOpen = { true }
        controller.show()

        controller.hide(.escape)

        XCTAssertEqual(presenter.dismissals, [false])
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
        }
        let app = makeLaunchItems(count: 1)[0]
        controller.show()

        controller.launch(app)

        XCTAssertEqual(openedPaths, [app.application!.identity.path])
        XCTAssertEqual(presenter.dismissals, [false])
    }

    // 启动是异步的：慢应用（如 QQ 约 30 秒）不能拖住启动器
    @MainActor
    func testLaunchHidesWithoutWaitingForTheApp() {
        var pending: [URL] = []
        let (controller, presenter) = makeController { pending.append($0) }
        controller.show()

        controller.launch(makeLaunchItems(count: 1)[0])

        XCTAssertEqual(pending.count, 1)
        XCTAssertFalse(presenter.isVisible)
        XCTAssertEqual(presenter.dismissals, [false])
    }

    @MainActor
    func testUpdateCatalogKeepsIconsWhenAppsAreUnchanged() {
        var loads = 0
        let iconCache = IconCache { _, _ in
            loads += 1
        }
        let apps = makeLaunchItems(count: 2)
        let (controller, _) = makeController(apps: apps, iconCache: iconCache)
        _ = iconCache.icon(for: apps[0].application!.identity.path)

        controller.updateCatalog(apps)
        _ = iconCache.icon(for: apps[0].application!.identity.path)
        XCTAssertEqual(loads, 1)

        controller.updateCatalog(makeLaunchItems(count: 3))
        _ = iconCache.icon(for: apps[0].application!.identity.path)
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(controller.model.apps.count, 3)
    }

    @MainActor
    func testExtraItemChangesDoNotReloadApplicationIcons() {
        var loads = 0
        let iconCache = IconCache { _, _ in
            loads += 1
        }
        let apps = makeLaunchItems(count: 2)
        let (controller, _) = makeController(apps: apps, iconCache: iconCache)
        _ = iconCache.icon(for: apps[0].application!.identity.path)

        let website = ExtraItemDefinition(name: "文档", target: .website(URL(string: "https://example.com")!))
        controller.updateCatalog(apps + [LaunchItem(definition: website)])
        var renamed = website
        renamed.name = "项目文档"
        controller.updateCatalog(apps + [LaunchItem(definition: renamed)])
        _ = iconCache.icon(for: apps[0].application!.identity.path)

        XCTAssertEqual(loads, 1)
        XCTAssertEqual(controller.model.apps.last?.displayName, "项目文档")
    }

    @MainActor
    func testBackgroundClickClosesOpenFolderBeforeLauncher() {
        let apps = makeLaunchItems(count: 1)
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
        let apps = makeLaunchItems(count: 1)
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
        let apps = makeLaunchItems(count: 2)
        let (controller, presenter) = makeController(apps: apps) { url in
            openedPaths.append(url.path)
        }
        controller.show()
        controller.model.setQuery("App 1")

        controller.handle(.activate)

        XCTAssertEqual(openedPaths, [apps[1].application!.identity.path])
        XCTAssertEqual(presenter.dismissals, [false])
    }

    @MainActor
    func testCommandsAreIgnoredWhileHidden() {
        let (controller, _) = makeController(apps: makeLaunchItems(count: 2))

        controller.handle(.move(.right))

        XCTAssertNil(controller.model.selectedIndex)
    }

    @MainActor
    func testPageCommandsTurnPages() {
        let (controller, _) = makeController(apps: makeLaunchItems(count: 40))
        controller.show()

        controller.handle(.nextPage)
        XCTAssertEqual(controller.model.currentPage, 1)
        controller.handle(.previousPage)
        XCTAssertEqual(controller.model.currentPage, 0)
    }

    @MainActor
    func testDragCommandsFollowAndTurnPages() {
        let (controller, _) = makeController(apps: makeLaunchItems(count: 40))
        controller.show()
        controller.model.updatePageWidth(1000)

        controller.handle(.dragPage(-500))
        XCTAssertEqual(controller.model.pageDragOffset, -500)
        controller.handle(.endPageDrag(predictedTranslation: -500, velocity: 0))

        XCTAssertEqual(controller.model.currentPage, 1)
    }

    @MainActor
    func testUndoCommandForwardsToHandler() {
        let (controller, _) = makeController(apps: makeLaunchItems(count: 3))
        controller.show()
        var undos = 0
        controller.onUndoLayoutEdit = { undos += 1 }

        controller.handle(.undoLayoutEdit)

        XCTAssertEqual(undos, 1)
    }

    @MainActor
    func testBackgroundClickStopsJigglingBeforeClosing() {
        let apps = makeLaunchItems(count: 3)
        let (controller, presenter) = makeController(apps: apps)
        controller.show()
        controller.model.updateLayout([apps.map(ResolvedItem.item)])
        controller.model.canEditLayout = true
        controller.model.beginJiggling()

        controller.handleBackgroundClick()
        XCTAssertFalse(controller.model.isJiggling)
        XCTAssertTrue(presenter.isVisible)

        controller.handleBackgroundClick()
        XCTAssertFalse(presenter.isVisible)
    }

    @MainActor
    func testLaunchIsIgnoredWhileJiggling() {
        let apps = makeLaunchItems(count: 3)
        var opened: [URL] = []
        let (controller, presenter) = makeController(apps: apps, openApplication: { url in
            opened.append(url)
        })
        controller.show()
        controller.model.updateLayout([apps.map(ResolvedItem.item)])
        controller.model.canEditLayout = true
        controller.model.beginJiggling()

        controller.launch(apps[0])

        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(presenter.isVisible)
    }

    @MainActor
    func testBackgroundClickClearsSelectionBeforeJigglingAndClosing() {
        let apps = makeLaunchItems(count: 3)
        let (controller, presenter) = makeController(apps: apps)
        controller.show()
        controller.model.updateLayout([apps.map(ResolvedItem.item)])
        controller.model.canEditLayout = true
        controller.model.beginJiggling()
        controller.model.toggleMultiSelection(.item(apps[1].identity.stableKey))

        controller.handleBackgroundClick()
        XCTAssertTrue(controller.model.multiSelection.isEmpty)
        XCTAssertTrue(controller.model.isJiggling)

        controller.handleBackgroundClick()
        XCTAssertFalse(controller.model.isJiggling)
        XCTAssertTrue(presenter.isVisible)

        controller.handleBackgroundClick()
        XCTAssertFalse(presenter.isVisible)
    }

    @MainActor
    func testModifiedBackgroundClickIsIgnored() {
        let (controller, presenter) = makeController()
        controller.show()
        controller.model.isModifiedClick = true

        controller.handleBackgroundClick()

        XCTAssertTrue(presenter.isVisible)
    }

    @MainActor
    func testReturnOnlyClearsSelection() {
        let apps = makeLaunchItems(count: 3)
        var opened: [URL] = []
        let (controller, _) = makeController(apps: apps) { url in
            opened.append(url)
        }
        controller.show()
        controller.model.updateLayout([apps.map(ResolvedItem.item)])
        controller.model.canEditLayout = true
        controller.handle(.move(.right))
        controller.model.toggleMultiSelection(.item(apps[2].identity.stableKey))

        controller.handle(.activate)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(controller.model.multiSelection.isEmpty)

        controller.handle(.activate)
        XCTAssertEqual(opened.count, 1)
    }

    @MainActor
    func testOpenSettingsCommandIsForwarded() {
        let (controller, _) = makeController()
        var opened = 0
        controller.onOpenSettings = { opened += 1 }
        controller.show()

        controller.handle(.openSettings)

        XCTAssertEqual(opened, 1)
    }

    @MainActor
    func testPresentedStateFollowsShowAndHide() {
        let (controller, presenter) = makeController()
        XCTAssertFalse(controller.model.isPresented)

        controller.show()
        XCTAssertTrue(controller.model.isPresented)

        controller.hide(.escape)
        XCTAssertFalse(controller.model.isPresented)

        controller.show()
        XCTAssertTrue(controller.model.isPresented)
        XCTAssertEqual(presenter.presentCount, 2)
    }

    @MainActor
    private func makeController(
        apps: [LaunchItem] = [],
        iconCache: IconCache = IconCache { _, _ in },
        openApplication: @escaping (URL) -> Void = { _ in }
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
