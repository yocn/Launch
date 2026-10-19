import XCTest
@testable import LaunchCore

final class SearchServiceTests: XCTestCase {
    func testSearchFindsNameCaseInsensitively() {
        let reader = catalogApp()

        XCTAssertEqual(
            SearchService.results(for: "READ", in: [reader], hidden: []),
            [reader]
        )
    }

    func testSearchExcludesHiddenApps() {
        let reader = catalogApp()

        XCTAssertTrue(
            SearchService.results(
                for: "read",
                in: [reader],
                hidden: [reader.identity]
            ).isEmpty
        )
    }

    private func catalogApp() -> CatalogApp {
        CatalogApp(
            identity: AppIdentity(
                bundleIdentifier: "com.example.Reader",
                path: "/Applications/Reader.app"
            ),
            displayName: "Reader"
        )
    }
}
