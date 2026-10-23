import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

private struct EmptyEntryLaunchpad: LaunchpadSource {
    var isAvailable: Bool { true }
    func readSnapshot() async throws -> LaunchpadSnapshot { LaunchpadSnapshot(pages: []) }
}

@MainActor
final class ExtraItemsBackupTests: XCTestCase {
    func testImportAndRestoreIncludeDefinitionsIconsAndPinnedReferences() async throws {
        let root = try makeTemporaryDirectory()
        let store = LayoutStore(fileURL: root.appendingPathComponent("layout.json"))
        let entry = ExtraItemDefinition(name: "文档", target: .website(URL(string: "https://example.com")!), customIconData: Data([1, 2, 3]))
        let original = LayoutDocument(pages: [LayoutPage(slots: [.item(entry.identity)])], extraItems: [entry])
        try store.save(LayoutDocument())
        let layout = LayoutCoordinator(store: store, launchpad: NoEntryLaunchpad(), prompter: EntryPrompter())
        layout.start()
        await layout.catalogDidChange([])
        XCTAssertNotNil(layout.importBackup(try LayoutBackup.encode(original)))
        XCTAssertEqual(try store.load(), original)
        let before = try Data(contentsOf: store.fileURL)
        XCTAssertNil(layout.importBackup(Data("损坏".utf8)))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
        layout.restoreBackup()
        XCTAssertEqual(try store.load(), LayoutDocument())
    }

    func testLaunchpadReimportRetainsNonApplicationDefinitionsAndPins() async throws {
        let root = try makeTemporaryDirectory()
        let store = LayoutStore(fileURL: root.appendingPathComponent("layout.json"))
        let entry = ExtraItemDefinition(name: "文档", target: .website(URL(string: "https://example.com")!))
        try store.save(LayoutDocument(pages: [LayoutPage(slots: [.item(entry.identity)])], extraItems: [entry]))
        let layout = LayoutCoordinator(store: store, launchpad: EmptyEntryLaunchpad(), prompter: EntryPrompter())
        layout.start()
        await layout.catalogDidChange([LaunchItem(definition: entry)])
        await layout.importFromLaunchpad()
        XCTAssertEqual(try store.load()?.extraItems, [entry])
        XCTAssertEqual(try store.load()?.pinnedIdentities, [entry.identity])
    }
}
