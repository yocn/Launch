import Foundation
import XCTest
@testable import LaunchCore

final class LaunchpadProbeTests: XCTestCase {
    func testProbeReportsMissingCandidateWithoutCreatingIt() throws {
        let directory = try temporaryDirectory()
        let missing = directory.appending(path: "missing.db")

        let report = LaunchpadProbe().inspect(candidateURLs: [missing])

        XCTAssertEqual(report.count, 1)
        XCTAssertEqual(report.first?.status, .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path()))
    }

    func testProbeReportsReadableRegularFile() throws {
        let directory = try temporaryDirectory()
        let source = directory.appending(path: "layout.data")
        try Data("fixture".utf8).write(to: source)

        let report = LaunchpadProbe().inspect(candidateURLs: [source])

        XCTAssertEqual(report.count, 1)
        XCTAssertEqual(report.first?.status, .readableRegularFile)
        XCTAssertEqual(report.first?.byteCount, 7)
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
