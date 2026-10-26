import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
final class EntryPrompter: LayoutPrompting {
    var errors: [String] = []
    func confirmFirstImport(_ summary: LaunchpadImportSummary) -> Bool { false }
    func confirmReimport(_ summary: LaunchpadImportSummary) -> Bool { true }
    func confirmBackupImport(_ summary: LaunchpadImportSummary) -> Bool { true }
    func confirmRestore() -> Bool { true }
    func showError(_ message: String) { errors.append(message) }
}

struct NoEntryLaunchpad: LaunchpadSource {
    var isAvailable: Bool { false }
    func readSnapshot() async throws -> LaunchpadSnapshot { LaunchpadSnapshot(pages: []) }
}

private actor EntryListing {
    var name = "旧名称"
    func rename(_ name: String) { self.name = name }
    func output() -> String { "\(name) (77777777-7777-7777-7777-777777777777)" }
}

private actor DelayedEntryIcons {
    var requests: [CheckedContinuation<Data?, Never>] = []
    var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func load() async -> Data? {
        await withCheckedContinuation { continuation in
            requests.append(continuation)
            let ready = waiters.filter { requests.count >= $0.0 }
            waiters.removeAll { requests.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitFor(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func finish(_ index: Int, data: Data?) { requests[index].resume(returning: data) }
}

@MainActor
final class ExtraItemsControllerTests: XCTestCase {
    func testChangingOnlyShortcutArtworkDoesNotFreezeTheSystemName() async throws {
        let (layout, _) = try await makeLayout()
        let listing = EntryListing()
        let controller = ExtraItemsController(layout: layout, shortcuts: ShortcutService(execute: { _, _ in await listing.output() }), fetchIcon: { _ in nil })
        await controller.refreshShortcuts()
        let item = try XCTUnwrap(controller.items.first)
        try controller.updateAppearance(of: item.identity, name: item.displayName, customIconData: nil)
        await listing.rename("系统新名称")
        await controller.refreshShortcuts()
        XCTAssertEqual(controller.items.first?.displayName, "系统新名称")
        XCTAssertNil(layout.extraItems.first?.nameOverride)
    }

    func testCatalogIsNotPublishedBeforeApplicationsAreScanned() async throws {
        let (layout, _) = try await makeLayout()
        let listing = EntryListing()
        let controller = ExtraItemsController(layout: layout, shortcuts: ShortcutService(execute: { _, _ in await listing.output() }), fetchIcon: { _ in nil })
        var published: [[LaunchItem]] = []
        controller.onCatalogChange = { published.append($0) }

        await controller.refreshShortcuts()
        XCTAssertEqual(controller.items.count, 1)
        XCTAssertTrue(published.isEmpty)

        let app = CatalogApp(identity: AppIdentity(bundleIdentifier: "com.example.notes", path: "/Applications/Notes.app"), displayName: "备忘录")
        controller.setApplications([app])
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(published.first?.count, 2)
    }

    func testImportAndRestoreInvalidateIconResponsesButUndoKeepsThem() async throws {
        let (layout, store) = try await makeLayout()
        let pending = DelayedEntryIcons()
        let controller = ExtraItemsController(layout: layout, fetchIcon: { _ in await pending.load() })
        layout.onDocumentChange = { controller.layoutDidChange() }
        let entry = try controller.saveWebsite(name: "文档", address: "example.com", existing: nil, toPage: 0, customIconData: nil)
        await pending.waitFor(1)
        var imported = entry
        imported.cachedIconData = entryTestPNG()
        let document = LayoutDocument(pages: [LayoutPage(slots: [.item(entry.identity)])], extraItems: [imported])
        XCTAssertNotNil(layout.importBackup(try LayoutBackup.encode(document)))
        await pending.finish(0, data: nil)
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(try store.load()?.extraItems.first?.cachedIconData, imported.cachedIconData)
        controller.refreshWebsiteIcon(entry.identity)
        await pending.waitFor(2)
        layout.restoreBackup()
        await pending.finish(1, data: imported.cachedIconData)
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertNil(try store.load()?.extraItems.first?.cachedIconData)
        controller.refreshWebsiteIcon(entry.identity)
        await pending.waitFor(3)
        _ = try controller.saveWebsite(name: "新名称", address: "example.com", existing: entry, toPage: nil, customIconData: nil)
        layout.undo()
        await pending.finish(2, data: imported.cachedIconData)
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(try store.load()?.extraItems.first?.cachedIconData, imported.cachedIconData)
    }

    func testUndoingAnEditMadeBeforeTheIconArrivedKeepsTheIcon() async throws {
        let (layout, store) = try await makeLayout()
        let pending = DelayedEntryIcons()
        let controller = ExtraItemsController(layout: layout, fetchIcon: { _ in await pending.load() })
        layout.onDocumentChange = { controller.layoutDidChange() }
        let entry = try controller.saveWebsite(name: "文档", address: "example.com", existing: nil, toPage: 0, customIconData: nil)
        await pending.waitFor(1)
        _ = try controller.saveWebsite(name: "项目文档", address: "example.com", existing: entry, toPage: nil, customIconData: nil)
        await pending.finish(0, data: entryTestPNG())
        for _ in 0 ..< 10 { await Task.yield() }

        layout.undo()

        let saved = try XCTUnwrap(store.load()?.extraItems.first)
        XCTAssertEqual(saved.name, "文档")
        XCTAssertEqual(saved.cachedIconData, entryTestPNG())
    }
    func testAddingWebsiteToAFullPageKeepsItOnTheRequestedPage() async throws {
        let (layout, store) = try await makeLayout()
        layout.updatePageCapacity(2)
        await layout.catalogDidChange(makeLaunchItems(count: 3))
        let controller = ExtraItemsController(layout: layout, fetchIcon: { _ in nil })
        let entry = try controller.saveWebsite(name: "文档", address: "example.com", existing: nil, toPage: 0, customIconData: nil)
        XCTAssertTrue(try XCTUnwrap(store.load()).pages[0].slots.contains(.item(entry.identity)))
    }
    func testShortcutRenameFollowsSystemUnlessUserSetsAliasAndRetainsCustomIcon() async throws {
        let (layout, _) = try await makeLayout()
        let listing = EntryListing()
        let service = ShortcutService(execute: { _, _ in await listing.output() })
        let controller = ExtraItemsController(layout: layout, shortcuts: service, fetchIcon: { _ in nil })
        await controller.refreshShortcuts()
        let id = ItemIdentity.shortcut(UUID(uuidString: "77777777-7777-7777-7777-777777777777")!)
        XCTAssertTrue(controller.pin(id, toPage: 0))
        await listing.rename("新名称")
        await controller.refreshShortcuts()
        XCTAssertEqual(controller.items.first?.displayName, "新名称")
        try controller.updateAppearance(of: id, name: "我的别名", customIconData: entryTestPNG())
        await listing.rename("再次改名")
        await controller.refreshShortcuts()
        XCTAssertEqual(controller.items.first?.displayName, "我的别名")
        XCTAssertEqual(controller.items.first?.iconData, entryTestPNG())
    }

    func testOldIconResponsesCannotOverwriteEditedURLOrResurrectDeletedWebsite() async throws {
        let (layout, store) = try await makeLayout()
        let pending = DelayedEntryIcons()
        let controller = ExtraItemsController(layout: layout, fetchIcon: { _ in await pending.load() })
        let original = try controller.saveWebsite(name: "文档", address: "https://old.example", existing: nil, toPage: 0, customIconData: nil)
        await pending.waitFor(1)
        let edited = try controller.saveWebsite(name: "新文档", address: "https://new.example", existing: original, toPage: nil, customIconData: nil)
        await pending.waitFor(2)
        await pending.finish(0, data: Data([1]))
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(try store.load()?.extraItems.first?.target, .website(URL(string: "https://new.example")!))
        XCTAssertNil(try store.load()?.extraItems.first?.cachedIconData)
        XCTAssertTrue(controller.deleteWebsite(edited.identity))
        await pending.finish(1, data: Data([2]))
        for _ in 0 ..< 10 { await Task.yield() }
        XCTAssertEqual(try store.load()?.extraItems, [])
    }
    func testDiscoveryIsSearchOnlyAndPinningIsExplicit() async throws {
        let (layout, store) = try await makeLayout()
        let id = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let service = ShortcutService(execute: { _, _ in "测试 (55555555-5555-5555-5555-555555555555)" })
        let controller = ExtraItemsController(layout: layout, shortcuts: service, fetchIcon: { _ in nil })
        await controller.refreshShortcuts()
        XCTAssertEqual(controller.items.count, 1)
        XCTAssertEqual(try store.load()?.pages, [])
        XCTAssertTrue(controller.pin(.shortcut(id), toPage: 0))
        XCTAssertEqual(try store.load()?.pages.first?.slots, [.item(.shortcut(id))])
        XCTAssertTrue(controller.unpin(.shortcut(id)))
        XCTAssertEqual(try store.load()?.pages, [])
        XCTAssertEqual(controller.items.count, 1, "移出网格不删除系统快捷指令")
    }

    func testWebsiteSaveEditDeleteUndoAndBackupAreComplete() async throws {
        let (layout, store) = try await makeLayout()
        let controller = ExtraItemsController(layout: layout, fetchIcon: { _ in nil })
        let entry = try controller.saveWebsite(name: "文档", address: "example.com", existing: nil, toPage: 0, customIconData: nil)
        XCTAssertEqual(try store.load()?.extraItems, [entry])
        let edited = try controller.saveWebsite(name: "新名称", address: "example.com/docs", existing: entry, toPage: nil, customIconData: nil)
        XCTAssertEqual(entry.identity, edited.identity)
        XCTAssertEqual(controller.items.first?.displayName, "新名称")
        let exported = try layout.exportBackup()
        XCTAssertEqual(try LayoutBackup.decode(exported).extraItems, [edited])
        XCTAssertTrue(controller.deleteWebsite(edited.identity))
        XCTAssertEqual(try store.load()?.extraItems, [])
        XCTAssertEqual(try store.load()?.pages, [])
        layout.undo()
        controller.layoutDidChange()
        XCTAssertEqual(controller.items.map(\.displayName), ["新名称"])
        XCTAssertEqual(try store.load()?.pages.first?.slots, [.item(entry.identity)])
    }

    func testRemovedPinnedShortcutRetainsAliasAndIconAsUnavailable() async throws {
        let (layout, store) = try await makeLayout()
        let id = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let entry = ExtraItemDefinition(id: id, name: "别名", target: .shortcut(id), customIconData: entryTestPNG())
        XCTAssertTrue(layout.saveExtraItem(entry, toPage: 0))
        let controller = ExtraItemsController(layout: layout, shortcuts: ShortcutService(execute: { _, _ in "" }), fetchIcon: { _ in nil })
        await controller.refreshShortcuts()
        XCTAssertEqual(controller.items.first?.displayName, "别名")
        XCTAssertEqual(controller.items.first?.iconData, entryTestPNG())
        XCTAssertFalse(try XCTUnwrap(controller.items.first).isAvailable)
        XCTAssertEqual(try store.load()?.pages.first?.slots, [.item(.shortcut(id))])
    }

    func testPinnedShortcutStaysAvailableUntilAListSucceeds() async throws {
        enum ListFailure: Error { case timedOut }
        let (layout, _) = try await makeLayout()
        let id = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        XCTAssertTrue(layout.saveExtraItem(ExtraItemDefinition(id: id, name: "专注", target: .shortcut(id)), toPage: 0))
        let controller = ExtraItemsController(layout: layout, shortcuts: ShortcutService(execute: { _, _ in throw ListFailure.timedOut }), fetchIcon: { _ in nil })
        XCTAssertTrue(try XCTUnwrap(controller.items.first).isAvailable)

        await controller.refreshShortcuts()
        XCTAssertTrue(try XCTUnwrap(controller.items.first).isAvailable)
        XCTAssertNotNil(controller.lastError)
    }

    private func makeLayout() async throws -> (LayoutCoordinator, LayoutStore) {
        let root = try makeTemporaryDirectory()
        let store = LayoutStore(fileURL: root.appendingPathComponent("layout.json"))
        try store.save(LayoutDocument())
        let layout = LayoutCoordinator(store: store, launchpad: NoEntryLaunchpad(), prompter: EntryPrompter(), log: makeTestLog())
        layout.start()
        await layout.catalogDidChange([])
        return (layout, store)
    }
}
