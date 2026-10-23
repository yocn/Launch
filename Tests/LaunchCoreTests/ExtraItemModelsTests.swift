import Foundation
import XCTest
@testable import LaunchCore

final class ExtraItemModelsTests: XCTestCase {
    func testTargetsHaveDistinctIdentitiesAndNoApplicationCapability() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let website = ExtraItemDefinition(id: id, name: "同名", target: .website(URL(string: "https://example.com")!))
        let shortcut = ExtraItemDefinition(id: id, name: "同名", target: .shortcut(id))
        XCTAssertNotEqual(website.identity, shortcut.identity)
        XCTAssertNil(website.identity.applicationIdentity)
        XCTAssertNil(shortcut.identity.applicationIdentity)
        let item = LaunchItem(definition: website)
        XCTAssertNil(item.application)
        XCTAssertEqual(item.displayName, "同名")
        XCTAssertEqual(try JSONDecoder().decode(ExtraItemDefinition.self, from: JSONEncoder().encode(website)), website)
    }

    func testMixedItemsStaySearchableWithoutAutomaticGridInsertion() {
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let website = LaunchItem(definition: ExtraItemDefinition(id: id, name: "文档", target: .website(URL(string: "https://docs.example.com")!)))
        let app = LaunchItem(application: CatalogApp(identity: AppIdentity(bundleIdentifier: "app.test", path: "/Applications/Test.app"), displayName: "Test"))
        let result = LayoutEngine.reconcile(layout: LayoutDocument(), catalog: [app, website], pageCapacity: 35)
        XCTAssertEqual(result.pages, [[.item(app)]])
        XCTAssertEqual(SearchIndex(items: [app, website]).results(for: "docs.example", hidden: []), [website])
    }

    func testMixedFolderAndIconDataSurviveBackup() throws {
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let website = ExtraItemDefinition(id: id, name: "文档", target: .website(URL(string: "https://example.com")!), customIconData: Data([1, 2, 3]))
        let app = AppIdentity(bundleIdentifier: "app.test", path: "/Applications/Test.app")
        let document = LayoutDocument(pages: [LayoutPage(slots: [.folder(LayoutFolder(id: "f", name: "混合", items: [.application(app), website.identity])), .empty])], hiddenItems: [website.identity], extraItems: [website])
        XCTAssertEqual(try LayoutBackup.decode(LayoutBackup.encode(document)), document)
    }

    func testMixedItemsCanMergeMoveHideAndKeepDefinitions() {
        let definition = ExtraItemDefinition(name: "文档", target: .website(URL(string: "https://example.com")!))
        let website = LaunchItem(definition: definition)
        let app = layoutApp("Reader")
        let original = LayoutDocument(pages: [LayoutPage(slots: [.item(app.identity), .item(website.identity)])], extraItems: [definition])
        let grouped = LayoutEditor.apply(.mergeIntoNewFolder([.item(app.identity.stableKey), .item(website.identity.stableKey)]), to: original, catalog: [app, website], pageCapacity: 35, makeFolderID: { "f" })
        guard case .folder(let folder) = grouped.pages[0].slots[0] else { return XCTFail("未合并") }
        XCTAssertEqual(folder.items, [app.identity, website.identity])
        XCTAssertEqual(grouped.extraItems, [definition])
        let hidden = LayoutEditor.apply(.hide([.folder("f")]), to: grouped, catalog: [app, website], pageCapacity: 35)
        XCTAssertEqual(Set(hidden.hiddenItems), [app.identity, website.identity])
        let restored = LayoutEditor.apply(.unhide([website.identity, app.identity]), to: hidden, catalog: [app, website], pageCapacity: 35)
        XCTAssertEqual(restored, grouped)
        let moved = LayoutEditor.apply(.moveOutOfFolder(app: website.identity.stableKey, folder: "f", to: .newPage), to: grouped, catalog: [app, website], pageCapacity: 35)
        XCTAssertEqual(moved.pages.last?.slots, [.item(website.identity)])
        XCTAssertEqual(moved.extraItems, [definition])
    }
}
