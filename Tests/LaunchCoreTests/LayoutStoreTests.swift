import Foundation
import XCTest
@testable import LaunchCore

final class LayoutStoreTests: XCTestCase {
    func testSaveThenLoadPreservesEmptySlots() throws {
        let store = try temporaryStore()
        let document = LayoutDocument(pages: [LayoutPage(slots: [.empty])])

        try store.save(document)

        XCTAssertEqual(try store.load(), document)
    }

    func testMalformedImportDoesNotReplaceSavedLayout() throws {
        let store = try temporaryStore()
        let original = LayoutDocument(pages: [LayoutPage(slots: [.empty])])
        try store.save(original)

        XCTAssertThrowsError(try store.replaceFromImport(Data("not json".utf8)))

        XCTAssertEqual(try store.load(), original)
    }

    private func temporaryStore() throws -> LayoutStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return LayoutStore(fileURL: directory.appending(path: "layout.json"))
    }
}
