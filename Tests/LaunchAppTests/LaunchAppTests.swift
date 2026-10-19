import XCTest
@testable import LaunchApp

final class LaunchAppTests: XCTestCase {
    func testLauncherDefaultsToMouseScreenPlacement() {
        XCTAssertEqual(LauncherPlacement.defaultTarget, .mouseScreen)
    }
}
