import Foundation
import XCTest
@testable import LaunchApp

final class ApplicationSourcesTests: XCTestCase {
    func testDefaultSourcesIncludeUserAndSystemApplicationRoots() {
        let roots = ApplicationSources.defaultRoots(
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )

        XCTAssertEqual(
            roots.map(\.path),
            [
                "/Applications",
                "/System/Applications",
                "/System/Library/CoreServices/Applications",
                "/Users/example/Applications",
            ]
        )
    }
}
