import AppKit
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
final class UninstallReviewTests: XCTestCase {
    private func makePlan(items count: Int) -> ResidualPlan {
        let app = CatalogApp(identity: AppIdentity(bundleIdentifier: "dev.example.fixture", path: "/Applications/Fixture.app"), displayName: "Fixture")
        let snapshot = ResidualSnapshot(digest: "fixture", bytes: 75)
        let items = (0 ..< count).map { index in
            ResidualItem(url: URL(fileURLWithPath: "/Users/fixture/Library/Caches/dev.example.fixture\(index)"),
                         category: "缓存", evidence: "精确标识", snapshot: snapshot, blockedReason: nil)
        }
        return ResidualPlan(app: app, appSnapshot: snapshot, infoDigest: "fixture", signing: nil, items: items, notices: [])
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.lazy.compactMap(scrollView).first
    }

    func testShortListFitsWithoutExtraSpaceAndResidualsStartUnchecked() throws {
        let content = UninstallReview(plan: makePlan(items: 1), isRunning: false).makeContent()
        let scroll = try XCTUnwrap(scrollView(in: content))
        let document = try XCTUnwrap(scroll.documentView)

        XCTAssertGreaterThanOrEqual(content.frame.width, 560)
        XCTAssertLessThan(content.frame.height, 250)
        XCTAssertLessThanOrEqual(document.frame.height, scroll.frame.height)
        XCTAssertTrue(scroll.autohidesScrollers)
        func buttons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        let boxes = buttons(content)
        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes.first?.state, .on)
        XCTAssertEqual(boxes.last?.state, .off)
    }

    func testLongListIsCappedAndScrolls() throws {
        let content = UninstallReview(plan: makePlan(items: 15), isRunning: false).makeContent()
        let scroll = try XCTUnwrap(scrollView(in: content))
        let document = try XCTUnwrap(scroll.documentView)

        XCTAssertEqual(scroll.frame.height, 330)
        XCTAssertGreaterThan(document.frame.height, scroll.frame.height)
        XCTAssertGreaterThan(content.frame.height, scroll.frame.height)
    }
}
