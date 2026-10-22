import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

final class UninstallCleanupTests: XCTestCase {
    private func setup() throws -> (UninstallCleanup, ResidualPlan, URL) {
        let root = try makeTemporaryDirectory()
        let apps = root.appending(path: "Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let app = try makeFakeApp(named: "Fixture", in: apps, bundleIdentifier: "dev.example.fixture")
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "dev.example.fixture"], format: .xml, options: 0)
        try info.write(to: URL(fileURLWithPath: app.identity.path).appending(path: "Contents/Info.plist"))
        for relative in ["Caches/dev.example.fixture", "Logs/dev.example.fixture"] {
            try FileManager.default.createDirectory(at: root.appending(path: "Library/" + relative), withIntermediateDirectories: true)
        }
        let scanner = ResidualScanner(home: root, applicationRoots: [apps], signing: { _ in
            ResidualSigning(identifier: "dev.example.fixture", team: "TESTTEAM", groups: [])
        })
        let trash = root.appending(path: "TestTrash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let cleanup = UninstallCleanup(scanner: scanner, recordDirectory: root.appending(path: "Records"), trash: { url in
            let target = trash.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        })
        return (cleanup, try scanner.scan(app), root)
    }

    func testOnlyExplicitlySelectedResidualsMoveAndRecordKeepsActualTrashLocations() throws {
        let (cleanup, plan, _) = try setup()
        let selected = try XCTUnwrap(plan.items.first { $0.category == "缓存" })

        let result = try cleanup.execute(plan, selection: [selected.id])

        XCTAssertTrue(result.appRemoved)
        XCTAssertTrue(result.problems.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.app.identity.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: selected.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(plan.items.first { $0.category == "日志" }).url.path))
        let record = try JSONDecoder().decode(UninstallRecord.self, from: Data(contentsOf: result.recordURL))
        XCTAssertEqual(record.entries.filter { $0.state == .trashed }.count, 2)
        XCTAssertTrue(record.entries.filter { $0.state == .trashed }.allSatisfy { $0.trashPath != nil })
        XCTAssertTrue(record.entries.filter { $0.state == .trashed }.allSatisfy { FileManager.default.fileExists(atPath: $0.trashPath!) })
    }

    func testEmptySelectionKeepsAllResiduals() throws {
        let (cleanup, plan, _) = try setup()
        let result = try cleanup.execute(plan, selection: [])
        XCTAssertTrue(result.appRemoved)
        XCTAssertTrue(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }

    func testForgedSelectionIsRejectedBeforeMovingAnything() throws {
        let (cleanup, plan, root) = try setup()
        XCTAssertThrowsError(try cleanup.execute(plan, selection: [root.path]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.app.identity.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanup.recordDirectory.path))
    }

    func testAppFailureDoesNotMoveResiduals() throws {
        var (cleanup, plan, _) = try setup()
        cleanup.trash = { _ in throw CocoaError(.fileWriteNoPermission) }
        let result = try cleanup.execute(plan, selection: Set(plan.items.map(\.id)))
        XCTAssertFalse(result.appRemoved)
        XCTAssertEqual(result.problems.count, 1)
        XCTAssertTrue(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }

    func testReplacementAndLateChangesAreSkippedAndReported() throws {
        var (cleanup, plan, _) = try setup()
        let logs = try XCTUnwrap(plan.items.first { $0.category == "日志" })
        let originalTrash = cleanup.trash
        cleanup.trash = { url in
            let result = try originalTrash(url)
            if url.pathExtension == "app" { try Data("new".utf8).write(to: logs.url.appending(path: "late.txt")) }
            return result
        }
        let result = try cleanup.execute(plan, selection: Set(plan.items.map(\.id)))
        XCTAssertTrue(result.appRemoved)
        XCTAssertEqual(result.problems.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logs.url.path))
    }

    func testCannotMoveAnythingIfRecordCannotBeCreated() throws {
        var (cleanup, plan, _) = try setup()
        cleanup.writeRecord = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertThrowsError(try cleanup.execute(plan, selection: Set(plan.items.map(\.id))))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.app.identity.path))
        XCTAssertTrue(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }

    func testNewDuplicateAfterReviewStopsBeforeApplicationMoves() throws {
        let (cleanup, plan, root) = try setup()
        let copy = root.appending(path: "Applications/Second.app/Contents")
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "dev.example.fixture"], format: .xml, options: 0)
            .write(to: copy.appending(path: "Info.plist"))
        XCTAssertThrowsError(try cleanup.execute(plan, selection: Set(plan.items.map(\.id))))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.app.identity.path))
    }

    func testApplicationReplacementStopsBeforeMovingAnything() throws {
        let (cleanup, plan, _) = try setup()
        let url = URL(fileURLWithPath: plan.app.identity.path)
        try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("original"))
        try FileManager.default.createDirectory(at: url.appending(path: "Contents"), withIntermediateDirectories: true)
        try Data(contentsOf: url.appendingPathExtension("original").appending(path: "Contents/Info.plist"))
            .write(to: url.appending(path: "Contents/Info.plist"))
        XCTAssertThrowsError(try cleanup.execute(plan, selection: []))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecordFailureAfterAppMoveStopsRemainingItems() throws {
        var (cleanup, plan, _) = try setup()
        let originalWriter = cleanup.writeRecord
        cleanup.writeRecord = { data, url in
            let record = try JSONDecoder().decode(UninstallRecord.self, from: data)
            if record.entries.first?.state == .trashed { throw CocoaError(.fileWriteNoPermission) }
            try originalWriter(data, url)
        }
        let result = try cleanup.execute(plan, selection: Set(plan.items.map(\.id)))
        XCTAssertTrue(result.appRemoved)
        XCTAssertNotNil(result.recordError)
        XCTAssertTrue(plan.items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
        let stored = try JSONDecoder().decode(UninstallRecord.self, from: Data(contentsOf: result.recordURL))
        XCTAssertEqual(stored.entries.first?.state, .moving)
    }
}
