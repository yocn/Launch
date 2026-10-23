import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor private final class ActivationPresenter: LauncherPresenting {
    var isVisible = false
    var restored: [Bool] = []
    func present() { isVisible = true }
    func dismiss(restoringPreviousApp: Bool) { isVisible = false; restored.append(restoringPreviousApp) }
}

private actor ControlledShortcutRun {
    var calls: [[String]] = []
    var continuation: CheckedContinuation<String, any Error>?
    func execute(_ arguments: [String]) async throws -> String {
        if arguments.first == "list" { return "测试指令 (88888888-8888-8888-8888-888888888888)" }
        calls.append(arguments)
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilRunning() async {
        while continuation == nil { await Task.yield() }
    }
    func fail() { continuation?.resume(throwing: ShortcutError.failed("受控错误")); continuation = nil }
    func count() -> Int { calls.count }
    func arguments() -> [[String]] { calls }
}

@MainActor final class LaunchItemActivationTests: XCTestCase {
    func testDispatchUsesTypedTargetsAndNeverTreatsEntriesAsApplicationPaths() {
        let presenter = ActivationPresenter()
        var applications: [URL] = [], websites: [URL] = [], shortcuts: [UUID] = []
        let controller = LauncherController(model: LauncherModel(), presenter: presenter, iconCache: IconCache { _, _ in },
                                            openApplication: { applications.append($0) })
        controller.onOpenWebsite = { websites.append($0) }
        controller.onRunShortcut = { shortcuts.append($0) }
        let url = URL(string: "https://example.com/docs")!
        let id = UUID()
        let website = LaunchItem(definition: ExtraItemDefinition(name: "文档", target: .website(url)))
        let shortcut = LaunchItem(definition: ExtraItemDefinition(name: "测试", target: .shortcut(id)))
        controller.show()
        controller.launch(website)
        XCTAssertEqual(websites, [url])
        XCTAssertTrue(applications.isEmpty)
        XCTAssertTrue(shortcuts.isEmpty)
        XCTAssertEqual(presenter.restored, [false])
        controller.show()
        controller.launch(shortcut)
        XCTAssertEqual(shortcuts, [id])
        XCTAssertTrue(applications.isEmpty)
        controller.show()
        controller.launch(LaunchItem(definition: ExtraItemDefinition(name: "失效", target: .shortcut(UUID())), unavailableReason: "已删除"))
        XCTAssertTrue(presenter.isVisible)
        XCTAssertEqual(shortcuts.count, 1)
        XCTAssertEqual(websites.count, 1)
    }

    func testShortcutDuplicateClickDoesNotStartAnotherRunAndFailureDoesNotRetry() async throws {
        let root = try makeTemporaryDirectory()
        let store = LayoutStore(fileURL: root.appendingPathComponent("layout.json"))
        try store.save(LayoutDocument())
        let layout = LayoutCoordinator(store: store, launchpad: NoEntryLaunchpad(), prompter: EntryPrompter())
        layout.start()
        await layout.catalogDidChange([])
        let process = ControlledShortcutRun()
        let extras = ExtraItemsController(layout: layout, shortcuts: ShortcutService(execute: { args, _ in try await process.execute(args) }), fetchIcon: { _ in nil })
        await extras.refreshShortcuts()
        let id = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let first = Task { try await extras.runShortcut(id: id) }
        await process.waitUntilRunning()
        XCTAssertEqual(extras.runningShortcuts, [id])
        let duplicated = try await extras.runShortcut(id: id)
        XCTAssertFalse(duplicated)
        let arguments = await process.arguments()
        XCTAssertEqual(arguments, [["run", id.uuidString]])
        await process.fail()
        do { _ = try await first.value; XCTFail("应报告运行失败") } catch {}
        XCTAssertTrue(extras.runningShortcuts.isEmpty)
        let count = await process.count()
        XCTAssertEqual(count, 1, "失败不能自动重试")
        XCTAssertEqual(extras.items.count, 1, "失败不删除条目")
        do { _ = try await extras.runShortcut(id: UUID()); XCTFail("未知指令不能执行") } catch {}
        let finalCount = await process.count()
        XCTAssertEqual(finalCount, 1)
    }
}
