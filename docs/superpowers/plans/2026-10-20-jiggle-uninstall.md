# 抖动模式与卸载 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 长按图标进入抖动模式，可直接删除的应用显示 ×，确认后移到废纸篓。

**Architecture:** `AppUninstaller` 负责可卸载判定、运行检测、退出等待与移到废纸篓（文件系统、运行中应用、废纸篓操作均可注入）；`UninstallCoordinator` 串起确认、退出、删除与重新扫描；`LauncherModel` 持有抖动状态与 × 命中；`ItemDragController` 增加长按计时与 × 的按下/松开；视图用 `phaseAnimator` 摇摆并叠加 × 按钮。

**Tech Stack:** Swift 6，AppKit（`NSAlert`、`NSRunningApplication`、`FileManager.trashItem`），SwiftUI，XCTest。

**Spec:** `docs/superpowers/specs/2026-10-20-jiggle-uninstall-design.md`

---

## 文件结构

| 文件 | 动作 | 职责 |
| --- | --- | --- |
| `Sources/LaunchApp/AppUninstaller.swift` | 新建 | `RunningAppHandle`、`UninstallError`、`AppUninstaller` |
| `Sources/LaunchApp/UninstallCoordinator.swift` | 新建 | `UninstallPrompting`、`UninstallCoordinator`、`AlertUninstallPrompter` |
| `Tests/LaunchAppTests/AppUninstallerTests.swift` | 新建 | 判定、运行检测、退出等待、移到废纸篓 |
| `Tests/LaunchAppTests/UninstallCoordinatorTests.swift` | 新建 | 卸载流程 |
| `Tests/LaunchAppTests/TestFixtures.swift` | 修改 | `FakeRunningApp`、`TrashRecorder`、`makeFakeApp` |
| `Sources/LaunchApp/LauncherHomeLayout.swift` | 修改 | × 按钮尺寸与位置 |
| `Sources/LaunchApp/LauncherModel.swift` | 修改 | `isJiggling`、进入/退出、Esc 层次、× 命中 |
| `Tests/LaunchAppTests/LauncherModelJiggleTests.swift` | 新建 | 模型抖动 |
| `Sources/LaunchApp/LauncherController.swift` | 修改 | 抖动时不启动；点空白先退出抖动 |
| `Tests/LaunchAppTests/LauncherControllerTests.swift` | 修改 | 对应测试 |
| `Sources/LaunchApp/ItemDragController.swift` | 修改 | 长按、× 按下松开 |
| `Sources/LaunchApp/CatalogWatcher.swift` | 修改 | `rescan()` 去掉 `private` |
| `Sources/LaunchApp/LaunchApp.swift` | 修改 | 组装 |
| `Sources/LaunchApp/LauncherView.swift` | 修改 | 摇摆与 × 按钮 |

命令（项目根目录）：`swift build 2>&1 | grep -E "error:|warning:|Build complete"`；`swift test 2>&1 | grep -E "error: -|Executed .* tests"`；`swift test --filter <类名>`；安装 `LAUNCH_SIGN_IDENTITY="Apple Development: zhaoyingkun@163.com" ./scripts/build-app.sh --install`。

---

### Task 1: AppUninstaller

**Files:**
- Create: `Sources/LaunchApp/AppUninstaller.swift`
- Modify: `Tests/LaunchAppTests/TestFixtures.swift`
- Test: `Tests/LaunchAppTests/AppUninstallerTests.swift`

- [ ] **Step 1: 测试辅助**（追加到 `TestFixtures.swift`，并在文件顶部 `import XCTest` 之后加 `@testable import LaunchApp`）

```swift
final class FakeRunningApp: RunningAppHandle {
    let bundleIdentifier: String?
    let bundlePath: String?
    private let quitsWhenAsked: Bool
    private(set) var terminateCalls = 0

    init(bundleIdentifier: String?, bundlePath: String?, quitsWhenAsked: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.quitsWhenAsked = quitsWhenAsked
    }

    var isTerminated: Bool {
        quitsWhenAsked && terminateCalls > 0
    }

    func terminate() -> Bool {
        terminateCalls += 1
        return true
    }
}

final class TrashRecorder {
    var urls: [URL] = []
    var failure: Error?
}

func makeFakeApp(named name: String, in root: URL, bundleIdentifier: String? = nil) throws -> CatalogApp {
    let url = root.appending(path: "\(name).app/Contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let path = root.appending(path: "\(name).app").path(percentEncoded: false)
    return CatalogApp(
        identity: AppIdentity(bundleIdentifier: bundleIdentifier, path: path.hasSuffix("/") ? String(path.dropLast()) : path),
        displayName: name
    )
}
```

- [ ] **Step 2: 写失败测试**

```swift
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
```

- [ ] **Step 3: 运行确认失败**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find type 'RunningAppHandle' in scope`。

- [ ] **Step 4: 实现**

```swift
import AppKit
import LaunchCore

protocol RunningAppHandle: AnyObject {
    var bundleIdentifier: String? { get }
    var bundlePath: String? { get }
    var isTerminated: Bool { get }
    func terminate() -> Bool
}

extension NSRunningApplication: RunningAppHandle {
    var bundlePath: String? {
        bundleURL?.path(percentEncoded: false)
    }
}

enum UninstallError: LocalizedError, Equatable {
    case notAllowed

    var errorDescription: String? {
        "该应用不能直接移到废纸篓"
    }
}

@MainActor
struct AppUninstaller {
    var roots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
    ]
    var ownBundlePath = Bundle.main.bundleURL.path(percentEncoded: false)
    var fileManager = FileManager.default
    var quitTimeout: TimeInterval = 5
    var runningApplications: () -> [any RunningAppHandle] = { NSWorkspace.shared.runningApplications }
    var trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    // 只允许当前用户能直接移动的应用；系统应用、符号链接入口和需要管理员权限的都不行
    func canUninstall(_ app: CatalogApp) -> Bool {
        let path = Self.normalized(app.identity.path)
        guard path.hasSuffix(".app"),
              !path.hasPrefix("/System/"),
              path != Self.normalized(ownBundlePath),
              roots.contains(where: { path.hasPrefix(Self.normalized($0.path(percentEncoded: false)) + "/") }),
              let attributes = try? fileManager.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
            return false
        }
        let parent = (path as NSString).deletingLastPathComponent
        return fileManager.isWritableFile(atPath: path) && fileManager.isWritableFile(atPath: parent)
    }

    func runningInstance(of app: CatalogApp) -> (any RunningAppHandle)? {
        let path = Self.normalized(app.identity.path)
        return runningApplications().first { running in
            if let bundlePath = running.bundlePath, Self.normalized(bundlePath) == path {
                return true
            }
            guard let bundleIdentifier = app.identity.bundleIdentifier else {
                return false
            }
            return running.bundleIdentifier == bundleIdentifier
        }
    }

    func quit(_ running: any RunningAppHandle) async -> Bool {
        if !running.isTerminated {
            _ = running.terminate()
        }
        let deadline = Date().addingTimeInterval(quitTimeout)
        while !running.isTerminated, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return running.isTerminated
    }

    func moveToTrash(_ app: CatalogApp) throws {
        guard canUninstall(app) else {
            throw UninstallError.notAllowed
        }
        try trash(URL(fileURLWithPath: app.identity.path))
    }

    private static func normalized(_ path: String) -> String {
        (path as NSString).standardizingPath
    }
}
```

- [ ] **Step 5: 运行确认通过**

Run: `swift test --filter AppUninstallerTests 2>&1 | grep -E "error: -|Executed"`
Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 6: 提交**

```bash
git add Sources/LaunchApp/AppUninstaller.swift Tests/LaunchAppTests/AppUninstallerTests.swift Tests/LaunchAppTests/TestFixtures.swift
git commit -m "feat(卸载): 添加应用卸载判定与移到废纸篓"
```

---

### Task 2: UninstallCoordinator 与确认框

**Files:**
- Create: `Sources/LaunchApp/UninstallCoordinator.swift`
- Test: `Tests/LaunchAppTests/UninstallCoordinatorTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
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
```

- [ ] **Step 2: 运行确认失败**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find type 'UninstallPrompting' in scope`。

- [ ] **Step 3: 实现**

```swift
import AppKit
import LaunchCore

@MainActor
protocol UninstallPrompting: AnyObject {
    func confirmUninstall(appName: String, isRunning: Bool) -> Bool
    func showUninstallError(_ message: String)
}

@MainActor
final class UninstallCoordinator {
    private let uninstaller: AppUninstaller
    private let prompter: UninstallPrompting
    private let onRemoved: () -> Void

    init(uninstaller: AppUninstaller, prompter: UninstallPrompting, onRemoved: @escaping () -> Void) {
        self.uninstaller = uninstaller
        self.prompter = prompter
        self.onRemoved = onRemoved
    }

    func canUninstall(_ app: CatalogApp) -> Bool {
        uninstaller.canUninstall(app)
    }

    func uninstall(_ app: CatalogApp) async {
        guard uninstaller.canUninstall(app) else {
            return
        }
        let running = uninstaller.runningInstance(of: app)
        guard prompter.confirmUninstall(appName: app.displayName, isRunning: running != nil) else {
            return
        }
        if let running {
            let didQuit = await uninstaller.quit(running)
            guard didQuit else {
                prompter.showUninstallError("“\(app.displayName)”没有退出，未移到废纸篓。")
                return
            }
        }
        do {
            try uninstaller.moveToTrash(app)
            onRemoved()
        } catch {
            prompter.showUninstallError("无法将“\(app.displayName)”移到废纸篓：\(error.localizedDescription)")
        }
    }
}

@MainActor
final class AlertUninstallPrompter: UninstallPrompting {
    func confirmUninstall(appName: String, isRunning: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = isRunning ? "“\(appName)”正在运行" : "要将“\(appName)”移到废纸篓吗？"
        alert.informativeText = isRunning ? "退出后移到废纸篓，可以在废纸篓中恢复。" : "可以在废纸篓中恢复。"
        alert.addButton(withTitle: isRunning ? "退出并移到废纸篓" : "移到废纸篓")
        alert.addButton(withTitle: "取消")
        return Self.run(alert) == .alertFirstButtonReturn
    }

    func showUninstallError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "卸载失败"
        alert.informativeText = message
        _ = Self.run(alert)
    }

    // 启动器面板在 statusBar 层级，提示框要更高才不会被挡住
    private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        return alert.runModal()
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter UninstallCoordinatorTests 2>&1 | grep -E "error: -|Executed"`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/UninstallCoordinator.swift Tests/LaunchAppTests/UninstallCoordinatorTests.swift
git commit -m "feat(卸载): 卸载流程与确认提示"
```

---

### Task 3: 模型抖动状态与 × 命中

**Files:**
- Modify: `Sources/LaunchApp/LauncherHomeLayout.swift`
- Modify: `Sources/LaunchApp/LauncherModel.swift`
- Test: `Tests/LaunchAppTests/LauncherModelJiggleTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import CoreGraphics
import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelJiggleTests: XCTestCase {
    private let layout = LauncherHomeLayout(
        screenSize: LauncherHomeLayout.canvasSize,
        referenceSize: LauncherHomeLayout.canvasSize
    )

    private var gridFrame: CGRect {
        CGRect(x: 0, y: 135, width: layout.contentSize.width, height: layout.gridHeight)
    }

    private func tile(_ index: Int) -> CGRect {
        GridHitTester(layout: layout, frame: gridFrame).tileRect(index)
    }

    @MainActor
    private func makeModel(apps: [CatalogApp], pages: [[ResolvedItem]]) -> LauncherModel {
        let model = LauncherModel(apps: apps)
        model.updateLayout(pages)
        model.canEditLayout = true
        model.updateHomeLayout(layout)
        model.updateGridFrame(gridFrame)
        return model
    }

    @MainActor
    func testJigglingNeedsEditableLayoutWithoutSearch() {
        let apps = makeApps(count: 3)
        let model = makeModel(apps: apps, pages: [apps.map(ResolvedItem.app)])

        model.canEditLayout = false
        model.beginJiggling()
        XCTAssertFalse(model.isJiggling)

        model.canEditLayout = true
        model.setQuery("App")
        model.beginJiggling()
        XCTAssertFalse(model.isJiggling)

        model.setQuery("")
        model.beginJiggling()
        XCTAssertTrue(model.isJiggling)
    }

    @MainActor
    func testEscapeClosesFolderThenStopsJigglingThenCloses() {
        let apps = makeApps(count: 3)
        let model = makeModel(apps: apps, pages: [[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.showFolder(id: "f")
        model.beginJiggling()

        XCTAssertEqual(model.handleEscape(), .closedFolder)
        XCTAssertTrue(model.isJiggling)
        XCTAssertEqual(model.handleEscape(), .stoppedJiggling)
        XCTAssertFalse(model.isJiggling)
        XCTAssertEqual(model.handleEscape(), .close)
    }

    @MainActor
    func testTypingAndPresentingStopJiggling() {
        let apps = makeApps(count: 3)
        let model = makeModel(apps: apps, pages: [apps.map(ResolvedItem.app)])

        model.beginJiggling()
        model.setQuery("App")
        XCTAssertFalse(model.isJiggling)

        model.setQuery("")
        model.beginJiggling()
        model.prepareForPresentation()
        XCTAssertFalse(model.isJiggling)
    }

    @MainActor
    func testUninstallTargetOnlyOnBadgeOfUninstallableAppWhileJiggling() {
        let apps = makeApps(count: 3)
        let model = makeModel(apps: apps, pages: [apps.map(ResolvedItem.app)])
        model.canUninstall = { $0 == apps[1] }
        let badge = layout.uninstallBadgeFrame(inTile: tile(1))
        let badgeCenter = CGPoint(x: badge.midX, y: badge.midY)

        XCTAssertNil(model.uninstallTarget(at: badgeCenter))

        model.beginJiggling()
        XCTAssertEqual(model.uninstallTarget(at: badgeCenter), apps[1])
        let otherBadge = layout.uninstallBadgeFrame(inTile: tile(0))
        XCTAssertNil(model.uninstallTarget(at: CGPoint(x: otherBadge.midX, y: otherBadge.midY)))
        XCTAssertNil(model.uninstallTarget(at: CGPoint(x: tile(1).midX, y: tile(1).midY)))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected: `value of type 'LauncherModel' has no member 'beginJiggling'`。

- [ ] **Step 3: 实现**

`LauncherHomeLayout.swift`，在 `folderTitleSpacing` 之后加：

```swift
    var uninstallBadgeSide: CGFloat { iconSide * 0.3 }

    func uninstallBadgeFrame(inTile tile: CGRect) -> CGRect {
        let side = uninstallBadgeSide
        return CGRect(
            x: tile.midX - iconSide / 2 - side * 0.2,
            y: tile.minY + tilePadding - side * 0.2,
            width: side,
            height: side
        )
    }
```

`LauncherModel.swift`：

- `EscapeOutcome` 在 `case closedFolder` 之后加 `case stoppedJiggling`。
- 在 `private(set) var landing: Landing?` 之后加 `private(set) var isJiggling = false`。
- 在 `@ObservationIgnored var canEditLayout = false` 之后加 `@ObservationIgnored var canUninstall: (CatalogApp) -> Bool = { _ in false }`。
- 在 `func cancelRenamingFolder()` 之后加：

```swift
    func beginJiggling() {
        guard canDragItems else {
            return
        }
        isJiggling = true
    }

    func endJiggling() {
        isJiggling = false
    }

    func uninstallTarget(at point: CGPoint) -> CatalogApp? {
        guard isJiggling,
              let homeLayout,
              let press = itemPress(at: point),
              case .app(let app) = press.item,
              canUninstall(app),
              let tile = frame(of: press.origin) else {
            return nil
        }
        return homeLayout.uninstallBadgeFrame(inTile: tile).insetBy(dx: -6, dy: -6).contains(point) ? app : nil
    }
```

- `setQuery` 的 `} else {` 分支第一行加 `isJiggling = false`。
- `prepareForPresentation()` 第一行加 `isJiggling = false`。
- `handleEscape()` 在 `guard !query.isEmpty else {` 之前加：

```swift
        if isJiggling {
            endJiggling()
            return .stoppedJiggling
        }
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test 2>&1 | grep -E "error: -|Executed .* tests"` → 0 failures。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/LauncherHomeLayout.swift Sources/LaunchApp/LauncherModel.swift Tests/LaunchAppTests/LauncherModelJiggleTests.swift
git commit -m "feat(编辑): 模型支持抖动状态与卸载按钮命中"
```

---

### Task 4: 控制器 —— 抖动时不启动、点空白先退出抖动

**Files:**
- Modify: `Sources/LaunchApp/LauncherController.swift`
- Test: `Tests/LaunchAppTests/LauncherControllerTests.swift`

- [ ] **Step 1: 写失败测试**（追加到 `LauncherControllerTests`，放在 `@MainActor private func makeController(` 之前）

```swift
    @MainActor
    func testBackgroundClickStopsJigglingBeforeClosing() {
        let apps = makeApps(count: 3)
        let (controller, presenter) = makeController(apps: apps)
        controller.show()
        controller.model.updateLayout([apps.map(ResolvedItem.app)])
        controller.model.canEditLayout = true
        controller.model.beginJiggling()

        controller.handleBackgroundClick()
        XCTAssertFalse(controller.model.isJiggling)
        XCTAssertTrue(presenter.isVisible)

        controller.handleBackgroundClick()
        XCTAssertFalse(presenter.isVisible)
    }

    @MainActor
    func testLaunchIsIgnoredWhileJiggling() {
        let apps = makeApps(count: 3)
        var opened: [URL] = []
        let (controller, presenter) = makeController(apps: apps, openApplication: { url in
            opened.append(url)
            return true
        })
        controller.show()
        controller.model.updateLayout([apps.map(ResolvedItem.app)])
        controller.model.canEditLayout = true
        controller.model.beginJiggling()

        controller.launch(apps[0])

        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(presenter.isVisible)
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LauncherControllerTests 2>&1 | grep -E "error: -|Executed"`
Expected: 两个新测试失败。

- [ ] **Step 3: 实现**

```swift
    func handleBackgroundClick() {
        if model.openFolderID != nil {
            model.closeFolder()
        } else if model.isJiggling {
            model.endJiggling()
        } else {
            hide(.backgroundClick)
        }
    }
```

```swift
    func launch(_ app: CatalogApp) {
        guard !model.isJiggling, openApplication(URL(fileURLWithPath: app.identity.path)) else {
            return
        }
        hide(.launchedApp)
    }
```

- [ ] **Step 4: 运行确认通过并提交**

Run: `swift test 2>&1 | grep -E "error: -|Executed .* tests"` → 0 failures

```bash
git add Sources/LaunchApp/LauncherController.swift Tests/LaunchAppTests/LauncherControllerTests.swift
git commit -m "feat(编辑): 抖动时点应用不启动，点空白先退出抖动"
```

---

### Task 5: 长按、× 点击与组装

**Files:**
- Modify: `Sources/LaunchApp/ItemDragController.swift`
- Modify: `Sources/LaunchApp/CatalogWatcher.swift`
- Modify: `Sources/LaunchApp/LaunchApp.swift`

- [ ] **Step 1: ItemDragController**

文件头注释改为 `// 图标上的鼠标事件全部由这里接管：点击自行执行，长按进入抖动，移动超过阈值即发起系统拖拽会话`。

属性区：`private static let dragThreshold: CGFloat = 4` 之后加 `private static let longPressDuration: TimeInterval = 0.5`；`private let onActivate: (ResolvedItem) -> Void` 之后加 `private let onUninstall: (CatalogApp) -> Void`；`private var press: LauncherModel.ItemPress?` 之后加：

```swift
    private var badgePress: CatalogApp?
    private var didLongPress = false
    private var longPressTimer: Timer?
```

`init` 增加参数 `onUninstall: @escaping (CatalogApp) -> Void,`（放在 `onActivate` 之后）并赋值 `self.onUninstall = onUninstall`。

`mouseDown`、`mouseDragged`、`mouseUp` 替换为：

```swift
    private func mouseDown(_ event: NSEvent) -> NSEvent? {
        press = nil
        badgePress = nil
        cancelLongPress()
        guard let point = globalPoint(of: event) else {
            return event
        }
        if let app = model.uninstallTarget(at: point) {
            badgePress = app
            return nil
        }
        guard let hit = model.itemPress(at: point) else {
            return event
        }
        press = hit
        pressPoint = point
        didLongPress = false
        startLongPress()
        return nil
    }

    private func mouseDragged(_ event: NSEvent) -> NSEvent? {
        if badgePress != nil {
            return nil
        }
        guard let press else {
            return event
        }
        guard let point = globalPoint(of: event),
              hypot(point.x - pressPoint.x, point.y - pressPoint.y) > Self.dragThreshold else {
            return nil
        }
        // 拖拽被 Esc 取消后仍会收到松开事件，提前清掉点击候选
        self.press = nil
        cancelLongPress()
        if model.canDragItems {
            beginSession(press, event: event)
        }
        return nil
    }

    private func mouseUp(_ event: NSEvent) -> NSEvent? {
        if let app = badgePress {
            badgePress = nil
            onUninstall(app)
            return nil
        }
        guard let press else {
            return event
        }
        self.press = nil
        cancelLongPress()
        if !didLongPress {
            onActivate(press.item)
        }
        return nil
    }

    private func startLongPress() {
        let timer = Timer(timeInterval: Self.longPressDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.longPressFired()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        longPressTimer = timer
    }

    private func longPressFired() {
        longPressTimer = nil
        guard press != nil, model.canDragItems else {
            return
        }
        didLongPress = true
        model.beginJiggling()
    }

    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
```

- [ ] **Step 2: CatalogWatcher**

`private func rescan()` 改为 `func rescan()`。

- [ ] **Step 3: LaunchApp 组装**

在 `private lazy var itemDragController = ItemDragController(` 之前加：

```swift
    private lazy var uninstallCoordinator = UninstallCoordinator(
        uninstaller: AppUninstaller(),
        prompter: AlertUninstallPrompter(),
        onRemoved: { [weak self] in self?.catalogWatcher?.rescan() }
    )
```

`itemDragController` 构造在 `onActivate:` 之后加 `onUninstall: { [weak self] app in self?.uninstall(app) },`。

在 `controller.onUndoLayoutEdit = { ... }` 之后加：

```swift
        controller.model.canUninstall = { [weak self] app in
            self?.uninstallCoordinator.canUninstall(app) ?? false
        }
```

在 `private func activate(_ item: ResolvedItem)` 之前加：

```swift
    private func uninstall(_ app: CatalogApp) {
        Task {
            await uninstallCoordinator.uninstall(app)
        }
    }
```

- [ ] **Step 4: 构建、测试、提交**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete"` → `Build complete!`，无警告
Run: `swift test 2>&1 | grep -E "error: -|Executed .* tests"` → 0 failures

```bash
git add Sources/LaunchApp/ItemDragController.swift Sources/LaunchApp/CatalogWatcher.swift Sources/LaunchApp/LaunchApp.swift
git commit -m "feat(编辑): 长按图标进入抖动，点 × 卸载应用"
```

---

### Task 6: 界面 —— 摇摆与 × 按钮

**Files:**
- Modify: `Sources/LaunchApp/LauncherView.swift`

- [ ] **Step 1: GridCell 叠加 × 与摇摆**

在 `GridCell` 的 `.item` 分支，`.modifier(LandingModifier(...))` 之后加：

```swift
                .overlay(alignment: .topLeading) {
                    let showsBadge = showsUninstallBadge(for: item)
                    ZStack {
                        if showsBadge {
                            UninstallBadge(layout: layout)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.55), value: showsBadge)
                }
                .modifier(JiggleModifier(isActive: model.isJiggling, seed: entry.id.hashValue))
```

在 `GridCell` 的 `body` 之后加：

```swift
    private func showsUninstallBadge(for item: ResolvedItem) -> Bool {
        guard model.isJiggling, case .app(let app) = item else {
            return false
        }
        return model.canUninstall(app)
    }
```

- [ ] **Step 2: 新增 UninstallBadge 与 JiggleModifier**（放在 `LandingModifier` 之后）

```swift
private struct UninstallBadge: View {
    let layout: LauncherHomeLayout

    var body: some View {
        let side = layout.uninstallBadgeSide
        Image(systemName: "xmark")
            .font(.system(size: side * 0.42, weight: .bold))
            .foregroundStyle(.black.opacity(0.75))
            .frame(width: side, height: side)
            .background(Circle().fill(.white.opacity(0.92)))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .offset(x: (layout.tileWidth - layout.iconSide) / 2 - side * 0.2, y: layout.tilePadding - side * 0.2)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("移到废纸篓")
    }
}

// 抖动时各图标以略有差异的周期左右摇摆
private struct JiggleModifier: ViewModifier {
    let isActive: Bool
    let seed: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            let period = 0.11 + Double(((seed % 5) + 5) % 5) * 0.008
            content.phaseAnimator([-1.0, 1.0]) { view, phase in
                view.rotationEffect(.degrees(phase * 2))
            } animation: { _ in
                .easeInOut(duration: period)
            }
        } else {
            content
        }
    }
}
```

- [ ] **Step 3: 构建、测试、安装、提交**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete"` → `Build complete!`，无警告
Run: `swift test 2>&1 | grep -E "error: -|Executed .* tests"` → 0 failures
Run: 安装命令。

```bash
git add Sources/LaunchApp/LauncherView.swift
git commit -m "feat(编辑): 抖动时图标摇摆并显示卸载按钮"
```

---

### Task 7: 目标机验证与文档

- [ ] **Step 1: 备份布局并放入测试用假应用**

```bash
L="$HOME/Library/Application Support/Launch"; B=$(mktemp -d); echo "$B" > /tmp/launch-layout-backup-dir
cp "$L/layout.json" "$B/"; [ -f "$L/layout.json.backup" ] && cp "$L/layout.json.backup" "$B/"
shasum -a 256 "$L"/layout.json* | tee "$B/sha.txt"
D="$HOME/Applications/LaunchTestDummy.app"; mkdir -p "$D/Contents"
cat > "$D/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.yocn.launch.testdummy</string>
<key>CFBundleName</key><string>LaunchTestDummy</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
```

- [ ] **Step 2: e2e（编译到临时目录运行）**

场景：J1 长按第 1 页图标后 Esc 不关闭启动器（说明进入了抖动），再 Esc 关闭；J2 切到最后一页，长按假应用进入抖动，假应用出现 × 且 Launch 自身没有；点 × 出现确认框且层级高于面板，先取消（假应用仍在），再点 × 并确认，假应用移到废纸篓、图标消失、仍在抖动；全程未启动应用。

```swift
import AppKit
import ApplicationServices

let launchID = "dev.yocn.launch"
let dummyPath = NSHomeDirectory() + "/Applications/LaunchTestDummy.app"
let src = CGEventSource(stateID: .hidSystemState)
var failures = 0
setvbuf(stdout, nil, _IONBF, 0)

func check(_ ok: Bool, _ name: String) {
    print(ok ? "PASS \(name)" : "FAIL \(name)")
    if !ok { failures += 1 }
}
func wait(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
func pid() -> pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: launchID).first?.processIdentifier }
func attr(_ e: AXUIElement, _ n: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func all(_ e: AXUIElement, _ d: Int = 0) -> [AXUIElement] { d > 40 ? [] : [e] + kids(e).flatMap { all($0, d + 1) } }
func role(_ e: AXUIElement) -> String { (attr(e, kAXRoleAttribute) as? String) ?? "" }
func desc(_ e: AXUIElement) -> String { (attr(e, kAXDescriptionAttribute) as? String) ?? "" }
func title(_ e: AXUIElement) -> String { (attr(e, kAXTitleAttribute) as? String) ?? "" }
func frame(_ e: AXUIElement) -> CGRect? {
    guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(s as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}
func windows() -> [AXUIElement] { pid().map { (attr(AXUIElementCreateApplication($0), kAXWindowsAttribute) as? [AXUIElement]) ?? [] } ?? [] }
func elements() -> [AXUIElement] { windows().flatMap { all($0) } }
func button(_ name: String) -> CGRect? { elements().first { role($0) == kAXButtonRole && desc($0) == name }.flatMap(frame) }
func panelVisible() -> Bool {
    guard let pid = pid() else { return false }
    return (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []).contains {
        ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 25
    }
}
func dialogLayer() -> Int? {
    guard let pid = pid() else { return nil }
    return (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap {
        guard ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid else { return nil }
        let layer = ($0[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        return layer == 25 ? nil : layer
    }.max()
}
func dialogButton(_ name: String) -> AXUIElement? {
    windows().filter { (attr($0, kAXSubroleAttribute) as? String) == "AXDialog" }.flatMap { all($0) }.first { role($0) == kAXButtonRole && title($0) == name }
}
func mouse(_ type: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap) }
func key(_ code: CGKeyCode) {
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
}
func longPress(_ p: CGPoint) { mouse(.mouseMoved, p); usleep(150_000); mouse(.leftMouseDown, p); wait(0.8); mouse(.leftMouseUp, p); wait(0.5) }
func click(_ p: CGPoint) { mouse(.mouseMoved, p); usleep(150_000); mouse(.leftMouseDown, p); usleep(60_000); mouse(.leftMouseUp, p) }
func openLauncher() {
    let open = Process(); open.executableURL = URL(fileURLWithPath: "/usr/bin/open"); open.arguments = [NSHomeDirectory() + "/Applications/Launch.app"]; try? open.run(); open.waitUntilExit(); wait(1.5)
}
func selectPage(_ label: String) {
    if let dot = elements().first(where: { role($0) == kAXButtonRole && desc($0) == label }) { AXUIElementPerformAction(dot, kAXPressAction as CFString); wait(0.9) }
}
func badgePoint(_ tile: CGRect) -> CGPoint {
    let side = 88 * 0.3
    return CGPoint(x: tile.midX - 44 - side * 0.2 + side / 2, y: tile.minY + 12 - side * 0.2 + side / 2)
}

for _ in 0 ..< 8 {
    for w in windows() where (attr(w, kAXSubroleAttribute) as? String) == "AXDialog" {
        if let ok = all(w).first(where: { role($0) == kAXButtonRole }) { AXUIElementPerformAction(ok, kAXPressAction as CFString) }
    }
    wait(0.3)
}
let originalMouse = CGEvent(source: nil)?.location ?? .zero
let appsBefore = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
CGWarpMouseCursorPosition(CGPoint(x: 756, y: 491)); mouse(.mouseMoved, CGPoint(x: 756, y: 491)); wait(0.5)
openLauncher()
selectPage("第 1 页")

// J1 长按进入抖动，第一次 Esc 只退出抖动
if let notes = button("备忘录") { longPress(CGPoint(x: notes.midX, y: notes.midY)) }
key(53); wait(0.6)
check(panelVisible(), "J1 长按后第一次 Esc 不关闭启动器")
key(53); wait(0.6)
check(!panelVisible(), "J1 第二次 Esc 关闭启动器")

// J2 假应用的 × 与卸载
openLauncher()
let dots = elements().filter { role($0) == kAXButtonRole && desc($0).hasPrefix("第 ") && desc($0).hasSuffix(" 页") }
if let last = dots.last { AXUIElementPerformAction(last, kAXPressAction as CFString); wait(0.9) }
guard let dummy = button("LaunchTestDummy") else { print("FAIL 找不到假应用"); exit(1) }
longPress(CGPoint(x: dummy.midX, y: dummy.midY))
let badges = elements().filter { desc($0) == "移到废纸篓" }.compactMap(frame)
check(badges.contains { dummy.intersects($0) }, "J2 假应用显示 ×")
if let own = button("Launch") { check(!badges.contains { own.intersects($0) }, "J2 Launch 自身不显示 ×（本页 × 共 \(badges.count) 个）") }
click(badgePoint(dummy)); wait(0.8)
check((dialogLayer() ?? 0) > 25, "J2 确认框层级高于面板（\(dialogLayer() ?? -1)）")
if let cancel = dialogButton("取消") { AXUIElementPerformAction(cancel, kAXPressAction as CFString) }
wait(0.6)
check(FileManager.default.fileExists(atPath: dummyPath), "J2 取消后假应用仍在")
click(badgePoint(dummy)); wait(0.8)
if let confirm = dialogButton("移到废纸篓") { AXUIElementPerformAction(confirm, kAXPressAction as CFString) }
wait(2.5)
check(!FileManager.default.fileExists(atPath: dummyPath), "J2 确认后假应用移出 ~/Applications")
check(button("LaunchTestDummy") == nil, "J2 图标消失")
key(53); wait(0.6)
check(panelVisible(), "J2 卸载后仍在抖动（Esc 只退出抖动）")
let appsAfter = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
check(appsAfter.subtracting(appsBefore).subtracting([launchID]).isEmpty, "全程未启动应用")
key(53); wait(0.5)
CGWarpMouseCursorPosition(originalMouse)
print("FAILURES \(failures)")
```

Expected: 全部 `PASS`。

- [ ] **Step 3: 清理假应用并还原布局**

```bash
for f in "$HOME/.Trash"/LaunchTestDummy*.app "$HOME/Applications/LaunchTestDummy.app"; do
  [ -d "$f" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$f/Contents/Info.plist")" = "dev.yocn.launch.testdummy" ] && rm -r "$f" && echo "已删除测试假应用 $f"
done
L="$HOME/Library/Application Support/Launch"; B=$(cat /tmp/launch-layout-backup-dir)
cp "$B/layout.json" "$L/layout.json"; [ -f "$B/layout.json.backup" ] && cp "$B/layout.json.backup" "$L/layout.json.backup"
shasum -a 256 "$L"/layout.json* | diff - "$B/sha.txt" && echo "布局已还原"
pkill -x LaunchApp; sleep 1; open "$HOME/Applications/Launch.app"
```

- [ ] **Step 4: 文档**

- `docs/manual-verification.md` 当前结果追加本次 e2e 与清理记录；待验证追加「抖动观感、× 弹出动画、真实应用卸载（需用户自行决定）」。
- `README.md` 第 4a 期描述后追加：长按图标进入抖动，可直接删除的应用显示 ×，确认后移到废纸篓。

```bash
git add docs/manual-verification.md README.md
git commit -m "chore(文档): 记录抖动与卸载的验证结果"
```

---

## Self-Review

- Spec 覆盖：3.1 → Task 3/4/5；3.2 → Task 6；3.3 → Task 1；3.4 → Task 2/5；4 组件 → 各任务；5 测试 → Task 1–4 与 Task 7。
- 类型一致：`RunningAppHandle`、`AppUninstaller.canUninstall/runningInstance/quit/moveToTrash`、`UninstallCoordinator.canUninstall/uninstall`、`LauncherModel.beginJiggling/endJiggling/uninstallTarget/isJiggling/canUninstall`、`LauncherHomeLayout.uninstallBadgeSide/uninstallBadgeFrame(inTile:)` 各处一致。
