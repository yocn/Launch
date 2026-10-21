import XCTest
@testable import LaunchCore

final class LayoutBackupTests: XCTestCase {
    private let a = layoutApp("A")
    private let b = layoutApp("B")
    private let c = layoutApp("C")
    private let gone = AppIdentity(bundleIdentifier: "com.example.gone", path: "/Applications/Gone.app")

    func testEncodingIsStableSortedAndIndented() throws {
        let document = LayoutDocument(pages: [LayoutPage(slots: [.app(a.identity)])], hiddenApps: [b.identity])

        let data = try LayoutBackup.encode(document)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(try LayoutBackup.encode(document), data)
        XCTAssertTrue(text.contains("\n  "))
        XCTAssertFalse(text.contains("\\/"))
        let keys = ["\"hiddenApps\"", "\"pages\"", "\"schemaVersion\""].map { text.range(of: $0)!.lowerBound }
        XCTAssertEqual(keys, keys.sorted())
        XCTAssertEqual(try LayoutBackup.decode(data), document)
    }

    func testDecodeRejectsUnsupportedVersionAndGarbage() {
        XCTAssertThrowsError(try LayoutBackup.decode(Data(#"{"schemaVersion":99,"pages":[]}"#.utf8))) { error in
            XCTAssertEqual(error as? LayoutStoreError, .unsupportedSchema(99))
        }
        XCTAssertThrowsError(try LayoutBackup.decode(Data("not json".utf8)))
    }

    func testImportSummarizesAndKeepsHiddenApps() {
        let backup = LayoutDocument(
            pages: [
                LayoutPage(slots: [.folder(LayoutFolder(id: "f", name: "效率", apps: [a.identity, gone])), .empty]),
                LayoutPage(slots: [.app(b.identity)]),
            ],
            hiddenApps: [b.identity]
        )

        let result = LayoutBackup.makeImport(from: backup, catalog: [a, b, c], pageCapacity: 35)

        XCTAssertEqual(result.summary, LaunchpadImportSummary(pageCount: 2, folderCount: 1, appCount: 3, installedCount: 2, newAppCount: 1))
        XCTAssertEqual(result.document.hiddenApps, [b.identity])
        XCTAssertEqual(result.document.pages.last?.slots.last, .app(c.identity))
    }
}
