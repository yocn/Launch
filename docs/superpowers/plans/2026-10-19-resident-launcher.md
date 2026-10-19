# 第 1 期：常驻唤起 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Launch 常驻后台，⌥Space 或菜单栏唤起/关闭复用的启动器面板，支持开机启动，并能安装到 `~/Applications`。

**Architecture:** `LauncherController` 是显示/隐藏的唯一入口，通过 `LauncherPresenting` 协议驱动 `ScreenPresenter`（单个复用面板），界面状态放在 `@Observable` 的 `LauncherModel`。快捷键用 KeyboardShortcuts，目录变化用 FSEvents 驱动后台重扫，菜单栏与登录项各自独立成组件，`LaunchAppDelegate` 只负责组装。

**Tech Stack:** Swift 6.4（tools 6.2，Swift 6 语言模式）、macOS 26、AppKit、SwiftUI、Observation、ServiceManagement、CoreServices（FSEvents）、KeyboardShortcuts 3.1.0、XCTest、SwiftPM。

**Spec:** `docs/superpowers/specs/2026-10-19-resident-launcher-design.md`

## 全局约束

- 只改本期必需的代码，不顺带重构或清理。
- 不修改系统设置、不回写系统 Launchpad 数据、不卸载应用。LaunchOS 的偏好只读。
- 注释一行为限，只写非显而易见的约束。
- **每个 Commit 步骤执行前必须先征得用户明确同意**（用户全局约定）。提交信息只有标题行，格式 `<type>(<中文scope>): <中文描述>`，type 只用 `feat`/`fix`/`refactor`/`chore`，不加 `Co-Authored-By`。
- 测试命令：`swift test`；单个测试类：`swift test --filter LaunchAppTests.<类名>`。

## 文件结构

| 文件 | 操作 | 职责 |
| --- | --- | --- |
| `Package.swift` | 修改 | 增加 KeyboardShortcuts 依赖；`LaunchAppTests` 增加 `LaunchCore` 依赖 |
| `Package.resolved` | 新增（生成） | 锁定依赖版本 |
| `Resources/Info.plist` | 修改 | `LSUIElement`、版本号 |
| `Sources/LaunchApp/LauncherModel.swift` | 新增 | 搜索词、页码、应用列表、显示次数；Esc 分层 |
| `Sources/LaunchApp/IconCache.swift` | 新增 | 按路径缓存图标 |
| `Sources/LaunchApp/LauncherController.swift` | 新增 | `LauncherPresenting`、`LauncherHideReason`、`LauncherController` |
| `Sources/LaunchApp/HotKeyService.swift` | 新增 | 快捷键名称与注册 |
| `Sources/LaunchApp/HotKeyConflictDetector.swift` | 新增 | `HotKeyCombination`、LaunchOS 冲突检测 |
| `Sources/LaunchApp/LoginItemService.swift` | 新增 | `LoginItemAvailability`、`LoginItemService` |
| `Sources/LaunchApp/CatalogWatcher.swift` | 新增 | FSEvents 监听与后台重扫 |
| `Sources/LaunchApp/StatusItemController.swift` | 新增 | 菜单栏图标与菜单 |
| `Sources/LaunchApp/ScreenPresenter.swift` | 修改 | 单面板复用、按原因归还焦点、失去激活通知 |
| `Sources/LaunchApp/LauncherView.swift` | 修改 | 改由 `LauncherModel` 驱动，图标走 `IconCache` |
| `Sources/LaunchApp/LaunchApp.swift` | 修改 | 组装各组件、处理 reopen |
| `scripts/build-app.sh` | 修改 | 打入资源 bundle；`--install` |
| `Tests/LaunchAppTests/TestFixtures.swift` | 新增 | `makeApps`、`makeTemporaryDirectory` |
| `Tests/LaunchAppTests/LauncherModelTests.swift` 等 | 新增 | 各组件单测 |
| `README.md`、`docs/architecture.md`、`docs/manual-verification.md` | 修改 | 同步状态与调研结论 |

---

### Task 1: 引入依赖并隐藏 Dock 图标

**Files:**
- Modify: `Package.swift`
- Modify: `Resources/Info.plist`
- Create（生成）: `Package.resolved`

- [ ] **Step 1: 修改 `Package.swift`**

完整内容：

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Launch",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LaunchCore", targets: ["LaunchCore"]),
        .executable(name: "LaunchApp", targets: ["LaunchApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "LaunchCore"),
        .executableTarget(
            name: "LaunchApp",
            dependencies: [
                "LaunchCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .testTarget(name: "LaunchCoreTests", dependencies: ["LaunchCore"]),
        .testTarget(name: "LaunchAppTests", dependencies: ["LaunchApp", "LaunchCore"]),
    ]
)
```

- [ ] **Step 2: 修改 `Resources/Info.plist`**

在 `<key>CFBundlePackageType</key><string>APPL</string>` 之后插入：

```xml
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
```

- [ ] **Step 3: 解析依赖并验证构建与测试**

Run: `swift package resolve && swift build && swift test 2>&1 | grep -E "Executed|error" | tail -3`
Expected: `Package.resolved` 生成且 KeyboardShortcuts 为 `3.1.0`；构建成功；所有既有测试通过（0 failures）。

Run: `plutil -lint Resources/Info.plist`
Expected: `Resources/Info.plist: OK`

- [ ] **Step 4: Commit（先征得用户同意）**

```bash
git add Package.swift Package.resolved Resources/Info.plist
git commit -m "chore(构建): 引入 KeyboardShortcuts 并隐藏 Dock 图标"
```

---

### Task 2: 启动器状态模型

**Files:**
- Create: `Tests/LaunchAppTests/TestFixtures.swift`
- Create: `Tests/LaunchAppTests/LauncherModelTests.swift`
- Create: `Sources/LaunchApp/LauncherModel.swift`

- [ ] **Step 1: 新增测试辅助 `Tests/LaunchAppTests/TestFixtures.swift`**

```swift
import Foundation
import LaunchCore
import XCTest

func makeApps(count: Int) -> [CatalogApp] {
    (0 ..< count).map { index in
        CatalogApp(
            identity: AppIdentity(
                bundleIdentifier: "com.example.app\(index)",
                path: "/Applications/App \(index).app"
            ),
            displayName: "App \(index)"
        )
    }
}

extension XCTestCase {
    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
```

- [ ] **Step 2: 写失败测试 `Tests/LaunchAppTests/LauncherModelTests.swift`**

```swift
import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelTests: XCTestCase {
    @MainActor
    func testSetQueryResetsPage() {
        let model = LauncherModel(apps: makeApps(count: 40))
        model.selectPage(1)

        model.setQuery("App 1")

        XCTAssertEqual(model.currentPage, 0)
    }

    @MainActor
    func testSelectPageClampsToAvailablePages() {
        let model = LauncherModel(apps: makeApps(count: 40))

        model.selectPage(5)

        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.visibleApps.count, 5)
    }

    @MainActor
    func testPrepareForPresentationClearsQueryAndCountsPresentation() {
        let model = LauncherModel(apps: makeApps(count: 3))
        model.setQuery("App")

        model.prepareForPresentation()

        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.presentationCount, 1)
    }

    @MainActor
    func testPrepareForPresentationKeepsBrowsingPage() {
        let model = LauncherModel(apps: makeApps(count: 40))
        model.selectPage(1)

        model.prepareForPresentation()

        XCTAssertEqual(model.currentPage, 1)
    }

    @MainActor
    func testEscapeClearsQueryBeforeClosing() {
        let model = LauncherModel(apps: makeApps(count: 3))
        model.setQuery("App")

        XCTAssertEqual(model.handleEscape(), .clearedQuery)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.handleEscape(), .close)
    }

    @MainActor
    func testUpdateAppsClampsPage() {
        let model = LauncherModel(apps: makeApps(count: 40))
        model.selectPage(1)

        model.updateApps(makeApps(count: 10))

        XCTAssertEqual(model.currentPage, 0)
        XCTAssertEqual(model.visibleApps.count, 10)
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `swift test --filter LaunchAppTests.LauncherModelTests 2>&1 | grep -E "error|Executed" | head -5`
Expected: 编译失败，`cannot find 'LauncherModel' in scope`。

- [ ] **Step 4: 实现 `Sources/LaunchApp/LauncherModel.swift`**

```swift
import LaunchCore
import Observation

enum EscapeOutcome: Equatable {
    case clearedQuery
    case close
}

@MainActor
@Observable
final class LauncherModel {
    private(set) var apps: [CatalogApp]
    private(set) var query = ""
    private(set) var currentPage = 0
    private(set) var presentationCount = 0

    init(apps: [CatalogApp] = []) {
        self.apps = apps
    }

    var results: [CatalogApp] {
        SearchService.results(for: query, in: apps, hidden: [])
    }

    var pages: [[CatalogApp]] {
        LauncherPagination.pages(results, capacity: LauncherHomeLayout.pageCapacity)
    }

    var visibleApps: [CatalogApp] {
        let pages = pages
        guard !pages.isEmpty else {
            return []
        }
        return pages[LauncherPagination.normalizedPageIndex(currentPage, pageCount: pages.count)]
    }

    func setQuery(_ newQuery: String) {
        guard newQuery != query else {
            return
        }
        query = newQuery
        currentPage = 0
    }

    func selectPage(_ index: Int) {
        currentPage = clampedPage(index)
    }

    func prepareForPresentation() {
        setQuery("")
        currentPage = clampedPage(currentPage)
        presentationCount += 1
    }

    func handleEscape() -> EscapeOutcome {
        guard !query.isEmpty else {
            return .close
        }
        setQuery("")
        return .clearedQuery
    }

    func updateApps(_ newApps: [CatalogApp]) {
        apps = newApps
        currentPage = clampedPage(currentPage)
    }

    private func clampedPage(_ index: Int) -> Int {
        LauncherPagination.normalizedPageIndex(index, pageCount: pages.count)
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test --filter LaunchAppTests.LauncherModelTests 2>&1 | grep -E "error|Executed" | tail -2`
Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 6: Commit（先征得用户同意）**

```bash
git add Tests/LaunchAppTests/TestFixtures.swift Tests/LaunchAppTests/LauncherModelTests.swift Sources/LaunchApp/LauncherModel.swift
git commit -m "feat(启动器): 添加启动器状态模型"
```

---

### Task 3: 图标缓存

**Files:**
- Create: `Tests/LaunchAppTests/IconCacheTests.swift`
- Create: `Sources/LaunchApp/IconCache.swift`

- [ ] **Step 1: 写失败测试 `Tests/LaunchAppTests/IconCacheTests.swift`**

```swift
import AppKit
import XCTest
@testable import LaunchApp

final class IconCacheTests: XCTestCase {
    @MainActor
    func testIconIsLoadedOncePerPath() {
        var loadedPaths: [String] = []
        let cache = IconCache { path in
            loadedPaths.append(path)
            return NSImage()
        }

        _ = cache.icon(for: "/Applications/A.app")
        _ = cache.icon(for: "/Applications/A.app")
        _ = cache.icon(for: "/Applications/B.app")

        XCTAssertEqual(loadedPaths, ["/Applications/A.app", "/Applications/B.app"])
    }

    @MainActor
    func testRemoveAllForcesReload() {
        var loads = 0
        let cache = IconCache { _ in
            loads += 1
            return NSImage()
        }

        _ = cache.icon(for: "/Applications/A.app")
        cache.removeAll()
        _ = cache.icon(for: "/Applications/A.app")

        XCTAssertEqual(loads, 2)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter LaunchAppTests.IconCacheTests 2>&1 | grep -E "error|Executed" | head -3`
Expected: 编译失败，`cannot find 'IconCache' in scope`。

- [ ] **Step 3: 实现 `Sources/LaunchApp/IconCache.swift`**

```swift
import AppKit

@MainActor
final class IconCache {
    static let shared = IconCache(loader: ApplicationIconResolver.icon(for:))

    private let cache = NSCache<NSString, NSImage>()
    private let loader: (String) -> NSImage

    init(loader: @escaping (String) -> NSImage) {
        self.loader = loader
    }

    func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }
        let icon = loader(path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter LaunchAppTests.IconCacheTests 2>&1 | grep -E "error|Executed" | tail -2`
Expected: `Executed 2 tests, with 0 failures`

- [ ] **Step 5: Commit（先征得用户同意）**

```bash
git add Tests/LaunchAppTests/IconCacheTests.swift Sources/LaunchApp/IconCache.swift
git commit -m "feat(界面): 缓存应用图标"
```

---

### Task 4: 唤起与关闭控制器

**Files:**
- Create: `Tests/LaunchAppTests/LauncherControllerTests.swift`
- Create: `Sources/LaunchApp/LauncherController.swift`

- [ ] **Step 1: 写失败测试 `Tests/LaunchAppTests/LauncherControllerTests.swift`**

```swift
import AppKit
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
private final class FakePresenter: LauncherPresenting {
    private(set) var isVisible = false
    private(set) var presentCount = 0
    private(set) var dismissals: [Bool] = []

    func present() {
        isVisible = true
        presentCount += 1
    }

    func dismiss(restoringPreviousApp: Bool) {
        isVisible = false
        dismissals.append(restoringPreviousApp)
    }
}

final class LauncherControllerTests: XCTestCase {
    @MainActor
    func testToggleShowsThenHidesRestoringPreviousApp() {
        let (controller, presenter) = makeController()

        controller.toggle()
        controller.toggle()

        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertEqual(presenter.dismissals, [true])
    }

    @MainActor
    func testShowClearsQueryAndIgnoresRepeatWhileVisible() {
        let (controller, presenter) = makeController()
        controller.model.setQuery("App")

        controller.show()
        XCTAssertEqual(controller.model.query, "")

        controller.model.setQuery("Ap")
        controller.show()

        XCTAssertEqual(presenter.presentCount, 1)
        XCTAssertEqual(controller.model.query, "Ap")
    }

    @MainActor
    func testEscapeClearsQueryBeforeHiding() {
        let (controller, presenter) = makeController()
        controller.show()
        controller.model.setQuery("App")

        controller.handleEscape()
        XCTAssertTrue(presenter.isVisible)

        controller.handleEscape()
        XCTAssertEqual(presenter.dismissals, [true])
    }

    func testHideReasonsDecideFocusRestoration() {
        let reasons: [LauncherHideReason] = [
            .toggle, .escape, .backgroundClick, .launchedApp, .resignedActive,
        ]

        XCTAssertEqual(
            reasons.map(\.restoresPreviousApp),
            [true, true, true, false, false]
        )
    }

    @MainActor
    func testHideWhenNotVisibleDoesNothing() {
        let (controller, presenter) = makeController()

        controller.hide(.resignedActive)

        XCTAssertEqual(presenter.dismissals, [])
    }

    @MainActor
    func testSuccessfulLaunchHidesWithoutRestoringPreviousApp() {
        var openedPaths: [String] = []
        let (controller, presenter) = makeController { url in
            openedPaths.append(url.path)
            return true
        }
        let app = makeApps(count: 1)[0]
        controller.show()

        controller.launch(app)

        XCTAssertEqual(openedPaths, [app.identity.path])
        XCTAssertEqual(presenter.dismissals, [false])
    }

    @MainActor
    func testFailedLaunchKeepsLauncherVisible() {
        let (controller, presenter) = makeController { _ in false }
        controller.show()

        controller.launch(makeApps(count: 1)[0])

        XCTAssertTrue(presenter.isVisible)
        XCTAssertEqual(presenter.dismissals, [])
    }

    @MainActor
    func testUpdateCatalogKeepsIconsWhenAppsAreUnchanged() {
        var loads = 0
        let iconCache = IconCache { _ in
            loads += 1
            return NSImage()
        }
        let apps = makeApps(count: 2)
        let (controller, _) = makeController(apps: apps, iconCache: iconCache)
        _ = iconCache.icon(for: apps[0].identity.path)

        controller.updateCatalog(apps)
        _ = iconCache.icon(for: apps[0].identity.path)
        XCTAssertEqual(loads, 1)

        controller.updateCatalog(makeApps(count: 3))
        _ = iconCache.icon(for: apps[0].identity.path)
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(controller.model.apps.count, 3)
    }

    @MainActor
    private func makeController(
        apps: [CatalogApp] = [],
        iconCache: IconCache = IconCache { _ in NSImage() },
        openApplication: @escaping (URL) -> Bool = { _ in true }
    ) -> (LauncherController, FakePresenter) {
        let presenter = FakePresenter()
        let controller = LauncherController(
            model: LauncherModel(apps: apps),
            presenter: presenter,
            iconCache: iconCache,
            openApplication: openApplication
        )
        return (controller, presenter)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter LaunchAppTests.LauncherControllerTests 2>&1 | grep -E "error|Executed" | head -3`
Expected: 编译失败，`cannot find type 'LauncherPresenting' in scope`。

- [ ] **Step 3: 实现 `Sources/LaunchApp/LauncherController.swift`**

```swift
import Foundation
import LaunchCore

enum LauncherHideReason: Equatable {
    case toggle
    case escape
    case backgroundClick
    case launchedApp
    case resignedActive

    var restoresPreviousApp: Bool {
        switch self {
        case .toggle, .escape, .backgroundClick:
            true
        case .launchedApp, .resignedActive:
            false
        }
    }
}

@MainActor
protocol LauncherPresenting: AnyObject {
    var isVisible: Bool { get }
    func present()
    func dismiss(restoringPreviousApp: Bool)
}

@MainActor
final class LauncherController {
    let model: LauncherModel
    private let presenter: LauncherPresenting
    private let iconCache: IconCache
    private let openApplication: (URL) -> Bool

    init(
        model: LauncherModel,
        presenter: LauncherPresenting,
        iconCache: IconCache,
        openApplication: @escaping (URL) -> Bool
    ) {
        self.model = model
        self.presenter = presenter
        self.iconCache = iconCache
        self.openApplication = openApplication
    }

    func show() {
        guard !presenter.isVisible else {
            return
        }
        model.prepareForPresentation()
        presenter.present()
    }

    func toggle() {
        if presenter.isVisible {
            hide(.toggle)
        } else {
            show()
        }
    }

    func hide(_ reason: LauncherHideReason) {
        guard presenter.isVisible else {
            return
        }
        presenter.dismiss(restoringPreviousApp: reason.restoresPreviousApp)
    }

    func handleEscape() {
        if model.handleEscape() == .close {
            hide(.escape)
        }
    }

    func launch(_ app: CatalogApp) {
        guard openApplication(URL(fileURLWithPath: app.identity.path)) else {
            return
        }
        hide(.launchedApp)
    }

    func updateCatalog(_ apps: [CatalogApp]) {
        guard apps != model.apps else {
            return
        }
        iconCache.removeAll()
        model.updateApps(apps)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter LaunchAppTests.LauncherControllerTests 2>&1 | grep -E "error|Executed" | tail -2`
Expected: `Executed 8 tests, with 0 failures`

- [ ] **Step 5: Commit（先征得用户同意）**

```bash
git add Tests/LaunchAppTests/LauncherControllerTests.swift Sources/LaunchApp/LauncherController.swift
git commit -m "feat(启动器): 添加唤起与关闭控制器"
```

---

### Task 5: 全局快捷键与 LaunchOS 冲突检测

**Files:**
- Create: `Tests/LaunchAppTests/HotKeyConflictDetectorTests.swift`
- Create: `Sources/LaunchApp/HotKeyConflictDetector.swift`
- Create: `Sources/LaunchApp/HotKeyService.swift`

- [ ] **Step 1: 写失败测试 `Tests/LaunchAppTests/HotKeyConflictDetectorTests.swift`**

```swift
import XCTest
@testable import LaunchApp

final class HotKeyConflictDetectorTests: XCTestCase {
    private let optionSpace = HotKeyCombination(keyCode: 49, modifiers: 2048)
    private let launchOSOptionSpace = #"{"carbonModifiers":2048,"carbonKeyCode":49}"#

    @MainActor
    func testConflictWhenLaunchOSRunsWithSameShortcut() {
        let detector = makeDetector(running: true, value: launchOSOptionSpace)

        XCTAssertTrue(detector.conflictsWithLaunchOS(optionSpace))
    }

    @MainActor
    func testNoConflictWhenLaunchOSIsNotRunning() {
        let detector = makeDetector(running: false, value: launchOSOptionSpace)

        XCTAssertFalse(detector.conflictsWithLaunchOS(optionSpace))
    }

    @MainActor
    func testNoConflictWhenShortcutsDiffer() {
        let detector = makeDetector(
            running: true,
            value: #"{"carbonModifiers":256,"carbonKeyCode":49}"#
        )

        XCTAssertFalse(detector.conflictsWithLaunchOS(optionSpace))
    }

    @MainActor
    func testNoConflictWhenPreferenceIsMissingOrMalformed() {
        XCTAssertFalse(makeDetector(running: true, value: nil).conflictsWithLaunchOS(optionSpace))
        XCTAssertFalse(makeDetector(running: true, value: "not json").conflictsWithLaunchOS(optionSpace))
    }

    @MainActor
    func testNoConflictWithoutOwnShortcut() {
        let detector = makeDetector(running: true, value: launchOSOptionSpace)

        XCTAssertFalse(detector.conflictsWithLaunchOS(nil))
    }

    @MainActor
    private func makeDetector(running: Bool, value: String?) -> HotKeyConflictDetector {
        HotKeyConflictDetector(
            isLaunchOSRunning: { running },
            launchOSShortcutValue: { value }
        )
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter LaunchAppTests.HotKeyConflictDetectorTests 2>&1 | grep -E "error|Executed" | head -3`
Expected: 编译失败，`cannot find 'HotKeyCombination' in scope`。

- [ ] **Step 3: 实现 `Sources/LaunchApp/HotKeyConflictDetector.swift`**

```swift
import AppKit

struct HotKeyCombination: Equatable, Sendable {
    let keyCode: Int
    let modifiers: Int
}

@MainActor
struct HotKeyConflictDetector {
    static let launchOSBundleIdentifier = "app.remixdesign.LaunchOS"
    static let launchOSShortcutKey = "KeyboardShortcuts_launchApp"

    let isLaunchOSRunning: () -> Bool
    let launchOSShortcutValue: () -> String?

    static var live: HotKeyConflictDetector {
        HotKeyConflictDetector(
            isLaunchOSRunning: {
                !NSRunningApplication.runningApplications(
                    withBundleIdentifier: launchOSBundleIdentifier
                ).isEmpty
            },
            launchOSShortcutValue: {
                CFPreferencesCopyAppValue(
                    launchOSShortcutKey as CFString,
                    launchOSBundleIdentifier as CFString
                ) as? String
            }
        )
    }

    func conflictsWithLaunchOS(_ combination: HotKeyCombination?) -> Bool {
        guard let combination,
              isLaunchOSRunning(),
              let value = launchOSShortcutValue(),
              let launchOSCombination = Self.parse(value) else {
            return false
        }
        return launchOSCombination == combination
    }

    private static func parse(_ value: String) -> HotKeyCombination? {
        struct StoredShortcut: Decodable {
            let carbonKeyCode: Int
            let carbonModifiers: Int
        }
        guard let data = value.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredShortcut.self, from: data) else {
            return nil
        }
        return HotKeyCombination(keyCode: stored.carbonKeyCode, modifiers: stored.carbonModifiers)
    }
}
```

- [ ] **Step 4: 实现 `Sources/LaunchApp/HotKeyService.swift`**

不写单测：`KeyboardShortcuts.Name` 初始化会写入测试进程的 UserDefaults 并启动库的热键中心，改为 Task 9 手动验证。

```swift
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleLauncher = Self("toggleLauncher", initial: .init(.space, modifiers: [.option]))
}

@MainActor
enum HotKeyService {
    static func register(onToggle: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .toggleLauncher, action: onToggle)
    }

    static var currentCombination: HotKeyCombination? {
        KeyboardShortcuts.getShortcut(for: .toggleLauncher).map {
            HotKeyCombination(keyCode: $0.carbonKeyCode, modifiers: $0.carbonModifiers)
        }
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test --filter LaunchAppTests.HotKeyConflictDetectorTests 2>&1 | grep -E "error|Executed" | tail -2`
Expected: `Executed 5 tests, with 0 failures`

Run: `swift build 2>&1 | grep -E "error|Compiling|Build complete" | tail -2`
Expected: `Build complete!`（确认 `HotKeyService` 编译通过）

- [ ] **Step 6: Commit（先征得用户同意）**

```bash
git add Tests/LaunchAppTests/HotKeyConflictDetectorTests.swift Sources/LaunchApp/HotKeyConflictDetector.swift Sources/LaunchApp/HotKeyService.swift
git commit -m "feat(快捷键): 注册全局快捷键并检测 LaunchOS 冲突"
```

---

### Task 6: 开机启动服务

**Files:**
- Create: `Tests/LaunchAppTests/LoginItemAvailabilityTests.swift`
- Create: `Sources/LaunchApp/LoginItemService.swift`

- [ ] **Step 1: 写失败测试 `Tests/LaunchAppTests/LoginItemAvailabilityTests.swift`**

```swift
import Foundation
import XCTest
@testable import LaunchApp

final class LoginItemAvailabilityTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    func testAvailableInSystemApplications() {
        XCTAssertTrue(isAvailable(path: "/Applications/Launch.app"))
    }

    func testAvailableInUserApplications() {
        XCTAssertTrue(isAvailable(path: "/Users/tester/Applications/Launch.app"))
    }

    func testUnavailableInBuildDirectory() {
        XCTAssertFalse(isAvailable(path: "/Users/tester/launch/.build/Launch.app"))
    }

    func testUnavailableInNestedFolder() {
        XCTAssertFalse(isAvailable(path: "/Applications/Tools/Launch.app"))
    }

    func testUnavailableWithoutBundleIdentifier() {
        XCTAssertFalse(
            LoginItemAvailability.isAvailable(
                bundleIdentifier: nil,
                bundleURL: URL(fileURLWithPath: "/Applications/Launch.app"),
                homeDirectory: home
            )
        )
    }

    private func isAvailable(path: String) -> Bool {
        LoginItemAvailability.isAvailable(
            bundleIdentifier: "dev.yocn.launch",
            bundleURL: URL(fileURLWithPath: path),
            homeDirectory: home
        )
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter LaunchAppTests.LoginItemAvailabilityTests 2>&1 | grep -E "error|Executed" | head -3`
Expected: 编译失败，`cannot find 'LoginItemAvailability' in scope`。

- [ ] **Step 3: 实现 `Sources/LaunchApp/LoginItemService.swift`**

```swift
import Foundation
import ServiceManagement

enum LoginItemAvailability {
    static func isAvailable(bundleIdentifier: String?, bundleURL: URL, homeDirectory: URL) -> Bool {
        guard bundleIdentifier != nil, bundleURL.pathExtension == "app" else {
            return false
        }
        let parentPath = bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let allowedPaths = [
            "/Applications",
            homeDirectory.appending(path: "Applications").standardizedFileURL.path,
        ]
        return allowedPaths.contains(parentPath)
    }
}

@MainActor
final class LoginItemService {
    private let service = SMAppService.mainApp

    var isAvailable: Bool {
        LoginItemAvailability.isAvailable(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            bundleURL: Bundle.main.bundleURL,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            guard service.status == .requiresApproval else {
                throw error
            }
        }
        if enabled, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter LaunchAppTests.LoginItemAvailabilityTests 2>&1 | grep -E "error|Executed" | tail -2`
Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: Commit（先征得用户同意）**

```bash
git add Tests/LaunchAppTests/LoginItemAvailabilityTests.swift Sources/LaunchApp/LoginItemService.swift
git commit -m "feat(开机启动): 添加登录项服务"
```

---

### Task 7: 应用目录监听

**Files:**
- Create: `Tests/LaunchAppTests/CatalogWatcherTests.swift`
- Create: `Sources/LaunchApp/CatalogWatcher.swift`

- [ ] **Step 1: 写失败测试 `Tests/LaunchAppTests/CatalogWatcherTests.swift`**

```swift
import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
private final class DeliveryRecorder {
    private(set) var deliveries: [[CatalogApp]] = []

    func record(_ apps: [CatalogApp]) {
        deliveries.append(apps)
    }
}

final class CatalogWatcherTests: XCTestCase {
    @MainActor
    func testStartDeliversInitialScan() async throws {
        let root = try makeTemporaryDirectory()
        let recorder = DeliveryRecorder()
        let watcher = CatalogWatcher(
            roots: [root],
            scan: { _ in makeApps(count: 1) },
            onChange: { recorder.record($0) }
        )

        watcher.start()

        let delivered = try await waitUntil { !recorder.deliveries.isEmpty }
        XCTAssertTrue(delivered)
        XCTAssertEqual(recorder.deliveries.first?.count, 1)
        withExtendedLifetime(watcher) {}
    }

    @MainActor
    func testDirectoryChangeTriggersRescan() async throws {
        let root = try makeTemporaryDirectory()
        let recorder = DeliveryRecorder()
        let watcher = CatalogWatcher(
            roots: [root],
            scan: { _ in [] },
            onChange: { recorder.record($0) }
        )

        watcher.start()
        let initialDelivered = try await waitUntil { recorder.deliveries.count == 1 }
        XCTAssertTrue(initialDelivered)
        try Data().write(to: root.appending(path: "Added.app"))

        let rescanned = try await waitUntil { recorder.deliveries.count >= 2 }
        XCTAssertTrue(rescanned)
        withExtendedLifetime(watcher) {}
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ condition: () -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                return false
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return true
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter LaunchAppTests.CatalogWatcherTests 2>&1 | grep -E "error|Executed" | head -3`
Expected: 编译失败，`cannot find 'CatalogWatcher' in scope`。

- [ ] **Step 3: 实现 `Sources/LaunchApp/CatalogWatcher.swift`**

```swift
import CoreServices
import Foundation
import LaunchCore

final class CatalogWatcher {
    private let roots: [URL]
    private let scan: @Sendable ([URL]) -> [CatalogApp]
    private let onChange: @MainActor @Sendable ([CatalogApp]) -> Void
    private let queue = DispatchQueue(label: "dev.yocn.launch.catalog-watcher")
    private var stream: FSEventStreamRef?

    init(
        roots: [URL],
        scan: @escaping @Sendable ([URL]) -> [CatalogApp] = { roots in
            (try? AppCatalog().scan(roots: roots)) ?? []
        },
        onChange: @escaping @MainActor @Sendable ([CatalogApp]) -> Void
    ) {
        self.roots = roots
        self.scan = scan
        self.onChange = onChange
    }

    deinit {
        guard let stream else {
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    func start() {
        rescan()
        // FSEvents 需要真实路径，临时目录等位于 /var -> /private/var 的符号链接下
        let watchedPaths = roots
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { $0.resolvingSymlinksInPath().path }
        guard stream == nil, !watchedPaths.isEmpty else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else {
                return
            }
            Unmanaged<CatalogWatcher>.fromOpaque(info).takeUnretainedValue().rescan()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            watchedPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else {
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func rescan() {
        let roots = roots
        let scan = scan
        let onChange = onChange
        queue.async {
            let apps = scan(roots)
            Task { @MainActor in
                onChange(apps)
            }
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter LaunchAppTests.CatalogWatcherTests 2>&1 | grep -E "error|Executed" | tail -2`
Expected: `Executed 2 tests, with 0 failures`。若 `testDirectoryChangeTriggersRescan` 的 `rescanned` 为 false，先确认 `watchedPaths` 是否为解析后的 `/private/var/...` 路径，不要放宽超时掩盖问题。

- [ ] **Step 5: Commit（先征得用户同意）**

```bash
git add Tests/LaunchAppTests/CatalogWatcherTests.swift Sources/LaunchApp/CatalogWatcher.swift
git commit -m "feat(应用): 监听应用目录变化"
```

---

### Task 8: 菜单栏入口

**Files:**
- Create: `Sources/LaunchApp/StatusItemController.swift`

不写单测：创建 `NSStatusItem` 会占用真实菜单栏，改为 Task 9 手动验证。

- [ ] **Step 1: 实现 `Sources/LaunchApp/StatusItemController.swift`**

```swift
import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let openItem = NSMenuItem(title: "打开启动器", action: nil, keyEquivalent: " ")
    private let conflictItem = NSMenuItem(title: "⚠︎ 快捷键与 LaunchOS 冲突", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "开机启动", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "退出 Launch", action: nil, keyEquivalent: "q")
    private let loginItemService: LoginItemService
    private let hasHotKeyConflict: () -> Bool
    private let onOpen: () -> Void

    init(
        loginItemService: LoginItemService,
        hasHotKeyConflict: @escaping () -> Bool,
        onOpen: @escaping () -> Void
    ) {
        self.loginItemService = loginItemService
        self.hasHotKeyConflict = hasHotKeyConflict
        self.onOpen = onOpen
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "square.grid.3x3.fill",
            accessibilityDescription: "Launch"
        )
        // Shortcut.description 格式化 Space 时会读取库的资源 bundle，这里直接用 keyEquivalent 显示
        openItem.keyEquivalentModifierMask = [.option]
        openItem.action = #selector(openLauncher)
        openItem.target = self
        conflictItem.isEnabled = false
        loginItem.action = #selector(toggleLoginItem)
        loginItem.target = self
        quitItem.action = #selector(quit)
        quitItem.target = self

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.items = [openItem, conflictItem, .separator(), loginItem, .separator(), quitItem]
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        conflictItem.isHidden = !hasHotKeyConflict()
        let available = loginItemService.isAvailable
        loginItem.isEnabled = available
        loginItem.title = available ? "开机启动" : "开机启动（需安装到 ~/Applications）"
        loginItem.state = loginItemService.isEnabled ? .on : .off
    }

    @objc private func openLauncher() {
        onOpen()
    }

    @objc private func toggleLoginItem() {
        do {
            try loginItemService.setEnabled(loginItem.state != .on)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `swift build 2>&1 | grep -E "error|Build complete" | tail -2`
Expected: `Build complete!`

- [ ] **Step 3: Commit（先征得用户同意）**

```bash
git add Sources/LaunchApp/StatusItemController.swift
git commit -m "feat(菜单栏): 添加菜单栏入口"
```

---

### Task 9: 常驻并复用启动器面板

**Files:**
- Modify: `Sources/LaunchApp/ScreenPresenter.swift`（`ScreenPresenter` 类整体替换，其余类型保留）
- Modify: `Sources/LaunchApp/LauncherView.swift`
- Modify: `Sources/LaunchApp/LaunchApp.swift`

- [ ] **Step 1: 替换 `ScreenPresenter.swift` 的 import 与 `ScreenPresenter` 类**

`ScreenSelectionPolicy`、`LauncherPanelConfiguration`、`LauncherPanel` 保持不变。文件头部的 import 改为：

```swift
import AppKit
import CoreGraphics
import SwiftUI
```

`ScreenPresenter` 类整体替换为：

```swift
@MainActor
final class ScreenPresenter: LauncherPresenting {
    var onResignActive: (() -> Void)?
    private let panel: LauncherPanel
    private var resignObserver: NSObjectProtocol?

    init() {
        panel = LauncherPanel(
            contentRect: .zero,
            styleMask: LauncherPanelConfiguration.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onResignActive?()
            }
        }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func setContent(_ content: some View) {
        panel.contentView = NSHostingView(rootView: content)
    }

    func present() {
        guard let screen = targetScreen() else {
            return
        }
        panel.setFrame(screen.frame, display: true)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss(restoringPreviousApp: Bool) {
        panel.orderOut(nil)
        if restoringPreviousApp {
            NSApp.hide(nil)
        }
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let index = ScreenSelectionPolicy.screenIndex(
            containing: NSEvent.mouseLocation,
            in: screens.map(\.frame)
        ) ?? 0
        return screens.indices.contains(index) ? screens[index] : nil
    }
}
```

- [ ] **Step 2: 修改 `LauncherView.swift`：状态改由模型驱动**

将 `struct LauncherView` 开头到 `body` 结束（原第 15–66 行，含 `apps`、`onClose`、`onLaunch`、`@State`、`results`、`pages`、`visibleApps`、`body`）替换为：

```swift
struct LauncherView: View {
    let model: LauncherModel
    let onEscape: () -> Void
    let onBackgroundClick: () -> Void
    let onLaunch: (CatalogApp) -> Void

    @FocusState private var searchFieldIsFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.47))
                    .ignoresSafeArea()
                    .onTapGesture(perform: onBackgroundClick)

                homeContent(in: proxy.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onExitCommand(perform: onEscape)
        .onAppear {
            searchFieldIsFocused = true
        }
        .onChange(of: model.presentationCount) {
            searchFieldIsFocused = true
        }
    }
```

在 `homeContent(in:)` 中：

- `if visibleApps.isEmpty {` 改为 `if model.visibleApps.isEmpty {`
- `ForEach(visibleApps, id: \.identity) { app in` 改为 `ForEach(model.visibleApps, id: \.identity) { app in`
- 磁贴的 action 闭包

```swift
                        LauncherAppTile(app: app, iconSide: iconSide) {
                            if NSWorkspace.shared.open(
                                URL(fileURLWithPath: app.identity.path)
                            ) {
                                onLaunch()
                            }
                        }
```

  改为

```swift
                        LauncherAppTile(app: app, iconSide: iconSide) {
                            onLaunch(app)
                        }
```

- `if pages.count > 1 {` 改为 `if model.pages.count > 1 {`

在 `searchBar(width:)` 中：

- `TextField("搜索应用", text: $query)` 改为

```swift
            TextField("搜索应用", text: Binding(
                get: { model.query },
                set: { model.setQuery($0) }
            ))
```

- `SearchPresentation.showsClearControl(for: query)` 改为 `SearchPresentation.showsClearControl(for: model.query)`
- 清除按钮里的 `query = ""` 改为 `model.setQuery("")`
- `SearchPresentation.showsMoreControl(for: query)` 改为 `SearchPresentation.showsMoreControl(for: model.query)`

在 `pageIndicator` 中：

- `ForEach(pages.indices, id: \.self) { pageIndex in` 改为 `ForEach(model.pages.indices, id: \.self) { pageIndex in`
- `currentPage = pageIndex` 改为 `model.selectPage(pageIndex)`
- `.fill(pageIndex == currentPage ? .white : .white.opacity(0.4))` 改为 `.fill(pageIndex == model.currentPage ? .white : .white.opacity(0.4))`

在 `LauncherAppTile` 中：

- `Image(nsImage: ApplicationIconResolver.icon(for: app.identity.path))` 改为 `Image(nsImage: IconCache.shared.icon(for: app.identity.path))`

- [ ] **Step 3: 替换 `LaunchApp.swift` 中的 `LaunchAppDelegate`**

`LauncherPlacement` 与 `LaunchApp` 保持不变，`LaunchAppDelegate` 整体替换为：

```swift
@MainActor
private final class LaunchAppDelegate: NSObject, NSApplicationDelegate {
    private let presenter = ScreenPresenter()
    private let loginItemService = LoginItemService()
    private lazy var controller = LauncherController(
        model: LauncherModel(),
        presenter: presenter,
        iconCache: .shared,
        openApplication: { NSWorkspace.shared.open($0) }
    )
    private var statusItemController: StatusItemController?
    private var catalogWatcher: CatalogWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        presenter.setContent(
            LauncherView(
                model: controller.model,
                onEscape: { [weak self] in self?.controller.handleEscape() },
                onBackgroundClick: { [weak self] in self?.controller.hide(.backgroundClick) },
                onLaunch: { [weak self] app in self?.controller.launch(app) }
            )
        )
        presenter.onResignActive = { [weak self] in
            self?.controller.hide(.resignedActive)
        }
        HotKeyService.register { [weak self] in
            self?.controller.toggle()
        }
        statusItemController = StatusItemController(
            loginItemService: loginItemService,
            hasHotKeyConflict: { [weak self] in self?.hasHotKeyConflict() ?? false },
            onOpen: { [weak self] in self?.controller.show() }
        )
        let watcher = CatalogWatcher(roots: ApplicationSources.defaultRoots()) { [weak self] apps in
            self?.controller.updateCatalog(apps)
        }
        watcher.start()
        catalogWatcher = watcher
        warnIfHotKeyConflicts()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return false
    }

    private func hasHotKeyConflict() -> Bool {
        HotKeyConflictDetector.live.conflictsWithLaunchOS(HotKeyService.currentCombination)
    }

    private func warnIfHotKeyConflicts() {
        guard hasHotKeyConflict() else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "快捷键与 LaunchOS 冲突"
        alert.informativeText = "LaunchOS 正在使用相同的快捷键。请在 LaunchOS 中关闭它的快捷键或退出 LaunchOS，之后即可用该快捷键打开 Launch。"
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
```

- [ ] **Step 4: 全量构建与测试**

Run: `swift build 2>&1 | grep -E "error:|Build complete" | tail -3 && swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3`
Expected: `Build complete!`；所有测试 0 failures（`LaunchCore` 与 `LaunchApp` 两组）。

- [ ] **Step 5: 开发包冒烟验证**

此时 `build-app.sh` 尚未打入资源 bundle，先用 `swift run`（资源 bundle 就在可执行文件旁）：

Run: `swift run LaunchApp`（在单独终端保持运行）

手动确认并记录：

1. 启动后不弹出启动器，菜单栏出现网格图标，Dock 无图标。
2. 按 ⌥Space 弹出启动器，直接打字能搜索；再按 ⌥Space 关闭，焦点回到之前的应用。
3. 搜索框有字时按 Esc 只清空；再按 Esc 关闭。
4. 点击空白处关闭；点击应用图标启动该应用并关闭启动器。
5. 显示中按 ⌘Tab 切走，启动器自动消失。
6. 菜单栏菜单显示「打开启动器 ⌥Space」，点击可打开；「开机启动」为禁用状态并注明需安装；「退出 Launch」可退出。

任一项失败，先用 superpowers:systematic-debugging 定位，不要直接改动其他任务的代码。

- [ ] **Step 6: Commit（先征得用户同意）**

```bash
git add Sources/LaunchApp/ScreenPresenter.swift Sources/LaunchApp/LauncherView.swift Sources/LaunchApp/LaunchApp.swift
git commit -m "feat(启动器): 常驻后台并复用启动器面板"
```

---

### Task 10: 构建脚本支持安装

**Files:**
- Modify: `scripts/build-app.sh`

- [ ] **Step 1: 替换 `scripts/build-app.sh` 全部内容**

```zsh
#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
cd "${project_dir}"

install=false
configuration=debug
if [[ "${1:-}" == "--install" ]]; then
    install=true
    configuration=release
fi

swift build -c "${configuration}" --product LaunchApp
bin_dir=$(swift build -c "${configuration}" --show-bin-path)

bundle_dir="${project_dir}/.build/Launch.app"
contents_dir="${bundle_dir}/Contents"
rm -rf "${bundle_dir}"
mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources"
cp "${bin_dir}/LaunchApp" "${contents_dir}/MacOS/LaunchApp"
cp "${project_dir}/Resources/Info.plist" "${contents_dir}/Info.plist"
# KeyboardShortcuts 的 Bundle.module 从 Contents/Resources 加载，缺失时直接 fatalError
cp -R "${bin_dir}/KeyboardShortcuts_KeyboardShortcuts.bundle" "${contents_dir}/Resources/"

if [[ "${install}" != true ]]; then
    echo "${bundle_dir}"
    exit 0
fi

codesign --force --sign "${LAUNCH_SIGN_IDENTITY:--}" "${bundle_dir}"

if pgrep -x LaunchApp >/dev/null; then
    pkill -x LaunchApp
    for _ in {1..50}; do
        pgrep -x LaunchApp >/dev/null || break
        sleep 0.2
    done
    if pgrep -x LaunchApp >/dev/null; then
        echo "Launch 仍在运行，请手动退出后重试" >&2
        exit 1
    fi
fi

install_dir="${HOME}/Applications"
target_dir="${install_dir}/Launch.app"
staging_dir="${install_dir}/.Launch.app.installing"
mkdir -p "${install_dir}"
rm -rf "${staging_dir}"
ditto "${bundle_dir}" "${staging_dir}"
rm -rf "${target_dir}"
mv "${staging_dir}" "${target_dir}"
open "${target_dir}"
echo "${target_dir}"
```

- [ ] **Step 2: 验证 debug 打包**

Run: `./scripts/build-app.sh && ls .build/Launch.app/Contents/Resources && plutil -extract LSUIElement raw .build/Launch.app/Contents/Info.plist`
Expected: 输出 `.build/Launch.app` 路径；列出 `KeyboardShortcuts_KeyboardShortcuts.bundle`；`true`。

- [ ] **Step 3: 验证安装（会结束正在运行的 Launch 并启动新版）**

先退出 Task 9 的 `swift run` 进程。

Run: `LAUNCH_SIGN_IDENTITY="Apple Development: zhaoyingkun@163.com" ./scripts/build-app.sh --install && codesign --verify --strict --verbose=2 ~/Applications/Launch.app && pgrep -lx LaunchApp`
Expected: 输出 `~/Applications/Launch.app` 绝对路径；`valid on disk` 与 `satisfies its Designated Requirement`；`pgrep` 列出 `LaunchApp` 进程。

若用户不希望使用该证书，去掉 `LAUNCH_SIGN_IDENTITY=...` 以 ad-hoc 签名运行，并在 Task 11 记录登录项在重装后的表现。

- [ ] **Step 4: Commit（先征得用户同意）**

```bash
git add scripts/build-app.sh
git commit -m "feat(构建): 支持安装到 ~/Applications 并签名"
```

---

### Task 11: 目标机验证与文档同步

**Files:**
- Modify: `docs/manual-verification.md`
- Modify: `README.md`
- Modify: `docs/architecture.md`

- [ ] **Step 1: 用安装版逐项手动验证**

对 `~/Applications/Launch.app` 逐项执行并记录实际结果（通过/失败/现象）：

1. Task 9 Step 5 的 6 项在安装版上复测；菜单中「开机启动」此时可用。
2. 多显示器：鼠标移到副屏按 ⌥Space，启动器出现在副屏。无副屏则记录「未验证」。
3. 打开一个全屏应用，在其 Space 中按 ⌥Space，启动器覆盖在全屏应用上方；台前调度开启时重复一次。
4. 向 `~/Applications` 复制任一 `.app`（例如 `ditto /System/Applications/Chess.app ~/Applications/ChessCopy.app`），约 2 秒后唤起能搜到；删除后再唤起消失。验证完删除该副本。
5. 勾选「开机启动」；若系统要求批准，按弹出的系统设置页批准；重启后确认 Launch 自动运行且未弹出启动器。
6. 再执行一次 `./scripts/build-app.sh --install`，确认「开机启动」仍为勾选，且系统设置的登录项中仍为启用。
7. 若用户同意临时运行 LaunchOS 且其快捷键仍为 ⌥Space：启动 Launch 时弹出冲突提示，菜单出现冲突项。用户不同意则记录「未验证」。

- [ ] **Step 2: 更新 `docs/manual-verification.md`**

在「基础命令」代码块末尾追加一行：

```
    ./scripts/build-app.sh --install
```

在「当前结果」末尾追加一条，按 Step 1 实际结果填写，格式：

```
- 2026-10-19：第 1 期常驻唤起（安装版 ~/Applications/Launch.app，签名方式：<证书名或 ad-hoc>，显示器：<配置>）。⌥Space 唤起/关闭：<结果>；Esc 分层：<结果>；焦点归还：<结果>；⌘Tab 自动关闭：<结果>；全屏应用与台前调度：<结果>；目录变化刷新：<结果>；开机启动及重装后保持：<结果>；LaunchOS 冲突提示：<结果>。
```

「待验证」列表中删除已验证通过的条目，保留未验证或失败的条目并注明原因。

- [ ] **Step 3: 更新 `README.md` 的「当前状态」**

将

```
- 已建立可运行的 Swift Package 原型：扫描用户与系统应用目录，展示分页网格并即时筛选；布局编辑、旧布局导入和系统入口仍未实现。
- 使用 `./scripts/build-app.sh` 可在 `.build/Launch.app` 生成开发用应用包，便于手动验证界面。
- 尚未验证旧 Launchpad 布局数据是否存在、是否可读，以及能恢复多少内容。
```

替换为（按 Step 1 实际验证结果调整措辞，未通过的能力不得写成已支持）：

```
- 已建立可运行的 Swift Package 原型：扫描用户与系统应用目录，展示分页网格并即时筛选。第 1 期完成常驻唤起：后台常驻、⌥Space 与菜单栏唤起、目录变化自动刷新、开机启动开关。布局编辑、旧布局导入和 F4/手势等系统入口仍未实现。
- `./scripts/build-app.sh` 在 `.build/Launch.app` 生成开发用应用包；`./scripts/build-app.sh --install` 以 release 构建并安装到 `~/Applications/Launch.app`，可用环境变量 `LAUNCH_SIGN_IDENTITY` 指定签名证书。
- 旧 Launchpad 数据库位于 `$(getconf DARWIN_USER_DIR)/com.apple.dock.launchpad/db/db`，只读检查确认含 2 个有内容的页面、3 个文件夹、96 个应用（81 个可对应本机应用）；导入功能属于第 2 期。
```

- [ ] **Step 4: 更新 `docs/architecture.md`**

第 3 节，将

```
主界面优先评估 AppKit 的集合视图实现网格、复用和拖拽，设置用 SwiftUI；最终组件选择要由拖拽、文件夹动画和分页原型验证，不能仅凭“原生”推定所有交互都能自然满足。
```

替换为

```
主界面先沿用 SwiftUI 网格（LaunchOS 2.4.0 同样以 SwiftUI + `NSPanel` 实现，未使用 `NSCollectionView`），拖拽、文件夹动画或性能遇到瓶颈时再评估 AppKit 集合视图；设置用 SwiftUI。LaunchOS 技术栈的只读观察见 `docs/superpowers/specs/2026-10-19-resident-launcher-design.md` 第 8.2 节。
```

第 6 节，将

```
2026-10-19 对 `/Users/yocn/Library/Application Support` 和 `/Users/yocn/Library/Containers` 的有限用户级检查未发现可确认的旧 Launchpad 数据源；因此项目暂不硬编码未经证实的系统路径。macOS 26 的现有 Spotlight 应用入口不等同于旧 Launchpad 布局，也不能根据 LaunchOS 界面反推系统数据库一定完整存在。
```

替换为

```
2026-10-19 确认旧 Launchpad 数据库位于 `$(getconf DARWIN_USER_DIR)/com.apple.dock.launchpad/db/db`（SQLite，同目录有 `db-wal`、`db-shm`；`dbinfo` 记录 build 24F74，即 macOS 15.5 时期写入）。复制到临时目录只读查询：`items` 表以 `parent_id`、`ordering` 组织树，type 1 为根、3 为页面、2 为文件夹、4 为应用；`launchpad_root` 下有 2 个有内容的页面（另有 1 个空页）、3 个命名文件夹，共 96 个应用，其中 81 个可按 Bundle ID 对应本机应用。LaunchOS 2.4.0 读取同一路径。macOS 26 的 Spotlight 应用入口不等同于旧 Launchpad 布局。
```

- [ ] **Step 5: Commit（先征得用户同意）**

```bash
git add docs/manual-verification.md README.md docs/architecture.md
git commit -m "chore(文档): 同步第 1 期状态与旧布局调研"
```

---

## Self-Review

**Spec 覆盖：**

| Spec 要求 | 任务 |
| --- | --- |
| 2 KeyboardShortcuts 锁定 3.1.0、提交 `Package.resolved` | Task 1 |
| 3 `LSUIElement` | Task 1 |
| 3 `LauncherModel`、4.2 清空搜索词与页码规则、4.3 Esc 分层 | Task 2 |
| 5 `IconCache`、列表变化清空缓存 | Task 3、Task 4（`updateCatalog`） |
| 3 `LauncherController`、4.3 关闭原因与焦点、启动失败不关闭 | Task 4、Task 9 |
| 4.4 冲突检测（启动提示、菜单项、解析失败视为无冲突） | Task 5、Task 8、Task 9 |
| 6 开机启动可用条件、`requiresApproval`、错误弹窗 | Task 6、Task 8 |
| 5 FSEvents、1 秒合并、不存在目录不监听、后台重扫 | Task 7 |
| 6 菜单栏图标与 4 个菜单项 | Task 8 |
| 4.1 启动不弹出、4.2 三种唤起入口、单面板按鼠标屏幕显示 | Task 9 |
| 7 `--install`、资源 bundle、签名、替换安装 | Task 10 |
| 9 手动验证清单、10 文档同步 | Task 11 |

**类型一致性：** `LauncherPresenting`（`isVisible`/`present()`/`dismiss(restoringPreviousApp:)`）在 Task 4 定义，Task 9 的 `ScreenPresenter` 与测试中的 `FakePresenter` 实现一致；`LauncherHideReason` 五个 case 在 Task 4、Task 9 用法一致；`HotKeyCombination(keyCode:modifiers:)` 在 Task 5 定义并被 `HotKeyService.currentCombination` 使用；`IconCache(loader:)`、`icon(for:)`、`removeAll()` 在 Task 3/4/9 一致；`LauncherModel` 的 `setQuery`/`selectPage`/`prepareForPresentation`/`handleEscape`/`updateApps`/`presentationCount` 在 Task 2/4/9 一致。
