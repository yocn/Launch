import AppKit
import XCTest
@testable import LaunchApp

final class IconCacheTests: XCTestCase {
    @MainActor
    func testIconIsLoadedOncePerPath() {
        var loadedPaths: [String] = []
        let cache = IconCache { path in
            loadedPaths.append(path)
            return NSImage()
        }

        _ = cache.icon(for: "/Applications/A.app")
        _ = cache.icon(for: "/Applications/A.app")
        _ = cache.icon(for: "/Applications/B.app")

        XCTAssertEqual(loadedPaths, ["/Applications/A.app", "/Applications/B.app"])
    }

    @MainActor
    func testRemoveAllForcesReload() {
        var loads = 0
        let cache = IconCache { _ in
            loads += 1
            return NSImage()
        }

        _ = cache.icon(for: "/Applications/A.app")
        cache.removeAll()
        _ = cache.icon(for: "/Applications/A.app")

        XCTAssertEqual(loads, 2)
    }
}
