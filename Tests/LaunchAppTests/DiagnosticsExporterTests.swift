import Foundation
import XCTest
@testable import LaunchApp

final class DiagnosticsExporterTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testPackagesAvailableSourcesAndSkipsMissing() throws {
        let source = try makeDirectory()
        let log = source.appending(path: "launch.log")
        try Data("日志内容".utf8).write(to: log)
        let crashes = source.appending(path: "DiagnosticReports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: crashes, withIntermediateDirectories: true)
        try Data("crash".utf8).write(to: crashes.appending(path: "LaunchApp-2026-10-21-101010.ips"))
        try Data("other".utf8).write(to: crashes.appending(path: "Safari-2026-10-21-101010.ips"))
        let layout = source.appending(path: "layout.json")
        try Data("{}".utf8).write(to: layout)
        let output = try makeDirectory()
        let zip = output.appending(path: "诊断.zip")

        try DiagnosticsExporter.export(
            DiagnosticsSources(
                logFiles: [log, source.appending(path: "launch.1.log")],
                crashReportsDirectory: crashes,
                layoutFiles: [layout],
                settings: Data("<plist/>".utf8),
                systemInfo: "macOS 26"
            ),
            to: zip
        )

        let unpacked = try makeDirectory()
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: unpacked.path), ["Launch Diagnostics"])
        let root = unpacked.appending(path: "Launch Diagnostics")
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(files, ["crash-reports", "crash-reports/LaunchApp-2026-10-21-101010.ips", "layout", "layout/layout.json", "logs", "logs/launch.log", "settings.plist", "system-info.txt"])
        XCTAssertEqual(try String(contentsOf: root.appending(path: "system-info.txt"), encoding: .utf8), "macOS 26")
    }
}
