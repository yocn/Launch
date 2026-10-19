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
        XCTAssertEqual(model.visibleApps.count, 5)
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
        XCTAssertEqual(model.visibleApps.count, 10)
    }
}
