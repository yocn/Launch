import Foundation
import SQLite3
import XCTest
@testable import LaunchCore

final class LaunchpadSnapshotReaderTests: XCTestCase {
    private let schema = [
        "CREATE TABLE dbinfo (key VARCHAR, value VARCHAR)",
        "CREATE TABLE items (rowid INTEGER PRIMARY KEY ASC, uuid VARCHAR, flags INTEGER, type INTEGER, parent_id INTEGER NOT NULL, ordering INTEGER)",
        "CREATE TABLE apps (item_id INTEGER PRIMARY KEY, title VARCHAR, bundleid VARCHAR)",
        "CREATE TABLE groups (item_id INTEGER PRIMARY KEY, category_id INTEGER, title VARCHAR)",
    ]

    private var sampleRows: [String] {
        [
            "INSERT INTO dbinfo VALUES ('launchpad_root', '1'), ('launchpad_version_root', '5')",
            "INSERT INTO items (rowid, type, parent_id, ordering) VALUES (1, 1, 0, 0), (5, 1, 0, 0)",
            "INSERT INTO items (rowid, type, parent_id, ordering) VALUES (2, 3, 1, 0), (10, 3, 1, 1), (20, 3, 1, 2)",
            "INSERT INTO items (rowid, type, parent_id, ordering) VALUES (11, 4, 10, 1), (12, 2, 10, 0), (13, 4, 10, 2)",
            "INSERT INTO items (rowid, type, parent_id, ordering) VALUES (14, 3, 12, 0), (15, 4, 14, 0), (16, 4, 14, 1)",
            "INSERT INTO items (rowid, type, parent_id, ordering) VALUES (21, 4, 20, 0), (30, 3, 5, 0), (31, 4, 30, 0)",
            "INSERT INTO apps VALUES (11, '备忘录', 'com.apple.Notes'), (13, 'Safari', 'com.apple.Safari'), (15, '邮件', 'com.apple.mail'), (16, '日历', 'com.apple.iCal'), (21, '国际象棋', 'com.apple.Chess'), (31, '天气', 'com.apple.weather')",
            "INSERT INTO groups VALUES (12, 0, '效率')",
        ]
    }

    func testReadsPagesFoldersAndOrderFromLaunchpadRoot() throws {
        let url = try makeDatabase(schema + sampleRows)

        let snapshot = try LaunchpadSnapshotReader().read(databaseURL: url)

        XCTAssertEqual(snapshot, LaunchpadSnapshot(pages: [
            [],
            [
                .folder(id: 12, name: "效率", apps: [
                    LaunchpadApp(bundleIdentifier: "com.apple.mail", title: "邮件"),
                    LaunchpadApp(bundleIdentifier: "com.apple.iCal", title: "日历"),
                ]),
                .app(LaunchpadApp(bundleIdentifier: "com.apple.Notes", title: "备忘录")),
                .app(LaunchpadApp(bundleIdentifier: "com.apple.Safari", title: "Safari")),
            ],
            [.app(LaunchpadApp(bundleIdentifier: "com.apple.Chess", title: "国际象棋"))],
        ]))
    }

    func testReadingLeavesSourceDirectoryUntouched() throws {
        let url = try makeDatabase(schema + sampleRows)
        let directory = url.deletingLastPathComponent()
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let bytes = try Data(contentsOf: url)

        _ = try LaunchpadSnapshotReader().read(databaseURL: url)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testMissingDatabaseIsReported() throws {
        let url = try temporaryDirectory().appending(path: "db")

        XCTAssertThrowsError(try LaunchpadSnapshotReader().read(databaseURL: url)) { error in
            XCTAssertEqual(error as? LaunchpadReadError, .databaseNotFound)
        }
    }

    func testDatabaseWithoutRootIsReported() throws {
        let url = try makeDatabase(schema)

        XCTAssertThrowsError(try LaunchpadSnapshotReader().read(databaseURL: url)) { error in
            XCTAssertEqual(error as? LaunchpadReadError, .missingRoot)
        }
    }

    func testDatabaseWithoutItemsTableIsReported() throws {
        let url = try makeDatabase([
            "CREATE TABLE dbinfo (key VARCHAR, value VARCHAR)",
            "INSERT INTO dbinfo VALUES ('launchpad_root', '1')",
        ])

        XCTAssertThrowsError(try LaunchpadSnapshotReader().read(databaseURL: url)) { error in
            guard case .queryFailed = error as? LaunchpadReadError else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testDefaultDatabaseLivesInDockLaunchpadFolder() {
        XCTAssertEqual(
            LaunchpadSnapshotReader.defaultDatabaseURL()?.path.hasSuffix("com.apple.dock.launchpad/db/db"),
            true
        )
    }

    private func makeDatabase(_ statements: [String]) throws -> URL {
        let url = try temporaryDirectory().appending(path: "db")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        for sql in statements {
            XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, sql)
        }
        return url
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
