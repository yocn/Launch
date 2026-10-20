import AppKit
import XCTest
@testable import LaunchApp

@MainActor
final class WallpaperProviderTests: XCTestCase {
    private func makeImageFile() throws -> URL {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let url = try makeTemporaryDirectory().appending(path: "wallpaper.png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func scaling(_ value: NSImageScaling) -> NSNumber {
        NSNumber(value: value.rawValue)
    }

    func testFillFollowsWallpaperOptions() throws {
        let url = try makeImageFile()
        let provider = WallpaperProvider()

        XCTAssertEqual(
            provider.wallpaper(url: url, options: [.imageScaling: scaling(.scaleProportionallyUpOrDown), .allowClipping: true])?.fill,
            .aspectFill
        )
        XCTAssertEqual(
            provider.wallpaper(url: url, options: [.imageScaling: scaling(.scaleProportionallyUpOrDown), .allowClipping: false])?.fill,
            .aspectFit
        )
        XCTAssertEqual(provider.wallpaper(url: url, options: [.imageScaling: scaling(.scaleAxesIndependently)])?.fill, .stretch)
        XCTAssertEqual(provider.wallpaper(url: url, options: [.imageScaling: scaling(.scaleNone)])?.fill, .center)
        XCTAssertEqual(provider.wallpaper(url: url, options: [:])?.fill, .aspectFill)
    }

    func testMissingImageGivesNothingAndImagesAreCached() throws {
        let url = try makeImageFile()
        let provider = WallpaperProvider()

        XCTAssertNil(provider.wallpaper(url: nil, options: [:]))
        XCTAssertNil(provider.wallpaper(url: url.appending(path: "missing.png"), options: [:]))
        XCTAssertTrue(provider.wallpaper(url: url, options: [:])?.image === provider.wallpaper(url: url, options: [:])?.image)
    }

    func testBlurredWallpaperSoftensEdges() throws {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        for x in 0 ..< 64 {
            for y in 0 ..< 64 {
                let value: CGFloat = x < 32 ? 0 : 1
                rep.setColor(NSColor(deviceRed: value, green: value, blue: value, alpha: 1), atX: x, y: y)
            }
        }
        let url = try makeTemporaryDirectory().appending(path: "edge.png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        let provider = WallpaperProvider()

        let sharp = try XCTUnwrap(provider.wallpaper(url: url, options: [:], blurred: false)?.image)
        let blurred = try XCTUnwrap(provider.wallpaper(url: url, options: [:], blurred: true)?.image)

        XCTAssertFalse(sharp === blurred)
        let pixels = try XCTUnwrap(blurred.cgImage(forProposedRect: nil, context: nil, hints: nil).map(NSBitmapImageRep.init))
        let edge = try XCTUnwrap(pixels.colorAt(x: 31, y: 32)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(edge.redComponent, 0.1)
        XCTAssertLessThan(edge.redComponent, 0.9)
    }
}
