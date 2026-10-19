import Foundation
import XCTest
@testable import LaunchCore

final class AppCatalogTests: XCTestCase {
    func testScanSelectsLexicallyFirstPathForDuplicateBundleIdentifier() throws {
        let root = try fixtureApps([
            ("Zulu.app", "com.example.Reader"),
            ("Alpha.app", "com.example.Reader"),
        ])

        let apps = try AppCatalog().scan(roots: [root])

        XCTAssertEqual(apps.map(\.displayName), ["Alpha"])
        XCTAssertEqual(apps.first?.identity.path, root.appending(path: "Alpha.app").path())
    }

    private func fixtureApps(_ fixtures: [(String, String)]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        for (name, bundleIdentifier) in fixtures {
            let appURL = root.appending(path: name, directoryHint: .isDirectory)
            let contentsURL = appURL.appending(path: "Contents", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
            let plist: [String: String] = [
                "CFBundleIdentifier": bundleIdentifier,
                "CFBundleName": String(name.dropLast(4)),
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: contentsURL.appending(path: "Info.plist"))
        }
        return root
    }
}
