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

    func testScanPreservesSpacesInApplicationPaths() throws {
        let root = try fixtureApps([
            ("Utility App.app", "com.example.utility"),
        ])

        let apps = try AppCatalog().scan(roots: [root])

        XCTAssertEqual(
            apps.first?.identity.path,
            root.appending(path: "Utility App.app").path
        )
    }

    func testScanIncludesAppsFlaggedHidden() throws {
        let root = try fixtureApps([
            ("Safari.app", "com.apple.Safari"),
        ])
        var appURL = root.appending(path: "Safari.app", directoryHint: .isDirectory)
        var values = URLResourceValues()
        values.isHidden = true
        try appURL.setResourceValues(values)

        let apps = try AppCatalog().scan(roots: [root])

        XCTAssertEqual(apps.map(\.identity.bundleIdentifier), ["com.apple.Safari"])
    }

    func testScanSkipsDotPrefixedEntries() throws {
        let root = try fixtureApps([
            (".Staging.app", "com.example.staging"),
            ("Visible.app", "com.example.visible"),
        ])

        let apps = try AppCatalog().scan(roots: [root])

        XCTAssertEqual(apps.map(\.displayName), ["Visible"])
    }

    func testScanReadsAppCategory() throws {
        let root = try fixtureApps([("Tool.app", "com.example.tool"), ("Plain.app", "com.example.plain")], categories: ["Tool.app": "public.app-category.utilities"])

        let apps = try AppCatalog().scan(roots: [root])

        XCTAssertEqual(apps.map(\.category), [nil, "public.app-category.utilities"])
    }

    private func fixtureApps(_ fixtures: [(String, String)], categories: [String: String] = [:]) throws -> URL {
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
            var plist: [String: String] = [
                "CFBundleIdentifier": bundleIdentifier,
                "CFBundleName": String(name.dropLast(4)),
            ]
            plist["LSApplicationCategoryType"] = categories[name]
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
