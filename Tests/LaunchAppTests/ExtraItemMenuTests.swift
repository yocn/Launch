import AppKit
import LaunchCore
import XCTest
import Observation
import os
@testable import LaunchApp

@MainActor
final class ExtraItemMenuTests: XCTestCase {
    func testSearchObservesCatalogChangesEvenWhenQueryAndIdentityStayTheSame() {
        let definition = ExtraItemDefinition(name: "旧名字", target: .website(URL(string: "https://example.com")!))
        let model = LauncherModel(catalog: [LaunchItem(definition: definition)])
        model.setQuery("example.com")
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = model.results } onChange: { changed.withLock { $0 = true } }
        var edited = definition
        edited.name = "新名字"
        model.updateCatalog([LaunchItem(definition: edited)])
        XCTAssertTrue(changed.withLock { $0 }, "修改条目后，当前搜索界面必须重绘")
        XCTAssertEqual(model.results.first?.displayName, "新名字")
    }
    func testWebsiteNeverGetsApplicationCommandsEvenIfCallerOffersUninstall() {
        let entry = ExtraItemDefinition(name: "文档", target: .website(URL(string: "https://example.com")!))
        var content = AppMenuContent(app: LaunchItem(definition: entry), canOpen: true, canEdit: true, canUninstall: true)
        content.canManageExtraItems = true
        content.pinPage = 2
        var chosen: [ItemMenuCommand] = []
        let builder = ItemMenu { chosen.append($0) }
        let menu = builder.makeMenu(.item(content))
        let names = menu.items.map(\.title)
        XCTAssertFalse(names.contains("移到废纸篓…"))
        XCTAssertFalse(names.contains("显示简介"))
        XCTAssertFalse(names.contains("在访达中显示"))
        XCTAssertTrue(names.contains("编辑网址…"))
        XCTAssertFalse(names.contains("添加到网格"))
        XCTAssertFalse(names.contains("从网格移除"))
        trigger(menu.items[names.firstIndex(of: "删除网址入口…")!])
        XCTAssertEqual(chosen, [.deleteWebsite(entry.identity)])
    }

    func testShortcutCanBePinnedToTheClickedPage() {
        let id = UUID()
        var content = AppMenuContent(app: LaunchItem(definition: ExtraItemDefinition(id: id, name: "指令", target: .shortcut(id))),
                                     canOpen: true, canEdit: true, canUninstall: false)
        content.canManageExtraItems = true
        content.pinPage = 2
        var chosen: [ItemMenuCommand] = []
        let builder = ItemMenu { chosen.append($0) }
        let menu = builder.makeMenu(.item(content))
        trigger(menu.items[menu.items.map(\.title).firstIndex(of: "添加到网格")!])
        XCTAssertEqual(chosen, [.pinEntry(.shortcut(id), page: 2)])
    }

    func testUnavailableShortcutCanBeRemovedButCannotRunAndIsNotDeleted() {
        let id = UUID()
        let entry = ExtraItemDefinition(id: id, name: "指令", target: .shortcut(id))
        var content = AppMenuContent(app: LaunchItem(definition: entry, unavailableReason: "已删除"), canOpen: true, canEdit: true, canUninstall: true)
        content.canManageExtraItems = true
        content.isPinned = true
        let menu = ItemMenu { _ in }.makeMenu(.item(content))
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertTrue(menu.items.map(\.title).contains("从网格移除"))
        XCTAssertFalse(menu.items.map(\.title).contains("删除网址入口…"))
        XCTAssertFalse(menu.items.map(\.title).contains("移到废纸篓…"))
    }

    func testMainMenuRecordsTheClickedPage() {
        var content = MainMenuContent(canSelectAll: true, canArrange: true)
        content.canAddWebsite = true
        content.pageIndex = 3
        var chosen: [ItemMenuCommand] = []
        let builder = ItemMenu { chosen.append($0) }
        let menu = builder.makeMenu(.main(content))
        trigger(menu.items[menu.items.firstIndex { $0.title == "添加网址…" }!])
        XCTAssertEqual(chosen, [.addWebsite(page: 3)])
    }

    private func trigger(_ item: NSMenuItem) {
        guard let action = item.action else { return XCTFail("菜单项没有动作") }
        _ = (item.target as? NSObject)?.perform(action, with: item)
    }
}
