import AppKit
import XCTest
@testable import LaunchApp

final class StatusItemClickTests: XCTestCase {
    func testLeftClickOpensLauncher() {
        XCTAssertEqual(StatusItemClick(type: .leftMouseUp, modifiers: []), .open)
    }

    func testRightClickShowsMenu() {
        XCTAssertEqual(StatusItemClick(type: .rightMouseUp, modifiers: []), .menu)
    }

    func testControlClickShowsMenu() {
        XCTAssertEqual(StatusItemClick(type: .leftMouseUp, modifiers: [.control]), .menu)
    }

    func testAccessibilityPressOpensLauncher() {
        XCTAssertEqual(StatusItemClick(type: nil, modifiers: []), .open)
    }
}
