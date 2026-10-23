import AppKit
import XCTest
@testable import LaunchApp

private actor IconRequests {
    var paths: [String] = []
    func append(_ path: String) { paths.append(path) }
}

final class WebsiteIconFetcherTests: XCTestCase {
    private func icon() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: XCTUnwrap(context.makeImage())).representation(using: .png, properties: [:]))
    }

    func testTouchIconIsPreferredAndCrossOriginIconsAreNotRequested() async throws {
        let png = try icon()
        let requests = IconRequests()
        let fetcher = WebsiteIconFetcher(load: { url, limit in
            await requests.append(url.path)
            if url.path == "/docs" {
                return Data(#"<link href="https://tracker.example/icon.png" rel="apple-touch-icon"><link href="/touch.png" rel="apple-touch-icon"><link href="/favicon.ico" rel="icon">"#.utf8)
            }
            XCTAssertEqual(url.host, "example.com")
            XCTAssertLessThanOrEqual(limit, 1_048_576)
            return png
        })
        let result = await fetcher.fetch(for: URL(string: "https://example.com/docs")!)
        XCTAssertNotNil(result)
        let paths = await requests.paths
        XCTAssertEqual(paths, ["/docs", "/touch.png"])
    }

    func testNoLinksUsesFaviconAndInvalidOrOversizeResponsesFallBack() async {
        let requests = IconRequests()
        let fetcher = WebsiteIconFetcher(load: { url, _ in
            await requests.append(url.path)
            return Data("not an image".utf8)
        })
        let result = await fetcher.fetch(for: URL(string: "https://example.com")!)
        XCTAssertNil(result)
        let paths = await requests.paths
        XCTAssertEqual(paths, ["", "/favicon.ico"])
        let oversized = WebsiteIconFetcher(load: { _, limit in Data(repeating: 1, count: limit + 1) })
        let largeResult = await oversized.fetch(for: URL(string: "https://example.com")!)
        XCTAssertNil(largeResult)
    }

    func testRedirectPolicyRejectsCrossOriginCredentialsAndDowngrades() {
        let origin = URL(string: "https://example.com")!
        XCTAssertTrue(WebsiteIconFetcher.isAllowed(URL(string: "https://example.com/icon.png")!, origin: origin))
        for value in ["https://elsewhere.example/icon", "http://example.com/icon", "file:///tmp/icon", "https://u:p@example.com/icon"] {
            XCTAssertFalse(WebsiteIconFetcher.isAllowed(URL(string: value)!, origin: origin))
        }
    }
}
