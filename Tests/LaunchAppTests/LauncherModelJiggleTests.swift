import CoreGraphics
import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelJiggleTests: XCTestCase {
    private let layout = LauncherHomeLayout(
        screenSize: LauncherHomeLayout.canvasSize,
        referenceSize: LauncherHomeLayout.canvasSize
    )

    private var gridFrame: CGRect {
        CGRect(x: 0, y: 135, width: layout.contentSize.width, height: layout.gridHeight)
    }

    private func tile(_ index: Int) -> CGRect {
        GridHitTester(layout: layout, frame: gridFrame).tileRect(index)
    }

    @MainActor
    private func makeModel(apps: [LaunchItem], pages: [[ResolvedItem]]) -> LauncherModel {
        let model = LauncherModel(apps: apps)
        model.updateLayout(pages)
        model.canEditLayout = true
        model.updateHomeLayout(layout)
        model.updateGridFrame(gridFrame)
        return model
    }

    @MainActor
    func testJigglingNeedsEditableLayoutWithoutSearch() {
        let apps = makeLaunchItems(count: 3)
        let model = makeModel(apps: apps, pages: [apps.map(ResolvedItem.item)])

        model.canEditLayout = false
        model.beginJiggling()
        XCTAssertFalse(model.isJiggling)

        model.canEditLayout = true
        model.setQuery("App")
        model.beginJiggling()
        XCTAssertFalse(model.isJiggling)

        model.setQuery("")
        model.beginJiggling()
        XCTAssertTrue(model.isJiggling)
    }

    @MainActor
    func testEscapeClosesFolderThenStopsJigglingThenCloses() {
        let apps = makeLaunchItems(count: 3)
        let model = makeModel(apps: apps, pages: [[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.showFolder(id: "f")
        model.beginJiggling()

        XCTAssertEqual(model.handleEscape(), .closedFolder)
        XCTAssertTrue(model.isJiggling)
        XCTAssertEqual(model.handleEscape(), .stoppedJiggling)
        XCTAssertFalse(model.isJiggling)
        XCTAssertEqual(model.handleEscape(), .close)
    }

    @MainActor
    func testTypingAndPresentingStopJiggling() {
        let apps = makeLaunchItems(count: 3)
        let model = makeModel(apps: apps, pages: [apps.map(ResolvedItem.item)])

        model.beginJiggling()
        model.setQuery("App")
        XCTAssertFalse(model.isJiggling)

        model.setQuery("")
        model.beginJiggling()
        model.prepareForPresentation()
        XCTAssertFalse(model.isJiggling)
    }

    @MainActor
    func testUninstallTargetOnlyOnBadgeOfUninstallableAppWhileJiggling() {
        let apps = makeLaunchItems(count: 3)
        let model = makeModel(apps: apps, pages: [apps.map(ResolvedItem.item)])
        model.canUninstall = { $0 == apps[1] }
        let badge = layout.uninstallBadgeFrame(inTile: tile(1))
        let badgeCenter = CGPoint(x: badge.midX, y: badge.midY)

        XCTAssertNil(model.uninstallTarget(at: badgeCenter))

        model.beginJiggling()
        XCTAssertEqual(model.uninstallTarget(at: badgeCenter), apps[1])
        let otherBadge = layout.uninstallBadgeFrame(inTile: tile(0))
        XCTAssertNil(model.uninstallTarget(at: CGPoint(x: otherBadge.midX, y: otherBadge.midY)))
        XCTAssertNil(model.uninstallTarget(at: CGPoint(x: tile(1).midX, y: tile(1).midY)))
    }
}
