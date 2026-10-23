import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

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

func makeLaunchItems(count: Int) -> [LaunchItem] {
    makeApps(count: count).map(LaunchItem.init(application:))
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

func makeFolder(id: String, name: String, apps: [LaunchItem]) -> ResolvedItem {
    .folder(ResolvedFolder(id: id, name: name, items: apps))
}

final class FakeRunningApp: RunningAppHandle {
    let bundleIdentifier: String?
    let bundlePath: String?
    private let quitsWhenAsked: Bool
    private(set) var terminateCalls = 0

    init(bundleIdentifier: String?, bundlePath: String?, quitsWhenAsked: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.quitsWhenAsked = quitsWhenAsked
    }

    var isTerminated: Bool {
        quitsWhenAsked && terminateCalls > 0
    }

    func terminate() -> Bool {
        terminateCalls += 1
        return true
    }
}

final class TrashRecorder {
    var urls: [URL] = []
    var failure: Error?
}

func makeFakeApp(named name: String, in root: URL, bundleIdentifier: String? = nil) throws -> CatalogApp {
    let url = root.appending(path: "\(name).app/Contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let path = root.appending(path: "\(name).app").path(percentEncoded: false)
    return CatalogApp(
        identity: AppIdentity(bundleIdentifier: bundleIdentifier, path: path.hasSuffix("/") ? String(path.dropLast()) : path),
        displayName: name
    )
}
