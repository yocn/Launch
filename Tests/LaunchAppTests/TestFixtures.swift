import Foundation
import LaunchCore
import XCTest

func makeApps(count: Int) -> [CatalogApp] {
    (0 ..< count).map { index in
        CatalogApp(
            identity: AppIdentity(
                bundleIdentifier: "com.example.app\(index)",
                path: "/Applications/App \(index).app"
            ),
            displayName: "App \(index)"
        )
    }
}

extension XCTestCase {
    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

func makeFolder(id: String, name: String, apps: [CatalogApp]) -> ResolvedItem {
    .folder(ResolvedFolder(id: id, name: name, apps: apps))
}
