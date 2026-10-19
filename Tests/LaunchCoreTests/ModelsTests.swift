import XCTest
@testable import LaunchCore

final class ModelsTests: XCTestCase {
    func testAppIdentityUsesBundleIdentifierBeforePath() {
        let identity = AppIdentity(
            bundleIdentifier: "com.example.Reader",
            path: "/Applications/Reader.app"
        )

        XCTAssertEqual(identity.stableKey, "bundle:com.example.Reader")
    }

    func testLayoutDocumentCanRepresentAnIntentionalEmptySlot() {
        let reader = AppIdentity(
            bundleIdentifier: "com.example.Reader",
            path: "/Applications/Reader.app"
        )
        let page = LayoutPage(slots: [.app(reader), .empty])
        let document = LayoutDocument(pages: [page])

        XCTAssertEqual(document.pages.first?.slots.count, 2)
        XCTAssertEqual(document.pages.first?.slots[1], .empty)
    }
}
