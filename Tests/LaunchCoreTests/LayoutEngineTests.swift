import XCTest
@testable import LaunchCore

final class LayoutEngineTests: XCTestCase {
    func testReconcileKeepsMissingLayoutReference() {
        let identity = AppIdentity(
            bundleIdentifier: "com.example.Reader",
            path: "/Applications/Reader.app"
        )
        let document = LayoutDocument(pages: [LayoutPage(slots: [.app(identity)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [])

        XCTAssertEqual(result.pages[0].slots[0], .missing(identity))
        XCTAssertTrue(result.unplacedApps.isEmpty)
    }

    func testReconcileUpdatesPathWhenBundleIdentifierMatches() {
        let saved = AppIdentity(
            bundleIdentifier: "com.example.Reader",
            path: "/Old/Reader.app"
        )
        let current = CatalogApp(
            identity: AppIdentity(
                bundleIdentifier: "com.example.Reader",
                path: "/Applications/Reader.app"
            ),
            displayName: "Reader"
        )
        let document = LayoutDocument(pages: [LayoutPage(slots: [.app(saved)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [current])

        XCTAssertEqual(result.pages[0].slots[0], .app(current.identity))
    }
}
