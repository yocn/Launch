import Foundation
import AppKit
import XCTest
@testable import LaunchCore

final class ExtraItemValidationTests: XCTestCase {
    func testCorruptAndOversizedArtworkCannotReplaceLayoutOrExistingBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LayoutStore(fileURL: root.appendingPathComponent("layout.json"))
        try store.save(LayoutDocument())
        try store.replace(with: LayoutDocument(pages: [LayoutPage(slots: [.empty])]))
        let before = try Data(contentsOf: store.fileURL)
        let backup = try Data(contentsOf: store.backupURL)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8193, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let tooWide = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        for data in [Data([1, 2, 3]), tooWide] {
            let entry = ExtraItemDefinition(name: "错误图片", target: .website(URL(string: "https://example.com")!), customIconData: data)
            XCTAssertThrowsError(try store.replace(with: LayoutDocument(extraItems: [entry])))
            // 保存自己生成的布局不再解码校验图片；读取文件时仍会拒绝
            XCTAssertThrowsError(try LayoutBackup.decode(LayoutBackup.encode(LayoutDocument(extraItems: [entry]))))
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
        XCTAssertEqual(try Data(contentsOf: store.backupURL), backup)
    }

    func testDuplicateReferencesFolderIDsAndMissingDefinitionsAreRejected() throws {
        let entry = ExtraItemDefinition(name: "网站", target: .website(URL(string: "https://example.com")!))
        let app = ItemIdentity.application(AppIdentity(bundleIdentifier: "sample.app", path: "/Applications/Sample.app"))
        let invalid = [
            LayoutDocument(pages: [LayoutPage(slots: [.item(entry.identity), .item(entry.identity)])], extraItems: [entry]),
            LayoutDocument(pages: [LayoutPage(slots: [.folder(LayoutFolder(id: "f", name: "1", items: [app])), .folder(LayoutFolder(id: "f", name: "2", items: [entry.identity]))])], extraItems: [entry]),
            LayoutDocument(pages: [LayoutPage(slots: [.item(entry.identity)])]),
        ]
        for document in invalid { XCTAssertThrowsError(try LayoutBackup.decode(LayoutBackup.encode(document))) }
    }
}
