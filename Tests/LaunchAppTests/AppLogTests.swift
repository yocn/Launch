import Foundation
import XCTest
@testable import LaunchApp

final class AppLogTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testWritesTimestampedLevelLines() throws {
        let log = AppLog(directory: try makeDirectory(), now: { Date(timeIntervalSince1970: 0) })

        log.info("启动")
        log.error("保存布局失败")
        log.flush()

        let lines = try String(contentsOf: log.fileURL, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix(" [信息] 启动"))
        XCTAssertTrue(lines[1].hasSuffix(" [错误] 保存布局失败"))
        XCTAssertTrue(lines[0].hasPrefix("1970-01-01"))
    }

    func testRotatesWhenFull() throws {
        let log = AppLog(directory: try makeDirectory(), maxBytes: 120)

        for index in 0 ..< 10 {
            log.info("第 \(index) 条记录")
        }
        log.flush()

        let current = try String(contentsOf: log.fileURL, encoding: .utf8)
        let rotated = try String(contentsOf: log.rotatedURL, encoding: .utf8)
        XCTAssertLessThanOrEqual(current.utf8.count, 120)
        XCTAssertTrue(current.contains("第 9 条记录"))
        XCTAssertFalse(rotated.contains("第 0 条记录"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: log.fileURL.deletingLastPathComponent().path).sorted(), ["launch.1.log", "launch.log"])
    }
}
