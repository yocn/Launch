import Foundation
import XCTest
@testable import LaunchApp

final class LoginItemAvailabilityTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    func testAvailableInSystemApplications() {
        XCTAssertTrue(isAvailable(path: "/Applications/Launch.app"))
    }

    func testAvailableInUserApplications() {
        XCTAssertTrue(isAvailable(path: "/Users/tester/Applications/Launch.app"))
    }

    func testUnavailableInBuildDirectory() {
        XCTAssertFalse(isAvailable(path: "/Users/tester/launch/.build/Launch.app"))
    }

    func testUnavailableInNestedFolder() {
        XCTAssertFalse(isAvailable(path: "/Applications/Tools/Launch.app"))
    }

    func testUnavailableWithoutBundleIdentifier() {
        XCTAssertFalse(
            LoginItemAvailability.isAvailable(
                bundleIdentifier: nil,
                bundleURL: URL(fileURLWithPath: "/Applications/Launch.app"),
                homeDirectory: home
            )
        )
    }

    private func isAvailable(path: String) -> Bool {
        LoginItemAvailability.isAvailable(
            bundleIdentifier: "dev.yocn.launch",
            bundleURL: URL(fileURLWithPath: path),
            homeDirectory: home
        )
    }
}
