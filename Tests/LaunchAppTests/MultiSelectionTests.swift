import LaunchCore
import XCTest
@testable import LaunchApp

final class MultiSelectionTests: XCTestCase {
    private let apps = makeApps(count: 4)

    private func id(_ index: Int) -> LayoutItemID {
        .app(apps[index].identity.stableKey)
    }

    func testToggleAddsAndRemoves() {
        var selection = MultiSelection()

        selection.toggle(id(0))
        selection.toggle(id(1))
        selection.toggle(id(0))

        XCTAssertEqual(selection.items, [id(1)])
    }

    func testMarqueeAddsHitsOnTopOfBaseAndShrinksBack() {
        var selection = MultiSelection()
        selection.toggle(id(0))

        selection.beginMarquee()
        selection.updateMarquee(hits: [id(1), id(2)])
        XCTAssertEqual(selection.items, [id(0), id(1), id(2)])

        selection.updateMarquee(hits: [id(1)])
        XCTAssertEqual(selection.items, [id(0), id(1)])

        selection.endMarquee()
        XCTAssertEqual(selection.count, 2)
    }

    func testOrderedFollowsPagesAndRetainDropsMissing() {
        var selection = MultiSelection()
        selection.toggle(id(3))
        selection.toggle(.folder("f"))
        selection.toggle(id(0))
        let pages: [[ResolvedItem]] = [
            [.app(apps[0]), makeFolder(id: "f", name: "效率", apps: [apps[1]])],
            [.app(apps[2]), .app(apps[3])],
        ]

        XCTAssertEqual(selection.ordered(in: pages), [id(0), .folder("f"), id(3)])

        selection.retain([id(0)])
        XCTAssertEqual(selection.items, [id(0)])
    }
}
