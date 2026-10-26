import AppKit
import XCTest
@testable import LaunchApp

@MainActor
private final class ManualIconLoader {
    var requests: [String] = []
    private var completions: [(String, @MainActor @Sendable (CGImage?) -> Void)] = []

    func load(_ path: String, _ completion: @escaping @MainActor @Sendable (CGImage?) -> Void) {
        requests.append(path)
        completions.append((path, completion))
    }

    func finish(_ path: String, with image: CGImage? = makeImage()) {
        let matching = completions.filter { $0.0 == path }
        completions.removeAll { $0.0 == path }
        matching.forEach { $0.1(image) }
    }
}

private final class Stamps: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    init(_ values: [String: String]) { self.values = values }
    func value(_ path: String) -> String? { lock.withLock { values[path] } }
    func set(_ path: String, _ value: String) { lock.withLock { values[path] = value } }
}

private func makeImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}

@MainActor
final class IconCacheTests: XCTestCase {
    func testIconIsNilUntilLoadedInBackground() {
        let loader = ManualIconLoader()
        let cache = IconCache(load: loader.load)

        XCTAssertNil(cache.icon(for: "/Applications/A.app"))
        loader.finish("/Applications/A.app")

        XCTAssertNotNil(cache.icon(for: "/Applications/A.app"))
    }

    func testIconIsLoadedOncePerPath() {
        let loader = ManualIconLoader()
        let cache = IconCache(load: loader.load)

        _ = cache.icon(for: "/Applications/A.app")
        _ = cache.icon(for: "/Applications/A.app")
        loader.finish("/Applications/A.app")
        _ = cache.icon(for: "/Applications/A.app")
        _ = cache.icon(for: "/Applications/B.app")

        XCTAssertEqual(loader.requests, ["/Applications/A.app", "/Applications/B.app"])
    }

    func testRemoveAllForcesReload() {
        let loader = ManualIconLoader()
        let cache = IconCache(load: loader.load)

        _ = cache.icon(for: "/Applications/A.app")
        loader.finish("/Applications/A.app")
        cache.removeAll()

        XCTAssertNil(cache.icon(for: "/Applications/A.app"))
        XCTAssertEqual(loader.requests, ["/Applications/A.app", "/Applications/A.app"])
    }

    func testLoadFinishingAfterRemoveAllIsIgnored() {
        let loader = ManualIconLoader()
        let cache = IconCache(load: loader.load)

        _ = cache.icon(for: "/Applications/A.app")
        cache.removeAll()
        loader.finish("/Applications/A.app")

        XCTAssertNil(cache.icon(for: "/Applications/A.app"))
    }

    func testFailedLoadKeepsPlaceholderWithoutRetrying() {
        let loader = ManualIconLoader()
        let cache = IconCache(load: loader.load)

        _ = cache.icon(for: "/Applications/A.app")
        loader.finish("/Applications/A.app", with: nil)

        XCTAssertNil(cache.icon(for: "/Applications/A.app"))
        XCTAssertEqual(loader.requests, ["/Applications/A.app"])
    }

    func testResolverRasterizesRealIcon() throws {
        let image = try XCTUnwrap(ApplicationIconResolver.icon(for: "/System/Applications/Calculator.app"))
        XCTAssertEqual(image.width, ApplicationIconResolver.pixelSide)
        XCTAssertEqual(image.height, ApplicationIconResolver.pixelSide)
    }

    func testChangedBundleReloadsTheIconInPlaceWhileUnchangedOnesAreLeftAlone() async {
        let loader = ManualIconLoader()
        let stamps = Stamps(["/A.app": "installing", "/B.app": "ready"])
        let cache = IconCache(load: loader.load, signature: { stamps.value($0) })
        _ = cache.icon(for: "/A.app")
        _ = cache.icon(for: "/B.app")
        loader.finish("/A.app")
        loader.finish("/B.app")
        XCTAssertEqual(loader.requests, ["/A.app", "/B.app"])

        await cache.reloadChanged()
        XCTAssertEqual(loader.requests.count, 2)

        stamps.set("/A.app", "installed")
        await cache.reloadChanged()
        XCTAssertEqual(loader.requests, ["/A.app", "/B.app", "/A.app"])
        let before = cache.icon(for: "/A.app")
        loader.finish("/A.app", with: makeImage())
        XCTAssertNotNil(cache.icon(for: "/A.app"))
        XCTAssertFalse(before === cache.icon(for: "/A.app"))

        await cache.reloadChanged()
        XCTAssertEqual(loader.requests.count, 3)
    }
}
