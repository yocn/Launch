import CoreGraphics
import XCTest
@testable import LaunchApp

final class LauncherCoordinatesTests: XCTestCase {
    func testWindowPointFlipsToGlobal() {
        XCTAssertEqual(LauncherCoordinates.global(fromWindow: CGPoint(x: 10, y: 900), contentHeight: 982), CGPoint(x: 10, y: 82))
    }

    func testGlobalRectFlipsToWindow() {
        XCTAssertEqual(
            LauncherCoordinates.window(fromGlobal: CGRect(x: 10, y: 100, width: 50, height: 80), contentHeight: 982),
            CGRect(x: 10, y: 802, width: 50, height: 80)
        )
    }
}
