import Foundation
import XCTest
@testable import LaunchApp

final class ApplicationIconResolverTests: XCTestCase {
    func testResolverFindsIconNamedByBundleMetadata() throws {
        let appURL = try fixtureApplication(iconFile: "AppIcon")

        XCTAssertEqual(
            ApplicationIconResolver.iconFileURL(for: appURL)?.lastPathComponent,
            "AppIcon.icns"
        )
    }

    private func fixtureApplication(iconFile: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let appURL = root.appending(path: "Fixture.app", directoryHint: .isDirectory)
        let contentsURL = appURL.appending(path: "Contents", directoryHint: .isDirectory)
        let resourcesURL = contentsURL.appending(path: "Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let plist: [String: String] = [
            "CFBundleIdentifier": "com.example.Fixture",
            "CFBundleIconFile": iconFile,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appending(path: "Info.plist"))
        try Data().write(to: resourcesURL.appending(path: "\(iconFile).icns"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return appURL
    }
}
