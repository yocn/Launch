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

    func testRedirectedPageResolvesIconsFromFinalAddressAndAllowsCDNHosts() async throws {
        let png = try icon()
        let requests = IconRequests()
        let fetcher = WebsiteIconFetcher(load: { url, limit in
            await requests.append(url.absoluteString)
            if url.absoluteString == "https://example.com" {
                let page = #"<link rel="icon" href="/small.ico"><link rel="apple-touch-icon" href="https://cdn.example.net/touch.png">"#
                return (Data(page.utf8), URL(string: "https://www.example.com/")!)
            }
            XCTAssertLessThanOrEqual(limit, 1_048_576)
            return (png, url)
        })
        let result = await fetcher.fetch(for: URL(string: "https://example.com")!)
        XCTAssertNotNil(result)
        let paths = await requests.paths
        XCTAssertEqual(paths, ["https://example.com", "https://cdn.example.net/touch.png"])
    }

    func testFallsBackToRelativeLinksThenWellKnownPathsOnFinalHost() async {
        let requests = IconRequests()
        let fetcher = WebsiteIconFetcher(load: { url, _ in
            await requests.append(url.absoluteString)
            if url.path == "/" { return (Data(#"<link rel="icon" href="icon.png">"#.utf8), URL(string: "https://www.example.com/")!) }
            return (Data("not an image".utf8), url)
        })
        let result = await fetcher.fetch(for: URL(string: "https://example.com/")!)
        XCTAssertNil(result)
        let paths = await requests.paths
        XCTAssertEqual(paths, ["https://example.com/", "https://www.example.com/icon.png",
                               "https://www.example.com/apple-touch-icon.png", "https://www.example.com/favicon.ico"])
    }

    func testOversizeResponsesFallBack() async {
        let oversized = WebsiteIconFetcher(load: { url, limit in (Data(repeating: 1, count: limit + 1), url) })
        let largeResult = await oversized.fetch(for: URL(string: "https://example.com")!)
        XCTAssertNil(largeResult)
    }

    func testGBKPageLinksAreParsed() async throws {
        let png = try icon()
        let requests = IconRequests()
        let gbk = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let page = try XCTUnwrap(#"<title>中文</title><link rel="apple-touch-icon" href="/touch.png">"#.data(using: String.Encoding(rawValue: gbk)))
        let fetcher = WebsiteIconFetcher(load: { url, _ in
            await requests.append(url.path)
            return url.path == "/touch.png" ? (png, url) : (page, url)
        })
        let result = await fetcher.fetch(for: URL(string: "https://example.cn/")!)
        XCTAssertNotNil(result)
        let paths = await requests.paths
        XCTAssertEqual(paths, ["/", "/touch.png"])
    }

    func testRejectsCredentialsLocalNetworkAndNonWebAddresses() {
        let origin = URL(string: "https://example.com")!
        for value in ["https://example.com/icon.png", "https://cdn.example.net/icon.png", "http://example.com/icon"] {
            XCTAssertTrue(WebsiteIconFetcher.isAllowed(URL(string: value)!, origin: origin), value)
        }
        for value in ["file:///tmp/icon", "https://u:p@example.com/icon", "javascript:alert(1)",
                      "http://192.168.1.1/icon.png", "http://router.local/icon.png", "http://localhost/icon.png", "http://[::1]/icon"] {
            XCTAssertFalse(WebsiteIconFetcher.isAllowed(URL(string: value)!, origin: origin), value)
        }
        let lan = URL(string: "http://192.168.1.1/")!
        XCTAssertTrue(WebsiteIconFetcher.isAllowed(URL(string: "http://192.168.1.1/icon.png")!, origin: lan))
    }
}
