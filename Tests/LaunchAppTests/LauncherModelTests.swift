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

    @MainActor
    func testTypingSelectsFirstResultAndClearingDeselects() {
        let model = LauncherModel(apps: makeApps(count: 3))

        model.setQuery("App")
        XCTAssertEqual(model.selectedIndex, 0)
        model.setQuery("zzz")
        XCTAssertNil(model.selectedIndex)
        model.setQuery("")
        XCTAssertNil(model.selectedIndex)
    }

    @MainActor
    func testArrowsCrossToNextPage() {
        let model = LauncherModel(apps: makeApps(count: 40))

        model.moveSelection(.right)
        XCTAssertEqual(model.selectedIndex, 0)
        for _ in 0 ..< 35 {
            model.moveSelection(.right)
        }

        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.selectedIndex, 0)
    }

    @MainActor
    func testActivateReturnsSelectedSearchResult() {
        let apps = makeApps(count: 3)
        let model = LauncherModel(apps: apps)

        model.setQuery("App 1")

        XCTAssertEqual(model.activateSelection(), apps[1])
    }

    @MainActor
    func testActivatingFolderOpensItAndSelectsFirstMember() {
        let apps = makeApps(count: 2)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.moveSelection(.right)

        XCTAssertNil(model.activateSelection())
        XCTAssertEqual(model.openFolderID, "f")
        XCTAssertEqual(model.folderSelectedIndex, 0)
        XCTAssertEqual(model.activateSelection(), apps[0])
    }

    @MainActor
    func testEscapeFromFolderSelectsFolderTile() {
        let apps = makeApps(count: 2)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[.app(apps[0]), makeFolder(id: "f", name: "效率", apps: [apps[1]])]])
        model.showFolder(id: "f")

        XCTAssertEqual(model.handleEscape(), .closedFolder)
        XCTAssertEqual(model.selectedIndex, 1)
    }

    @MainActor
    func testLargeFolderPagesAndArrowsStayInsideFolder() {
        let apps = makeApps(count: 40)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "其他", apps: apps)]])
        model.showFolder(id: "f")

        XCTAssertEqual(model.folderPages.count, 2)
        model.turnPage(.next)
        XCTAssertEqual(model.folderPage, 1)
        XCTAssertEqual(model.visibleFolderApps.count, 5)
        model.moveSelection(.right)
        XCTAssertEqual(model.folderSelectedIndex, 0)
        XCTAssertEqual(model.activateSelection(), model.visibleFolderApps[0])
    }

    @MainActor
    func testPageTurnClearsSelection() {
        let model = LauncherModel(apps: makeApps(count: 40))
        model.moveSelection(.right)

        model.turnPage(.next)

        XCTAssertEqual(model.currentPage, 1)
        XCTAssertNil(model.selectedIndex)
    }

    @MainActor
    func testDragFollowsAndReleaseTurnsPage() {
        let model = LauncherModel(apps: makeApps(count: 40))
        model.updatePageWidth(1000)

        model.dragPage(by: -200)
        XCTAssertTrue(model.isPageDragging)
        XCTAssertEqual(model.pageDragOffset, -200)

        model.endPageDrag(predictedTranslation: -400)
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.pageDragOffset, 0)
        XCTAssertFalse(model.isPageDragging)
    }

    @MainActor
    func testShortDragSnapsBackAndFirstPageResists() {
        let model = LauncherModel(apps: makeApps(count: 40))
        model.updatePageWidth(1000)

        model.dragPage(by: 200)
        XCTAssertEqual(model.pageDragOffset, 60, accuracy: 0.001)
        model.endPageDrag(predictedTranslation: 900)
        XCTAssertEqual(model.currentPage, 0)

        model.dragPage(by: -100)
        model.endPageDrag(predictedTranslation: -150)
        XCTAssertEqual(model.currentPage, 0)
    }

    @MainActor
    func testDragInsideFolderTurnsFolderPage() {
        let apps = makeApps(count: 40)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "其他", apps: apps)]])
        model.showFolder(id: "f")
        model.updatePageWidth(1000)

        model.dragPage(by: -350)
        model.endPageDrag(predictedTranslation: -350)

        XCTAssertEqual(model.folderPage, 1)
        XCTAssertEqual(model.openFolderID, "f")
    }

    @MainActor
    func testShrinkingResultsClampsSelection() {
        let model = LauncherModel(apps: makeApps(count: 3))
        model.moveSelection(.right)
        model.moveSelection(.right)
        model.moveSelection(.right)

        model.updateApps(makeApps(count: 1))

        XCTAssertEqual(model.selectedIndex, 0)
    }
}
