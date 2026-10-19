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

    func testLauncherPanelCanReceiveKeyboardInput() {
        XCTAssertFalse(
            LauncherPanelConfiguration.styleMask.contains(.nonactivatingPanel)
        )
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
