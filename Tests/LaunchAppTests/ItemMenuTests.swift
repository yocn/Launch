import AppKit
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
final class ItemMenuTests: XCTestCase {
    private func trigger(_ item: NSMenuItem?) {
        guard let item, let action = item.action else {
            return XCTFail("菜单项没有动作")
        }
        _ = (item.target as? NSObject)?.perform(action, with: item)
    }

    func testSelectionMenu() {
        var chosen: [ItemMenuCommand] = []
        let builder = ItemMenu { chosen.append($0) }
        let menu = builder.makeMenu(.selection(SelectionMenuContent(
            count: 3,
            folders: [.init(id: "f", name: "效率")],
            pageCount: 2
        )))
        let pages = menu.items[5].submenu

        XCTAssertEqual(menu.items.map(\.title), ["已选中 3 个项目", "", "合并到新文件夹", "合并到“效率”", "", "移动到", "隐藏"])
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertEqual(pages?.items.map(\.title), ["第 1 页", "第 2 页", "", "新页面"])

        trigger(menu.items[2])
        trigger(menu.items[3])
        trigger(pages?.items[1])
        trigger(pages?.items[3])
        trigger(menu.items[6])
        XCTAssertEqual(chosen, [.mergeIntoNewFolder, .mergeInto(folder: "f"), .moveToPage(1), .moveToNewPage, .hideSelection])
    }

    func testSingleSelectionCannotMerge() {
        let menu = ItemMenu { _ in }.makeMenu(.selection(SelectionMenuContent(
            count: 1,
            folders: [.init(id: "f", name: "效率")],
            pageCount: 1
        )))

        XCTAssertEqual(menu.items.map(\.title), ["已选中 1 个项目", "", "合并到新文件夹", "", "移动到", "隐藏"])
        XCTAssertFalse(menu.items[2].isEnabled)
    }

    func testAppMenu() {
        var chosen: [ItemMenuCommand] = []
        let app = makeApps(count: 1)[0]
        let builder = ItemMenu { chosen.append($0) }
        let menu = builder.makeMenu(.app(AppMenuContent(
            app: app,
            canOpen: false,
            canEdit: true,
            canUninstall: true
        )))

        XCTAssertEqual(menu.items.map(\.title), ["打开", "", "在访达中显示", "显示简介", "", "隐藏", "移到废纸篓…"])
        XCTAssertFalse(menu.items[0].isEnabled)
        for index in [2, 3, 5, 6] {
            trigger(menu.items[index])
        }
        XCTAssertEqual(chosen, [.revealInFinder(app), .showInfo(app), .hide(.app(app.identity.stableKey)), .moveToTrash(app)])

        let plain = ItemMenu { _ in }.makeMenu(.app(AppMenuContent(
            app: app,
            canOpen: true,
            canEdit: false,
            canUninstall: false
        )))
        XCTAssertEqual(plain.items.map(\.title), ["打开", "", "在访达中显示", "显示简介", "", "隐藏"])
        XCTAssertTrue(plain.items[0].isEnabled)
        XCTAssertFalse(plain.items[5].isEnabled)
    }

    func testFolderMenu() {
        var chosen: [ItemMenuCommand] = []
        let folder = ResolvedFolder(id: "f", name: "效率", apps: makeApps(count: 2))
        let builder = ItemMenu { chosen.append($0) }
        let menu = builder.makeMenu(.folder(FolderMenuContent(folder: folder, canEdit: true)))

        XCTAssertEqual(menu.items.map(\.title), ["打开", "", "重命名", "取消分组", "隐藏"])
        for index in [0, 2, 3, 4] {
            trigger(menu.items[index])
        }
        XCTAssertEqual(chosen, [.open(.folder(folder)), .rename(folder: "f"), .ungroup(folder: "f"), .hide(.folder("f"))])

        let locked = ItemMenu { _ in }.makeMenu(.folder(FolderMenuContent(folder: folder, canEdit: false)))
        XCTAssertEqual([2, 3, 4].map { locked.items[$0].isEnabled }, [false, false, false])
    }

    func testMainMenu() {
        var chosen: [ItemMenuCommand] = []
        let builder = ItemMenu { chosen.append($0) }
        let menu = builder.makeMenu(.main)

        XCTAssertEqual(menu.items.map(\.title), ["设置…"])
        trigger(menu.items[0])
        XCTAssertEqual(chosen, [.openSettings])
    }

    func testHiddenAppOffersUnhide() {
        var chosen: [ItemMenuCommand] = []
        let app = makeApps(count: 1)[0]
        let builder = ItemMenu { chosen.append($0) }
        let menu = builder.makeMenu(.app(AppMenuContent(
            app: app,
            canOpen: true,
            canEdit: true,
            canUninstall: false,
            isHidden: true
        )))

        XCTAssertEqual(menu.items.map(\.title), ["打开", "", "在访达中显示", "显示简介", "", "取消隐藏"])
        trigger(menu.items[5])
        XCTAssertEqual(chosen, [.unhide(app)])
    }
}
