import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
private final class FakeUninstallPrompter: UninstallPrompting {
    var answer = true
    private(set) var confirmations: [String] = []
    private(set) var errors: [String] = []
    var reviewedPlans: [ResidualPlan] = []
    var results: [UninstallCleanupResult] = []

    func reviewCleanup(_ plan: ResidualPlan, isRunning: Bool) -> Set<String>? {
        reviewedPlans.append(plan)
        return confirmUninstall(appName: plan.app.displayName, isRunning: isRunning) ? [] : nil
    }

    func showCleanupResult(_ result: UninstallCleanupResult) { results.append(result) }

    func confirmUninstall(appName: String, isRunning: Bool) -> Bool {
        confirmations.append("\(appName)|\(isRunning)")
        return answer
    }

    func showUninstallError(_ message: String) {
        errors.append(message)
    }
}

@MainActor
final class UninstallCoordinatorTests: XCTestCase {
    private struct Setup {
        let app: CatalogApp
        let recorder: TrashRecorder
        let prompter: FakeUninstallPrompter
        let coordinator: UninstallCoordinator
        let removals: () -> Int
        let root: URL
    }

    private func makeSetup(running: [any RunningAppHandle] = [], cleanup: Bool = false) throws -> Setup {
        let root = try makeTemporaryDirectory()
        let app = try makeFakeApp(named: "Foo", in: root, bundleIdentifier: "com.example.foo")
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.foo"], format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: app.identity.path).appending(path: "Contents/Info.plist"))
        let recorder = TrashRecorder()
        var uninstaller = AppUninstaller()
        uninstaller.roots = [root]
        uninstaller.ownBundlePath = "/nonexistent/Launch.app"
        uninstaller.quitTimeout = 0.3
        uninstaller.runningApplications = { running }
        uninstaller.trash = { url in
            if let failure = recorder.failure {
                throw failure
            }
            recorder.urls.append(url)
        }
        let prompter = FakeUninstallPrompter()
        var removals = 0
        let service = UninstallCleanup(scanner: ResidualScanner(home: root, applicationRoots: [root]),
                                       recordDirectory: root.appending(path: "Records"), trash: { _ in nil })
        let coordinator = UninstallCoordinator(uninstaller: uninstaller, prompter: prompter,
                                              makeCleanup: cleanup ? { service } : nil) { removals += 1 }
        return Setup(app: app, recorder: recorder, prompter: prompter, coordinator: coordinator, removals: { removals }, root: root)
    }

    func testCancelLeavesAppInPlace() async throws {
        let setup = try makeSetup()
        setup.prompter.answer = false

        await setup.coordinator.uninstall(setup.app)

        XCTAssertEqual(setup.prompter.confirmations, ["Foo|false"])
        XCTAssertTrue(setup.recorder.urls.isEmpty)
        XCTAssertEqual(setup.removals(), 0)
    }

    func testRunningAppThatDoesNotQuitIsKept() async throws {
        let running = FakeRunningApp(bundleIdentifier: "com.example.foo", bundlePath: nil, quitsWhenAsked: false)
        let setup = try makeSetup(running: [running])

        await setup.coordinator.uninstall(setup.app)

        XCTAssertEqual(setup.prompter.confirmations, ["Foo|true"])
        XCTAssertEqual(running.terminateCalls, 1)
        XCTAssertTrue(setup.recorder.urls.isEmpty)
        XCTAssertEqual(setup.prompter.errors.count, 1)
    }

    func testRunningAppQuitsThenMovesToTrash() async throws {
        let running = FakeRunningApp(bundleIdentifier: "com.example.foo", bundlePath: nil)
        let setup = try makeSetup(running: [running])

        await setup.coordinator.uninstall(setup.app)

        XCTAssertEqual(setup.recorder.urls.count, 1)
        XCTAssertEqual(setup.removals(), 1)
        XCTAssertTrue(setup.prompter.errors.isEmpty)
    }

    func testTrashFailureIsReported() async throws {
        let setup = try makeSetup()
        setup.recorder.failure = CocoaError(.fileWriteNoPermission)

        await setup.coordinator.uninstall(setup.app)

        XCTAssertEqual(setup.removals(), 0)
        XCTAssertEqual(setup.prompter.errors.count, 1)
    }

    func testCleanupCancelDoesNotQuitOrCreateRecords() async throws {
        let running = FakeRunningApp(bundleIdentifier: "com.example.foo", bundlePath: nil)
        let setup = try makeSetup(running: [running], cleanup: true)
        setup.prompter.answer = false
        await setup.coordinator.uninstall(setup.app)
        XCTAssertEqual(setup.prompter.reviewedPlans.count, 1)
        XCTAssertEqual(running.terminateCalls, 0)
        XCTAssertTrue(setup.prompter.results.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.root.appending(path: "Records").path))
    }

    func testCleanupQuitFailureDoesNotCreateRecords() async throws {
        let running = FakeRunningApp(bundleIdentifier: "com.example.foo", bundlePath: nil, quitsWhenAsked: false)
        let setup = try makeSetup(running: [running], cleanup: true)
        await setup.coordinator.uninstall(setup.app)
        XCTAssertEqual(setup.prompter.errors.count, 1)
        XCTAssertEqual(setup.removals(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.root.appending(path: "Records").path))
    }

    func testConcurrentCleanupRequestsOnlyOpenOneReview() async throws {
        let setup = try makeSetup(cleanup: true)
        setup.prompter.answer = false
        let coordinator = setup.coordinator
        let app = setup.app
        let first = Task { @MainActor in await coordinator.uninstall(app) }
        let second = Task { @MainActor in await coordinator.uninstall(app) }
        await first.value
        await second.value
        XCTAssertEqual(setup.prompter.reviewedPlans.count, 1)
    }
}
