import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
private final class FakeUninstallPrompter: UninstallPrompting {
    var answer = true
    private(set) var confirmations: [String] = []
    private(set) var errors: [String] = []

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
    }

    private func makeSetup(running: [any RunningAppHandle] = []) throws -> Setup {
        let root = try makeTemporaryDirectory()
        let app = try makeFakeApp(named: "Foo", in: root, bundleIdentifier: "com.example.foo")
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
        let coordinator = UninstallCoordinator(uninstaller: uninstaller, prompter: prompter) { removals += 1 }
        return Setup(app: app, recorder: recorder, prompter: prompter, coordinator: coordinator, removals: { removals })
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
}
