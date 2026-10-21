import CoreGraphics
import XCTest
@testable import LaunchApp

final class ScreenPresenterTests: XCTestCase {
    func testScreenSelectionChoosesScreenContainingPointer() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        ]

        XCTAssertEqual(
            ScreenSelectionPolicy.screenIndex(
                containing: CGPoint(x: 2000, y: 400),
                in: screens
            ),
            1
        )
    }

    func testScreenSelectionReturnsNilWhenPointerIsOutsideAllScreens() {
        XCTAssertNil(
            ScreenSelectionPolicy.screenIndex(
                containing: CGPoint(x: -1, y: -1),
                in: []
            )
        )
    }

    func testScreenChoiceFallsBackToPointerScreen() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1920, y: -98, width: 1920, height: 1080),
        ]
        let mouse = CGPoint(x: -500, y: 300)
        func pick(_ choice: LauncherScreenChoice, active: CGRect? = nil, dock: CGRect? = nil, mouse: CGPoint = mouse) -> Int {
            ScreenSelectionPolicy.screenIndex(for: choice, screens: screens, mouse: mouse, active: active, dock: dock)
        }

        XCTAssertEqual(pick(.mouse), 1)
        XCTAssertEqual(pick(.main), 0)
        XCTAssertEqual(pick(.active, active: screens[0]), 0)
        XCTAssertEqual(pick(.active), 1)
        XCTAssertEqual(pick(.dock, dock: CGRect(x: 300, y: 0, width: 900, height: 70)), 0)
        XCTAssertEqual(pick(.dock), 1)
        XCTAssertEqual(pick(.mouse, mouse: CGPoint(x: 99999, y: 0)), 0)
    }

    func testDockScreenIsTheOneInsetByDock() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1920, y: -98, width: 1920, height: 1080),
        ]

        XCTAssertEqual(ScreenSelectionPolicy.dockScreenIndex(frames: frames, visibleFrames: [
            CGRect(x: 0, y: 61, width: 1512, height: 888), frames[1],
        ]), 0)
        XCTAssertEqual(ScreenSelectionPolicy.dockScreenIndex(frames: frames, visibleFrames: [
            CGRect(x: 0, y: 0, width: 1512, height: 949), CGRect(x: -1850, y: -98, width: 1850, height: 1080),
        ]), 1)
        XCTAssertNil(ScreenSelectionPolicy.dockScreenIndex(frames: frames, visibleFrames: [
            CGRect(x: 0, y: 0, width: 1512, height: 949), frames[1],
        ]))
    }

    func testWindowServerRectConvertsToScreenCoordinates() {
        XCTAssertEqual(
            ScreenSelectionPolicy.screenRect(fromWindowServer: CGRect(x: 0, y: 900, width: 1512, height: 82), primaryHeight: 982),
            CGRect(x: 0, y: 0, width: 1512, height: 82)
        )
    }

    func testLauncherPanelCanReceiveKeyboardInput() {
        XCTAssertFalse(
            LauncherPanelConfiguration.styleMask.contains(.nonactivatingPanel)
        )
    }

    func testSearchPresentationShowsClearControlOnlyForQuery() {
        XCTAssertFalse(SearchPresentation.showsClearControl(for: ""))
        XCTAssertTrue(SearchPresentation.showsClearControl(for: "safari"))
    }

    func testSearchPresentationShowsMoreControlOnlyWithoutQuery() {
        XCTAssertTrue(SearchPresentation.showsMoreControl(for: ""))
        XCTAssertFalse(SearchPresentation.showsMoreControl(for: "safari"))
    }

    @MainActor
    func testLauncherPanelCanBecomeKeyWhenBorderless() {
        let panel = LauncherPanel(
            contentRect: .zero,
            styleMask: LauncherPanelConfiguration.styleMask,
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(panel.canBecomeKey)
    }
}
