import Foundation
import XCTest
@testable import LaunchApp

private actor CommandLog {
    var arguments: [[String]] = []
    func record(_ args: [String]) { arguments.append(args) }
}

final class ShortcutServiceTests: XCTestCase {
    func testParsesNamesWithSpacesAndParenthesesByTrailingUUID() throws {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let rows = try ShortcutService.parseList("专注 模式 (工作) (12345678-1234-1234-1234-123456789ABC)\n")
        XCTAssertEqual(rows, [ShortcutRecord(id: id, name: "专注 模式 (工作)")])
        XCTAssertEqual(try ShortcutService.parseList(""), [])
        XCTAssertThrowsError(try ShortcutService.parseList("无法解析的输出"))
    }

    func testSkipsUnrecognizedLinesWhenOthersParse() throws {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let output = "Warning: something\n专注 (12345678-1234-1234-1234-123456789ABC)\n"
        XCTAssertEqual(try ShortcutService.parseList(output), [ShortcutRecord(id: id, name: "专注")])
    }

    func testRunPassesUUIDAsSingleArgumentWithoutShell() async throws {
        let log = CommandLog()
        let service = ShortcutService(execute: { args, _ in
            await log.record(args)
            return ""
        })
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        try await service.run(id: id)
        let calls = await log.arguments
        XCTAssertEqual(calls, [["run", "12345678-1234-1234-1234-123456789ABC"]])
    }

    func testListUsesReadOnlyCommandAndPropagatesFailure() async {
        enum FixtureFailure: Error { case failed }
        let service = ShortcutService(execute: { args, timeout in
            XCTAssertEqual(args, ["list", "--show-identifiers"])
            XCTAssertEqual(timeout, 10)
            throw FixtureFailure.failed
        })
        do { _ = try await service.list(); XCTFail("应报告执行失败") } catch { }
    }

    func testProcessRunnerReportsNonzeroExitAndBoundsTimeAndOutput() async throws {
        do {
            _ = try await ShortcutProcess.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], timeout: 1)
            XCTFail("非零退出未报错")
        } catch ShortcutError.failed { } catch { XCTFail("错误类别不符：\(error)") }
        let started = ContinuousClock.now
        do {
            _ = try await ShortcutProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["2"], timeout: 0.03)
            XCTFail("超时未报错")
        } catch ShortcutError.timedOut { } catch { XCTFail("错误类别不符：\(error)") }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1))
        do {
            _ = try await ShortcutProcess.run(executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: [], timeout: 1, outputLimit: 1024)
            XCTFail("超量输出未报错")
        } catch ShortcutError.tooMuchOutput { } catch { XCTFail("错误类别不符：\(error)") }
    }
}
