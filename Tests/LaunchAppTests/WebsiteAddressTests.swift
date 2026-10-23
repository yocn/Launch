import XCTest
@testable import LaunchApp

final class WebsiteAddressTests: XCTestCase {
    func testNormalizesBareHostsAndPreservesHTTPPaths() throws {
        XCTAssertEqual(try WebsiteAddress.normalized(" example.com/docs ").absoluteString, "https://example.com/docs")
        XCTAssertEqual(try WebsiteAddress.normalized("http://localhost:8080/docs?q=1").scheme, "http")
        for text in ["file:///tmp/a", "javascript:alert(1)", "https://u:p@example.com", "https:///", "", "not a domain"] {
            XCTAssertThrowsError(try WebsiteAddress.normalized(text), text)
        }
    }
}
