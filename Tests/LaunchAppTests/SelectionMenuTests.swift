import AppKit
import XCTest
@testable import LaunchApp

@MainActor
final class SelectionMenuTests: XCTestCase {
    private func trigger(_ item: NSMenuItem?) {
        guard let item, let action = item.action else {
            return XCTFail("菜单项没有动作")
        }
        _ = (item.target as? NSObject)?.perform(action, with: item)
    }

    func testMenuListsCommandsForSelection() {
        var chosen: [SelectionCommand] = []
        let builder = SelectionMenu { chosen.append($0) }
        let menu = builder.makeMenu(SelectionMenuContent(
            count: 3,
            folders: [.init(id: "f", name: "效率")],
            pageCount: 2
        ))
        let pages = menu.items[5].submenu

        XCTAssertEqual(menu.items.map(\.title), ["已选中 3 个项目", "", "合并到新文件夹", "合并到“效率”", "", "移动到"])
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertTrue(menu.items[2].isEnabled)
        XCTAssertEqual(pages?.items.map(\.title), ["第 1 页", "第 2 页", "", "新页面"])

        trigger(menu.items[2])
        trigger(menu.items[3])
        trigger(pages?.items[1])
        trigger(pages?.items[3])
        XCTAssertEqual(chosen, [.mergeIntoNewFolder, .mergeInto(folder: "f"), .moveToPage(1), .moveToNewPage])
    }

    func testSingleItemCannotMerge() {
        let menu = SelectionMenu { _ in }.makeMenu(SelectionMenuContent(
            count: 1,
            folders: [.init(id: "f", name: "效率")],
            pageCount: 1
        ))

        XCTAssertEqual(menu.items.map(\.title), ["已选中 1 个项目", "", "合并到新文件夹", "", "移动到"])
        XCTAssertFalse(menu.items[2].isEnabled)
    }
}
