import Foundation
import XCTest
@testable import LaunchCore

final class LayoutMigrationTests: XCTestCase {
    private let legacy = Data(#"{"schemaVersion":1,"pages":[{"slots":[{"app":{"_0":{"bundleIdentifier":"app.test","path":"/Applications/Test.app"}}},{"empty":{}},{"folder":{"_0":{"id":"f","name":"文件夹","apps":[{"bundleIdentifier":"app.hidden","path":"/Applications/Hidden.app"}]}}}]}],"hiddenApps":[{"bundleIdentifier":"app.hidden","path":"/Applications/Hidden.app"}]}"#.utf8)

    func testLegacyLayoutPreservesPagesEmptyFolderAndHiddenItems() throws {
        let document = try LayoutBackup.decode(legacy)
        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.pages[0].slots[1], .empty)
        guard case .folder(let folder) = document.pages[0].slots[2] else { return XCTFail("文件夹丢失") }
        XCTAssertEqual(folder.name, "文件夹")
        XCTAssertEqual(folder.items, document.hiddenItems)
        XCTAssertEqual(document.extraItems, [])
    }

    func testFirstSaveKeepsOriginalLegacyBytesAndNeverOverwritesMigrationBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("layout.json")
        try legacy.write(to: url)
        let store = LayoutStore(fileURL: url)
        let document = try XCTUnwrap(store.load())
        try store.save(document)
        XCTAssertEqual(try Data(contentsOf: store.migrationBackupURL), legacy)
        try store.save(document)
        XCTAssertEqual(try Data(contentsOf: store.migrationBackupURL), legacy)
    }

    func testUnknownVersionsAndDuplicateDefinitionsAreRejected() throws {
        XCTAssertThrowsError(try LayoutBackup.decode(Data(#"{"schemaVersion":99,"pages":[]}"#.utf8)))
        let id = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let item = ExtraItemDefinition(id: id, name: "文档", target: .website(URL(string: "https://example.com")!))
        XCTAssertThrowsError(try LayoutBackup.decode(LayoutBackup.encode(LayoutDocument(extraItems: [item, item]))))
    }
}
