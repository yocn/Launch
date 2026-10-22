import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

final class ResidualScannerTests: XCTestCase {
    private func setup() throws -> (ResidualScanner, CatalogApp, URL) {
        let root = try makeTemporaryDirectory().resolvingSymlinksInPath()
        let applications = root.appending(path: "Applications")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let app = try makeFakeApp(named: "Fixture", in: applications, bundleIdentifier: "dev.example.fixture")
        try writePlist(["CFBundleIdentifier": "dev.example.fixture"], at: URL(fileURLWithPath: app.identity.path).appending(path: "Contents/Info.plist"))
        let scanner = ResidualScanner(home: root, applicationRoots: [applications], signing: { _ in
            ResidualSigning(identifier: "dev.example.fixture", team: "TESTTEAM", groups: ["group.dev.example.shared"])
        })
        return (scanner, app, root)
    }

    private func writePlist(_ value: [String: Any], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: url)
    }

    private func directory(_ path: String, in root: URL) throws -> URL {
        let url = root.appending(path: "Library/" + path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testExactPathsAreOffByDefaultAndNamesAndGroupsAreBlocked() throws {
        let (scanner, app, root) = try setup()
        _ = try directory("Caches/dev.example.fixture", in: root)
        _ = try directory("Application Support/Fixture", in: root)
        _ = try directory("Group Containers/group.dev.example.shared", in: root)

        let plan = try scanner.scan(app)

        XCTAssertEqual(plan.items.count, 3)
        XCTAssertEqual(plan.defaultSelection, [])
        XCTAssertTrue(plan.notices.isEmpty, "不存在的候选文件不应报权限或读取错误")
        XCTAssertTrue(try XCTUnwrap(plan.items.first { $0.url.lastPathComponent == "dev.example.fixture" }).isSelectable)
        XCTAssertTrue(plan.items.filter { $0.url.lastPathComponent != "dev.example.fixture" }.allSatisfy { !$0.isSelectable })
    }

    func testUntrustedSignatureAndDuplicateInstallationBlockResiduals() throws {
        var (scanner, app, root) = try setup()
        _ = try directory("Caches/dev.example.fixture", in: root)
        scanner.signing = { _ in nil }
        XCTAssertFalse(try XCTUnwrap(scanner.scan(app).items.first).isSelectable)
        scanner.signing = { _ in ResidualSigning(identifier: "dev.example.fixture", team: "TESTTEAM", groups: []) }
        let copy = try makeFakeApp(named: "Other Copy", in: root.appending(path: "Applications"), bundleIdentifier: "dev.example.fixture")
        try writePlist(["CFBundleIdentifier": "dev.example.fixture"], at: URL(fileURLWithPath: copy.identity.path).appending(path: "Contents/Info.plist"))
        XCTAssertFalse(try XCTUnwrap(scanner.scan(app).items.first).isSelectable)
    }

    // 目录都不存在仍列出，说明没有探测磁盘
    func testProtectedContainersComeFromSignatureWithoutTouchingDisk() throws {
        var (scanner, app, _) = try setup()
        scanner.signing = { _ in
            ResidualSigning(identifier: "dev.example.fixture", team: "TESTTEAM", groups: ["group.dev.example.shared"], sandboxed: true)
        }

        let plan = try scanner.scan(app)

        let protected = plan.items.filter { $0.url.path.contains("Containers/") }
        XCTAssertEqual(protected.map(\.url.lastPathComponent), ["dev.example.fixture", "group.dev.example.shared"])
        XCTAssertTrue(protected.allSatisfy { !$0.isSelectable && $0.snapshot == nil })
        XCTAssertTrue(plan.notices.isEmpty)

        scanner.signing = { _ in ResidualSigning(identifier: "dev.example.fixture", team: "TESTTEAM", groups: []) }
        XCTAssertTrue(try scanner.scan(app).items.isEmpty)
    }

    func testSymlinksAndHardLinksCannotBeSelected() throws {
        let (scanner, app, root) = try setup()
        let documents = root.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let cacheParent = try directory("Caches", in: root)
        try FileManager.default.createSymbolicLink(at: cacheParent.appending(path: "dev.example.fixture"), withDestinationURL: documents)
        XCTAssertFalse(try XCTUnwrap(scanner.scan(app).items.first).isSelectable)
        let logs = try directory("Logs/dev.example.fixture", in: root)
        let personal = documents.appending(path: "personal.txt")
        try Data("keep".utf8).write(to: personal)
        try FileManager.default.linkItem(at: personal, to: logs.appending(path: "linked.txt"))
        XCTAssertTrue(try scanner.scan(app).items.allSatisfy { !$0.isSelectable })
        XCTAssertEqual(try String(contentsOf: personal, encoding: .utf8), "keep")
    }

    func testRevalidationRejectsReplacementAndNewContent() throws {
        let (scanner, app, root) = try setup()
        let cache = try directory("Caches/dev.example.fixture", in: root)
        let item = try XCTUnwrap(scanner.scan(app).items.first)
        XCTAssertNoThrow(try scanner.revalidate(item))
        try Data("changed".utf8).write(to: cache.appending(path: "new"))
        XCTAssertThrowsError(try scanner.revalidate(item))
        try FileManager.default.moveItem(at: cache, to: cache.appendingPathExtension("old"))
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        XCTAssertThrowsError(try scanner.revalidate(item))
    }

    func testMalformedIdentifierDoesNotGenerateCandidates() throws {
        let (scanner, app, _) = try setup()
        for identifier in ["../Documents", "dev.example/../../Documents", "com.apple.Safari", "Com.Apple.Fixture", "com.apple", "dev..example"] {
            let invalid = CatalogApp(identity: AppIdentity(bundleIdentifier: identifier, path: app.identity.path), displayName: "Fixture")
            XCTAssertTrue(try scanner.scan(invalid).items.isEmpty)
        }
    }

    func testUnreadableInventoryAndScanLimitBlockResiduals() throws {
        var (scanner, app, root) = try setup()
        _ = try directory("Caches/dev.example.fixture", in: root)
        let broken = root.appending(path: "Applications/Broken.app/Contents")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        XCTAssertFalse(try XCTUnwrap(scanner.scan(app).items.first).isSelectable)
        scanner.entryLimit = 0
        XCTAssertTrue(try scanner.scan(app).items.allSatisfy { !$0.isSelectable })
    }

    func testChangedAncestorAndInternalSymlinkAreRejected() throws {
        let (scanner, app, root) = try setup()
        let cache = try directory("Caches/dev.example.fixture", in: root)
        let first = try XCTUnwrap(scanner.scan(app).items.first)
        let parent = cache.deletingLastPathComponent()
        try FileManager.default.moveItem(at: parent, to: parent.appendingPathExtension("old"))
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: parent.appendingPathExtension("old").appending(path: "dev.example.fixture"), to: cache)
        XCTAssertThrowsError(try scanner.revalidate(first))
        try FileManager.default.createSymbolicLink(at: cache.appending(path: "link"), withDestinationURL: root)
        XCTAssertFalse(try XCTUnwrap(scanner.scan(app).items.first).isSelectable)
    }

    func testSignatureIdentifierMismatchAndInfoSpoofAreBlocked() throws {
        var (scanner, app, root) = try setup()
        _ = try directory("Caches/dev.example.fixture", in: root)
        scanner.signing = { _ in ResidualSigning(identifier: "dev.other.application", team: "TESTTEAM", groups: []) }
        XCTAssertFalse(try XCTUnwrap(scanner.scan(app).items.first).isSelectable)
        scanner.signing = { _ in ResidualSigning(identifier: "dev.example.fixture", team: "TESTTEAM", groups: []) }
        try writePlist(["CFBundleIdentifier": "dev.other.application"], at: URL(fileURLWithPath: app.identity.path).appending(path: "Contents/Info.plist"))
        XCTAssertFalse(try XCTUnwrap(scanner.scan(app).items.first).isSelectable)
    }

    func testCaseVariantAndChildIdentifierOfOtherAppsAreConservativelyBlocked() throws {
        let (scanner, app, root) = try setup()
        _ = try directory("Caches/dev.example.fixture", in: root)
        let other = root.appending(path: "Applications/Related.app/Contents/Info.plist")
        for identifier in ["DEV.EXAMPLE.FIXTURE", "dev.example.fixture.helper"] {
            try writePlist(["CFBundleIdentifier": identifier], at: other)
            XCTAssertFalse(try XCTUnwrap(scanner.scan(app).items.first).isSelectable)
        }
    }
}
