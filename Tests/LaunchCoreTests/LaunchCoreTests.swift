import XCTest
@testable import LaunchCore

final class LaunchCoreTests: XCTestCase {
    func testPackageExposesVersionedLayoutSchema() {
        XCTAssertEqual(LayoutDocument.currentVersion, 2)
    }
}
