import AppKit
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
final class ExtraItemIconTests: XCTestCase {
    func testTypeBadgesAreDistinctAndOnlyAtTheBottomLeft() {
        let website = LaunchItem(definition: ExtraItemDefinition(name: "文档", target: .website(URL(string: "https://example.com")!)))
        let shortcut = LaunchItem(definition: ExtraItemDefinition(name: "指令", target: .shortcut(UUID())))
        XCTAssertEqual(ItemIconPresentation.badge(for: website), .website)
        XCTAssertEqual(ItemIconPresentation.badge(for: shortcut), .shortcut)
        XCTAssertNil(ItemIconPresentation.badge(for: makeLaunchItems(count: 1)[0]))
        for side in [24.0, 64.0, 128.0] {
            let body = ItemIconPresentation.bodyFrame(side: side)
            XCTAssertEqual(body.width, side * 824 / 1024, accuracy: 0.001)
            XCTAssertEqual(body.midX, side / 2, accuracy: 0.001)
            XCTAssertEqual(body.midY, side / 2, accuracy: 0.001)
            let badge = ItemIconPresentation.badgeFrame(side: side)
            XCTAssertEqual(badge.width, body.width / 3, accuracy: 0.001)
            XCTAssertLessThan(badge.minX, body.minX)
            XCTAssertGreaterThan(badge.maxY, body.maxY)
            XCTAssertGreaterThanOrEqual(badge.minX, 0)
            XCTAssertLessThanOrEqual(badge.maxY, side)
        }
    }

    func testInvalidImportedArtworkFallsBackWithoutDecodingAnUnboundedImage() {
        XCTAssertNil(ItemImageData.normalized(Data([1, 2, 3])))
        XCTAssertNil(ItemImageData.normalized(Data(repeating: 0, count: 1_048_577)))
    }
}
