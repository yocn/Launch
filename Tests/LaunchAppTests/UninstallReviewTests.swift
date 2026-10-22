import AppKit
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
final class UninstallReviewTests: XCTestCase {
    func testAccessoryHasConcreteSizeAndResidualsStartUnchecked() throws {
        let app = CatalogApp(identity: AppIdentity(bundleIdentifier: "dev.example.fixture", path: "/Applications/Fixture.app"), displayName: "Fixture")
        let snapshot = ResidualSnapshot(digest: "fixture", bytes: 75)
        let item = ResidualItem(url: URL(fileURLWithPath: "/Users/fixture/Library/Caches/dev.example.fixture"),
                                category: "缓存", evidence: "精确标识", snapshot: snapshot, blockedReason: nil)
        let plan = ResidualPlan(app: app, appSnapshot: snapshot, infoDigest: "fixture", signing: nil, items: [item], notices: [])
        let content = UninstallReview(plan: plan, isRunning: false).makeContent()
        XCTAssertGreaterThanOrEqual(content.frame.width, 560)
        XCTAssertGreaterThan(content.frame.height, 330)
        func buttons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        let boxes = buttons(content)
        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes.first?.state, .on)
        XCTAssertEqual(boxes.last?.state, .off)
    }
}
