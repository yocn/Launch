import Foundation
import XCTest
@testable import LaunchApp

final class ApplicationSourcesTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/example")

    func testDefaultSourcesIncludeUserAndSystemApplicationRoots() {
        let roots = ApplicationSources.defaultRoots(homeDirectory: home)

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

    func testRootsAppendCustomFoldersWithoutDuplicates() {
        let roots = ApplicationSources.roots(custom: ["/Volumes/Tools", "/Applications", "/Volumes/Tools/"], homeDirectory: home)

        XCTAssertEqual(roots.map(\.path).suffix(1), ["/Volumes/Tools"])
        XCTAssertEqual(roots.count, 5)
    }

    func testAddingSkipsKnownFoldersAndSubfolders() {
        let result = ApplicationSources.adding(
            [
                URL(fileURLWithPath: "/Volumes/Tools/"),
                URL(fileURLWithPath: "/Applications/Utilities"),
                URL(fileURLWithPath: "/Users/example/Applications"),
                URL(fileURLWithPath: "/Volumes/Tools/Sub"),
                URL(fileURLWithPath: "/Volumes/ToolsExtra"),
            ],
            to: ["/Opt/Apps"],
            homeDirectory: home
        )

        XCTAssertEqual(result.custom, ["/Opt/Apps", "/Volumes/Tools", "/Volumes/ToolsExtra"])
        XCTAssertEqual(result.skipped, ["/Applications/Utilities", "/Users/example/Applications", "/Volumes/Tools/Sub"])
    }
}
