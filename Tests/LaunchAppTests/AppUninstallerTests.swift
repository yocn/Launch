import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
final class AppUninstallerTests: XCTestCase {
    private func makeUninstaller(root: URL, recorder: TrashRecorder = TrashRecorder()) -> AppUninstaller {
        var uninstaller = AppUninstaller()
        uninstaller.roots = [root]
        uninstaller.ownBundlePath = "/nonexistent/Launch.app"
        uninstaller.quitTimeout = 0.3
        uninstaller.runningApplications = { [] }
        uninstaller.trash = { url in
            if let failure = recorder.failure {
                throw failure
            }
            recorder.urls.append(url)
        }
        return uninstaller
    }

    func testWritableAppUnderRootIsUninstallable() throws {
        let root = try makeTemporaryDirectory()
        let app = try makeFakeApp(named: "Foo", in: root)

        XCTAssertTrue(makeUninstaller(root: root).canUninstall(app))
    }

    func testSystemOutsideOwnAndSymlinkAppsAreNot() throws {
        let root = try makeTemporaryDirectory()
        let other = try makeTemporaryDirectory()
        let app = try makeFakeApp(named: "Foo", in: root)
        let outside = try makeFakeApp(named: "Bar", in: other)
        let link = root.appending(path: "Link.app")
        try FileManager.default.createSymbolicLink(atPath: link.path(percentEncoded: false), withDestinationPath: app.identity.path)
        var uninstaller = makeUninstaller(root: root)

        XCTAssertFalse(uninstaller.canUninstall(CatalogApp(
            identity: AppIdentity(bundleIdentifier: nil, path: "/System/Applications/Calculator.app"),
            displayName: "计算器"
        )))
        XCTAssertFalse(uninstaller.canUninstall(outside))
        XCTAssertFalse(uninstaller.canUninstall(CatalogApp(
            identity: AppIdentity(bundleIdentifier: nil, path: link.path(percentEncoded: false)),
            displayName: "Link"
        )))
        uninstaller.ownBundlePath = app.identity.path
        XCTAssertFalse(uninstaller.canUninstall(app))
    }

    func testReadOnlyAppIsNotUninstallable() throws {
        let root = try makeTemporaryDirectory()
        let app = try makeFakeApp(named: "Foo", in: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: app.identity.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.identity.path)
        }

        XCTAssertFalse(makeUninstaller(root: root).canUninstall(app))
    }

    func testRunningInstanceMatchesPathOrBundleIdentifier() throws {
        let root = try makeTemporaryDirectory()
        let app = try makeFakeApp(named: "Foo", in: root, bundleIdentifier: "com.example.foo")
        var uninstaller = makeUninstaller(root: root)
        let byPath = FakeRunningApp(bundleIdentifier: nil, bundlePath: app.identity.path + "/")
        let byID = FakeRunningApp(bundleIdentifier: "com.example.foo", bundlePath: "/Elsewhere/Foo.app")
        let unrelated = FakeRunningApp(bundleIdentifier: "com.example.bar", bundlePath: "/Applications/Bar.app")

        uninstaller.runningApplications = { [unrelated, byPath] }
        XCTAssertTrue(uninstaller.runningInstance(of: app) === byPath)
        uninstaller.runningApplications = { [unrelated, byID] }
        XCTAssertTrue(uninstaller.runningInstance(of: app) === byID)
        uninstaller.runningApplications = { [unrelated] }
        XCTAssertNil(uninstaller.runningInstance(of: app))
    }

    func testQuitWaitsForTerminationAndTimesOut() async throws {
        let root = try makeTemporaryDirectory()
        let uninstaller = makeUninstaller(root: root)
        let quits = FakeRunningApp(bundleIdentifier: "a", bundlePath: nil)
        let stays = FakeRunningApp(bundleIdentifier: "b", bundlePath: nil, quitsWhenAsked: false)

        let didQuit = await uninstaller.quit(quits)
        let didStay = await uninstaller.quit(stays)

        XCTAssertTrue(didQuit)
        XCTAssertEqual(quits.terminateCalls, 1)
        XCTAssertFalse(didStay)
    }

    func testMoveToTrashUsesInjectedTrashAndRefusesUnsafeApps() throws {
        let root = try makeTemporaryDirectory()
        let app = try makeFakeApp(named: "Foo", in: root)
        let recorder = TrashRecorder()
        let uninstaller = makeUninstaller(root: root, recorder: recorder)

        try uninstaller.moveToTrash(app)
        XCTAssertEqual(recorder.urls, [URL(fileURLWithPath: app.identity.path)])

        let system = CatalogApp(identity: AppIdentity(bundleIdentifier: nil, path: "/System/Applications/Calculator.app"), displayName: "计算器")
        XCTAssertThrowsError(try uninstaller.moveToTrash(system)) { error in
            XCTAssertEqual(error as? UninstallError, .notAllowed)
        }
        XCTAssertEqual(recorder.urls.count, 1)
    }
}
