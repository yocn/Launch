import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelTests: XCTestCase {
    @MainActor
    func testSetQueryResetsPage() {
        let model = LauncherModel(apps: makeApps(count: 40))
        model.selectPage(1)

        model.setQuery("App 1")

        XCTAssertEqual(model.currentPage, 0)
    }

    @MainActor
    func testSelectPageClampsToAvailablePages() {
        let model = LauncherModel(apps: makeApps(count: 40))

        model.selectPage(5)

        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.visibleItems.count, 5)
    }

    @MainActor
    func testPrepareForPresentationClearsQueryAndCountsPresentation() {
        let model = LauncherModel(apps: makeApps(count: 3))
        model.setQuery("App")

        model.prepareForPresentation()

        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.presentationCount, 1)
    }

    @MainActor
    func testPrepareForPresentationKeepsBrowsingPage() {
        let model = LauncherModel(apps: makeApps(count: 40))
        model.selectPage(1)

        model.prepareForPresentation()

        XCTAssertEqual(model.currentPage, 1)
    }

    @MainActor
    func testEscapeClearsQueryBeforeClosing() {
        let model = LauncherModel(apps: makeApps(count: 3))
        model.setQuery("App")

        XCTAssertEqual(model.handleEscape(), .clearedQuery)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.handleEscape(), .close)
    }

    @MainActor
    func testUpdateAppsClampsPage() {
        let model = LauncherModel(apps: makeApps(count: 40))
        model.selectPage(1)

        model.updateApps(makeApps(count: 10))

        XCTAssertEqual(model.currentPage, 0)
        XCTAssertEqual(model.visibleItems.count, 10)
    }

    @MainActor
    func testLayoutPagesDriveBrowsing() {
        let apps = makeApps(count: 2)
        let model = LauncherModel(apps: apps)

        model.updateLayout([[.app(apps[1])], [.app(apps[0])]])

        XCTAssertEqual(model.pages.count, 2)
        XCTAssertEqual(model.visibleItems, [.app(apps[1])])
    }

    @MainActor
    func testSearchFindsAppsInsideFolders() {
        let apps = makeApps(count: 2)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: [apps[1]])]])

        model.setQuery("App 1")

        XCTAssertEqual(model.visibleItems, [.app(apps[1])])
    }

    @MainActor
    func testOpenFolderResolvesFromLayout() {
        let apps = makeApps(count: 1)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])

        model.showFolder(id: "f")

        XCTAssertEqual(model.openFolder?.name, "效率")
    }

    @MainActor
    func testEscapeClosesFolderThenQueryThenLauncher() {
        let apps = makeApps(count: 1)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.showFolder(id: "f")

        XCTAssertEqual(model.handleEscape(), .closedFolder)
        XCTAssertNil(model.openFolderID)
        model.setQuery("App")
        XCTAssertEqual(model.handleEscape(), .clearedQuery)
        XCTAssertEqual(model.handleEscape(), .close)
    }

    @MainActor
    func testTypingPresentingAndPagingCloseFolder() {
        let apps = makeApps(count: 1)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])

        model.showFolder(id: "f")
        model.setQuery("A")
        XCTAssertNil(model.openFolderID)

        model.setQuery("")
        model.showFolder(id: "f")
        model.prepareForPresentation()
        XCTAssertNil(model.openFolderID)

        model.showFolder(id: "f")
        model.selectPage(0)
        XCTAssertNil(model.openFolderID)
    }

    @MainActor
    func testUpdateLayoutDropsVanishedFolder() {
        let apps = makeApps(count: 1)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.showFolder(id: "f")

        model.updateLayout([[.app(apps[0])]])

        XCTAssertNil(model.openFolderID)
    }
}
