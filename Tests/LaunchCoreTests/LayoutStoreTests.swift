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

    func testReplaceKeepsPreviousLayoutAsBackup() throws {
        let store = try temporaryStore()
        let original = LayoutDocument(pages: [LayoutPage(slots: [.empty])])
        let replacement = LayoutDocument(pages: [LayoutPage(slots: [.empty, .empty])])
        try store.save(original)

        try store.replace(with: replacement)

        XCTAssertEqual(try store.load(), replacement)
        XCTAssertTrue(store.hasBackup)
    }

    func testSwapWithBackupExchangesLayoutsBothWays() throws {
        let store = try temporaryStore()
        let original = LayoutDocument(pages: [LayoutPage(slots: [.empty])])
        let replacement = LayoutDocument(pages: [LayoutPage(slots: [.empty, .empty])])
        try store.save(original)
        try store.replace(with: replacement)

        try store.swapWithBackup()
        XCTAssertEqual(try store.load(), original)

        try store.swapWithBackup()
        XCTAssertEqual(try store.load(), replacement)
    }

    func testCorruptBackupIsRejectedWithoutTouchingLayout() throws {
        let store = try temporaryStore()
        let original = LayoutDocument(pages: [LayoutPage(slots: [.empty])])
        try store.save(original)
        try Data("not json".utf8).write(to: store.backupURL)

        XCTAssertThrowsError(try store.swapWithBackup())

        XCTAssertEqual(try store.load(), original)
    }

    func testPathWithSpacesLoadsAndBacksUp() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let store = LayoutStore(fileURL: root.appending(path: "Application Support/Launch/layout.json"))
        let original = LayoutDocument(pages: [LayoutPage(slots: [.empty])])
        try store.save(original)

        XCTAssertEqual(try store.load(), original)

        try store.replace(with: LayoutDocument(pages: []))
        XCTAssertTrue(store.hasBackup)
    }

    func testMalformedLayoutFileFailsToLoad() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: store.fileURL)

        XCTAssertThrowsError(try store.load())
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
