# 第 5a 期：设置窗口与显示设置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供设置窗口（通用、外观、应用三页），支持开机启动、快捷键录制、菜单栏图标、重新打开回第一页、背景与暗度、隐藏名称、隐藏应用列表与搜索可见性；「…」按钮与空白处右键打开主菜单。

**Architecture:** `LauncherSettings` 是存进 UserDefaults 的可观察设置对象；`WallpaperProvider` 读取屏幕壁纸；`LauncherModel` 新增隐藏应用列表、搜索显示隐藏应用、回第一页与当前壁纸；`ItemMenu` 增加主菜单与「取消隐藏」；`SettingsWindowController` + `SettingsView` 提供窗口；`LauncherView` 按设置绘制背景、名称与半透明隐藏应用；LaunchApp 用观察跟踪把设置同步到模型和菜单栏。

**Tech Stack:** Swift 6，AppKit（`NSWindow`、`NSWorkspace` 壁纸接口、`NSStatusItem`），SwiftUI（`TabView`、`Form`、`@Observable`、`@Entry`），KeyboardShortcuts 3.1.0（`Recorder`），XCTest。

**Spec:** `docs/superpowers/specs/2026-10-20-settings-window-design.md`

---

## 文件结构

| 文件 | 动作 | 职责 |
| --- | --- | --- |
| `Sources/LaunchApp/LauncherSettings.swift` | 新建 | 设置对象与枚举 |
| `Tests/LaunchAppTests/LauncherSettingsTests.swift` | 新建 | 默认值与持久化 |
| `Sources/LaunchApp/WallpaperProvider.swift` | 新建 | `Wallpaper`、`WallpaperProvider` |
| `Tests/LaunchAppTests/WallpaperProviderTests.swift` | 新建 | 读取、缓存、填充方式 |
| `Sources/LaunchApp/ItemMenu.swift` | 修改 | 主菜单、「取消隐藏」 |
| `Tests/LaunchAppTests/ItemMenuTests.swift` | 修改 | 对应测试 |
| `Sources/LaunchApp/LauncherModel.swift` | 修改 | 隐藏应用列表、搜索显示隐藏、回第一页、壁纸、空白处主菜单 |
| `Tests/LaunchAppTests/LauncherModelSettingsTests.swift` | 新建 | 对应测试 |
| `Tests/LaunchAppTests/LauncherModelMenuTests.swift` | 修改 | 空白处改为主菜单 |
| `Sources/LaunchApp/KeyCommandMapper.swift`、`LauncherController.swift` | 修改 | ⌘, 与 `.settings` 关闭原因 |
| `Tests/LaunchAppTests/KeyCommandMapperTests.swift`、`LauncherControllerTests.swift` | 修改 | 对应测试 |
| `Sources/LaunchApp/SettingsWindowController.swift` | 新建 | 设置窗口 |
| `Sources/LaunchApp/SettingsView.swift` | 新建 | 三页表单 |
| `Sources/LaunchApp/LauncherView.swift` | 修改 | 背景、名称、半透明、「…」按钮、拖动卡片名称 |
| `Sources/LaunchApp/ScreenPresenter.swift` | 修改 | `onPresent` |
| `Sources/LaunchApp/ItemDragController.swift` | 修改 | 主菜单弹出、文本框上不拦截 |
| `Sources/LaunchApp/StatusItemController.swift` | 修改 | 「设置…」与图标显隐 |
| `Sources/LaunchApp/LaunchApp.swift` | 修改 | 组装与设置同步 |

命令（项目根目录）：`swift build 2>&1 | grep -E "error:|warning:|Build complete"`；`swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | awk '/Executed/{print $2} /error|with [1-9]/{print}' | sort -n | uniq | tail -3`（输出两套测试的总数，无错误行即通过）；`swift test --filter <类名>`；安装 `LAUNCH_SIGN_IDENTITY="Apple Development: zhaoyingkun@163.com" ./scripts/build-app.sh --install`。

---

### Task 1: LauncherSettings

**Files:**
- Create: `Sources/LaunchApp/LauncherSettings.swift`
- Test: `Tests/LaunchAppTests/LauncherSettingsTests.swift`

- [ ] **Step 1: 失败测试**

```swift
import XCTest
@testable import LaunchApp

@MainActor
final class LauncherSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "LauncherSettingsTests-\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return UserDefaults(suiteName: name)!
    }

    func testDefaults() {
        let settings = LauncherSettings(defaults: makeDefaults())

        XCTAssertEqual(settings.reopenBehavior, .resume)
        XCTAssertEqual(settings.background, .glass)
        XCTAssertEqual(settings.dimming, 0.47)
        XCTAssertFalse(settings.hidesNames)
        XCTAssertFalse(settings.showsHiddenAppsInSearch)
        XCTAssertTrue(settings.showsMenuBarIcon)
    }

    func testChangesPersist() {
        let defaults = makeDefaults()
        let settings = LauncherSettings(defaults: defaults)

        settings.reopenBehavior = .firstPage
        settings.background = .blurredWallpaper
        settings.dimming = 0.2
        settings.hidesNames = true
        settings.showsHiddenAppsInSearch = true
        settings.showsMenuBarIcon = false

        let reloaded = LauncherSettings(defaults: defaults)
        XCTAssertEqual(reloaded.reopenBehavior, .firstPage)
        XCTAssertEqual(reloaded.background, .blurredWallpaper)
        XCTAssertEqual(reloaded.dimming, 0.2)
        XCTAssertTrue(reloaded.hidesNames)
        XCTAssertTrue(reloaded.showsHiddenAppsInSearch)
        XCTAssertFalse(reloaded.showsMenuBarIcon)
    }
}
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter LauncherSettingsTests 2>&1 | grep -E "error:" | head -2`
Expected: 编译错误，找不到 `LauncherSettings`。

- [ ] **Step 3: 实现** `Sources/LaunchApp/LauncherSettings.swift`

```swift
import Foundation
import Observation

enum ReopenBehavior: String, CaseIterable {
    case resume
    case firstPage
}

enum LauncherBackgroundStyle: String, CaseIterable {
    case glass
    case blurredWallpaper
    case wallpaper
}

@MainActor
@Observable
final class LauncherSettings {
    static let defaultDimming = 0.47

    @ObservationIgnored private let defaults: UserDefaults

    var reopenBehavior: ReopenBehavior {
        didSet { defaults.set(reopenBehavior.rawValue, forKey: Key.reopenBehavior) }
    }

    var background: LauncherBackgroundStyle {
        didSet { defaults.set(background.rawValue, forKey: Key.background) }
    }

    var dimming: Double {
        didSet { defaults.set(dimming, forKey: Key.dimming) }
    }

    var hidesNames: Bool {
        didSet { defaults.set(hidesNames, forKey: Key.hidesNames) }
    }

    var showsHiddenAppsInSearch: Bool {
        didSet { defaults.set(showsHiddenAppsInSearch, forKey: Key.showsHiddenAppsInSearch) }
    }

    var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reopenBehavior = defaults.string(forKey: Key.reopenBehavior).flatMap(ReopenBehavior.init) ?? .resume
        background = defaults.string(forKey: Key.background).flatMap(LauncherBackgroundStyle.init) ?? .glass
        dimming = defaults.object(forKey: Key.dimming) as? Double ?? Self.defaultDimming
        hidesNames = defaults.bool(forKey: Key.hidesNames)
        showsHiddenAppsInSearch = defaults.bool(forKey: Key.showsHiddenAppsInSearch)
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
    }

    private enum Key {
        static let reopenBehavior = "reopenBehavior"
        static let background = "background"
        static let dimming = "dimming"
        static let hidesNames = "hidesNames"
        static let showsHiddenAppsInSearch = "showsHiddenAppsInSearch"
        static let showsMenuBarIcon = "showsMenuBarIcon"
    }
}
```

- [ ] **Step 4: 确认通过**

Run: `swift test --filter LauncherSettingsTests 2>&1 | grep -E "error:|failed \(|Executed" | tail -2`
Expected: `Executed 2 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/LauncherSettings.swift Tests/LaunchAppTests/LauncherSettingsTests.swift
git commit -m "feat(设置): 设置项及其保存"
```

---

### Task 2: WallpaperProvider

**Files:**
- Create: `Sources/LaunchApp/WallpaperProvider.swift`
- Test: `Tests/LaunchAppTests/WallpaperProviderTests.swift`

- [ ] **Step 1: 失败测试**

```swift
import AppKit
import XCTest
@testable import LaunchApp

@MainActor
final class WallpaperProviderTests: XCTestCase {
    private func makeImageFile() throws -> URL {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let url = try makeTemporaryDirectory().appending(path: "wallpaper.png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func scaling(_ value: NSImageScaling) -> NSNumber {
        NSNumber(value: value.rawValue)
    }

    func testFillFollowsWallpaperOptions() throws {
        let url = try makeImageFile()
        let provider = WallpaperProvider()

        XCTAssertEqual(
            provider.wallpaper(url: url, options: [.imageScaling: scaling(.scaleProportionallyUpOrDown), .allowClipping: true])?.fill,
            .aspectFill
        )
        XCTAssertEqual(
            provider.wallpaper(url: url, options: [.imageScaling: scaling(.scaleProportionallyUpOrDown), .allowClipping: false])?.fill,
            .aspectFit
        )
        XCTAssertEqual(provider.wallpaper(url: url, options: [.imageScaling: scaling(.scaleAxesIndependently)])?.fill, .stretch)
        XCTAssertEqual(provider.wallpaper(url: url, options: [.imageScaling: scaling(.scaleNone)])?.fill, .center)
        XCTAssertEqual(provider.wallpaper(url: url, options: [:])?.fill, .aspectFill)
    }

    func testMissingImageGivesNothingAndImagesAreCached() throws {
        let url = try makeImageFile()
        let provider = WallpaperProvider()

        XCTAssertNil(provider.wallpaper(url: nil, options: [:]))
        XCTAssertNil(provider.wallpaper(url: url.appending(path: "missing.png"), options: [:]))
        XCTAssertTrue(provider.wallpaper(url: url, options: [:])?.image === provider.wallpaper(url: url, options: [:])?.image)
    }
}
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter WallpaperProviderTests 2>&1 | grep -E "error:" | head -2`
Expected: 编译错误，找不到 `WallpaperProvider`。

- [ ] **Step 3: 实现** `Sources/LaunchApp/WallpaperProvider.swift`

```swift
import AppKit

struct Wallpaper {
    enum Fill: Equatable {
        case aspectFill
        case aspectFit
        case stretch
        case center
    }

    let image: NSImage
    let fill: Fill
    let fillColor: NSColor?
}

@MainActor
final class WallpaperProvider {
    private var cache: [URL: NSImage] = [:]

    func wallpaper(for screen: NSScreen) -> Wallpaper? {
        wallpaper(
            url: NSWorkspace.shared.desktopImageURL(for: screen),
            options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        )
    }

    func wallpaper(url: URL?, options: [NSWorkspace.DesktopImageOptionKey: Any]) -> Wallpaper? {
        guard let url, let image = image(at: url) else {
            return nil
        }
        let scaling = (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) }
        let allowsClipping = options[.allowClipping] as? Bool ?? true
        let fill: Wallpaper.Fill
        switch scaling {
        case .scaleAxesIndependently:
            fill = .stretch
        case .scaleNone:
            fill = .center
        default:
            fill = allowsClipping ? .aspectFill : .aspectFit
        }
        return Wallpaper(image: image, fill: fill, fillColor: options[.fillColor] as? NSColor)
    }

    private func image(at url: URL) -> NSImage? {
        if let cached = cache[url] {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache[url] = image
        return image
    }
}
```

- [ ] **Step 4: 确认通过**

Run: `swift test --filter WallpaperProviderTests 2>&1 | grep -E "error:|failed \(|Executed" | tail -2`
Expected: `Executed 2 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/WallpaperProvider.swift Tests/LaunchAppTests/WallpaperProviderTests.swift
git commit -m "feat(设置): 读取屏幕壁纸"
```

---

### Task 3: ItemMenu 主菜单与取消隐藏

**Files:**
- Modify: `Sources/LaunchApp/ItemMenu.swift`、`Sources/LaunchApp/LauncherModel.swift`（`performMenuCommand` 补分支）、`Sources/LaunchApp/LaunchApp.swift`（`performMenuCommand` 补分支）
- Test: `Tests/LaunchAppTests/ItemMenuTests.swift`

- [ ] **Step 1: 失败测试**（`ItemMenuTests` 类末尾）

```swift
    func testMainMenu() {
        var chosen: [ItemMenuCommand] = []
        let builder = ItemMenu { chosen.append($0) }
        let menu = builder.makeMenu(.main)

        XCTAssertEqual(menu.items.map(\.title), ["设置…"])
        trigger(menu.items[0])
        XCTAssertEqual(chosen, [.openSettings])
    }

    func testHiddenAppOffersUnhide() {
        var chosen: [ItemMenuCommand] = []
        let app = makeApps(count: 1)[0]
        let builder = ItemMenu { chosen.append($0) }
        let menu = builder.makeMenu(.app(AppMenuContent(
            app: app,
            canOpen: true,
            canEdit: true,
            canUninstall: false,
            isHidden: true
        )))

        XCTAssertEqual(menu.items.map(\.title), ["打开", "", "在访达中显示", "显示简介", "", "取消隐藏"])
        trigger(menu.items[5])
        XCTAssertEqual(chosen, [.unhide(app)])
    }
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter ItemMenuTests 2>&1 | grep -E "error:" | head -2`
Expected: 编译错误，`ItemMenuContent` 没有 `main`。

- [ ] **Step 3: 实现**

`AppMenuContent` 增加（带默认值，现有调用不变）：

```swift
    var isHidden = false
```

`ItemMenuContent` 增加 `case main`；`ItemMenuCommand` 增加 `case openSettings` 与 `case unhide(CatalogApp)`。

`makeMenu` 的 `switch` 增加：

```swift
        case .main:
            menu.addItem(item("设置…", .openSettings))
```

`addAppItems` 中「隐藏」一行改为：

```swift
        if content.isHidden {
            menu.addItem(item("取消隐藏", .unhide(app), isEnabled: content.canEdit))
        } else {
            menu.addItem(item("隐藏", .hide(.app(app.identity.stableKey)), isEnabled: content.canEdit))
        }
```

`LauncherModel.performMenuCommand` 最后一个分支改为 `case .open, .revealInFinder, .showInfo, .moveToTrash, .openSettings, .unhide:`；`performSelectionCommand` 中忽略的分支同样补上 `.openSettings, .unhide`。

`LaunchApp.performMenuCommand` 增加（`default` 之前）：

```swift
        case .unhide(let app):
            layoutCoordinator.unhide(app)
```

（`.openSettings` 到 Task 7 接入设置窗口时处理，此前走 `default` 交给模型忽略。）

- [ ] **Step 4: 确认通过**

Run: `swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | awk '/Executed/{print $2} /error|with [1-9]/{print}' | sort -n | uniq | tail -3`
Expected: 只有两个数字（两套测试总数），无错误行。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/ItemMenu.swift Sources/LaunchApp/LauncherModel.swift Sources/LaunchApp/LaunchApp.swift Tests/LaunchAppTests/ItemMenuTests.swift
git commit -m "feat(设置): 主菜单与隐藏应用的取消隐藏"
```

---

### Task 4: LauncherModel 设置相关状态

**Files:**
- Modify: `Sources/LaunchApp/LauncherModel.swift`、`Sources/LaunchApp/LaunchApp.swift`、`Tests/LaunchAppTests/LauncherModelMenuTests.swift`
- Test: `Tests/LaunchAppTests/LauncherModelSettingsTests.swift`

- [ ] **Step 1: 失败测试** `Tests/LaunchAppTests/LauncherModelSettingsTests.swift`

```swift
import CoreGraphics
import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelSettingsTests: XCTestCase {
    private let layout = LauncherHomeLayout(
        screenSize: LauncherHomeLayout.canvasSize,
        referenceSize: LauncherHomeLayout.canvasSize
    )

    private var gridFrame: CGRect {
        CGRect(x: 0, y: 135, width: layout.contentSize.width, height: layout.gridHeight)
    }

    private func center(_ index: Int) -> CGPoint {
        let rect = GridHitTester(layout: layout, frame: gridFrame).tileRect(index)
        return CGPoint(x: rect.midX, y: rect.minY + layout.tilePadding + layout.iconSide / 2)
    }

    @MainActor
    private func makeModel(apps: [CatalogApp]) -> LauncherModel {
        let model = LauncherModel(apps: apps)
        model.updateLayout(LauncherPagination.pages(apps.map(ResolvedItem.app), capacity: LauncherHomeLayout.pageCapacity))
        model.canEditLayout = true
        model.updateHomeLayout(layout)
        model.updateGridFrame(gridFrame)
        return model
    }

    @MainActor
    func testReopenKeepsPageUnlessFirstPageIsAsked() {
        let model = makeModel(apps: makeApps(count: 40))
        model.selectPage(1)

        model.prepareForPresentation()
        XCTAssertEqual(model.currentPage, 1)

        model.reopensAtFirstPage = true
        model.prepareForPresentation()
        XCTAssertEqual(model.currentPage, 0)
    }

    @MainActor
    func testSearchCanIncludeHiddenApps() {
        let apps = makeApps(count: 3)
        let model = makeModel(apps: apps)
        model.updateHiddenApps([apps[1]])
        model.setQuery("App")

        XCTAssertEqual(model.hiddenApps, [apps[1]])
        XCTAssertEqual(model.results, [apps[0], apps[2]])

        model.showsHiddenAppsInSearch = true
        XCTAssertEqual(model.results, apps)
        XCTAssertTrue(model.isHiddenApp(apps[1]))
        XCTAssertFalse(model.isHiddenApp(apps[0]))
        XCTAssertEqual(
            model.contextMenu(at: center(1)),
            .app(AppMenuContent(app: apps[1], canOpen: true, canEdit: true, canUninstall: false, isHidden: true))
        )
    }

    @MainActor
    func testBlankPointGivesMainMenu() {
        let model = makeModel(apps: makeApps(count: 3))

        XCTAssertEqual(model.contextMenu(at: CGPoint(x: 5, y: 5)), .main)
    }

    @MainActor
    func testWallpaperIsStoredForView() {
        let model = makeModel(apps: [])
        let wallpaper = Wallpaper(image: NSImage(size: CGSize(width: 1, height: 1)), fill: .aspectFill, fillColor: nil)

        model.updateWallpaper(wallpaper)
        XCTAssertTrue(model.wallpaper?.image === wallpaper.image)

        model.updateWallpaper(nil)
        XCTAssertNil(model.wallpaper)
    }
}
```

文件顶部 `import CoreGraphics` 后加 `import AppKit`（`NSImage`）。

`LauncherModelMenuTests.testAppAndFolderMenus` 中 `XCTAssertNil(model.contextMenu(at: CGPoint(x: 5, y: 5)))` 改为 `XCTAssertEqual(model.contextMenu(at: CGPoint(x: 5, y: 5)), .main)`。

- [ ] **Step 2: 确认失败**

Run: `swift test --filter LauncherModelSettingsTests 2>&1 | grep -E "error:" | head -2`
Expected: 编译错误，找不到 `reopensAtFirstPage` 等。

- [ ] **Step 3: 实现** `LauncherModel.swift`

文件顶部 `import CoreGraphics` 前加 `import AppKit`。

`private(set) var hiddenApps: Set<AppIdentity> = []` 改为：

```swift
    private(set) var hiddenApps: [CatalogApp] = []
    private(set) var wallpaper: Wallpaper?
    var showsHiddenAppsInSearch = false
    @ObservationIgnored var reopensAtFirstPage = false
```

`results`：

```swift
    var results: [CatalogApp] {
        let hidden = showsHiddenAppsInSearch ? [] : Set(hiddenApps.map(\.identity))
        return SearchService.results(for: query, in: apps, hidden: hidden)
    }
```

`updateHiddenApps` 改为：

```swift
    func updateHiddenApps(_ apps: [CatalogApp]) {
        guard apps != hiddenApps else {
            return
        }
        hiddenApps = apps
        normalizeState()
    }

    func isHiddenApp(_ app: CatalogApp) -> Bool {
        hiddenApps.contains(app)
    }

    func updateWallpaper(_ wallpaper: Wallpaper?) {
        self.wallpaper = wallpaper
    }
```

`contextMenu(at:)`：`guard let press = itemPress(at: point) else { return nil }` 改为 `return .main`；`.app` 分支的 `AppMenuContent(...)` 增加 `isHidden: isHiddenApp(app)`。

`prepareForPresentation()` 中 `setGridPage(clampedPage(currentPage), animated: false)` 改为：

```swift
        setGridPage(reopensAtFirstPage ? 0 : clampedPage(currentPage), animated: false)
```

`LaunchApp.swift`：`controller.model.updateHiddenApps(layoutCoordinator.hiddenApps)` 不变（参数已是 `[CatalogApp]`）。

- [ ] **Step 4: 确认通过**

Run: `swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | awk '/Executed/{print $2} /error|with [1-9]/{print}' | sort -n | uniq | tail -3`
Expected: 无错误行。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/LauncherModel.swift Tests/LaunchAppTests/LauncherModelSettingsTests.swift Tests/LaunchAppTests/LauncherModelMenuTests.swift
git commit -m "feat(设置): 模型支持回第一页、搜索显示隐藏应用与壁纸"
```

---

### Task 5: ⌘, 与打开设置时关闭启动器

**Files:**
- Modify: `Sources/LaunchApp/KeyCommandMapper.swift`、`Sources/LaunchApp/LauncherController.swift`
- Test: `Tests/LaunchAppTests/KeyCommandMapperTests.swift`、`Tests/LaunchAppTests/LauncherControllerTests.swift`

- [ ] **Step 1: 失败测试**

`KeyCommandMapperTests` 类末尾：

```swift
    func testCommandCommaOpensSettings() {
        XCTAssertEqual(map(43, [.command]), .openSettings)
        XCTAssertNil(map(43))
    }
```

`LauncherControllerTests`：`testHideReasonsDecideFocusRestoration` 的 `reasons` 末尾加 `.settings`，期望数组末尾加 `false`。在 `makeController` 之前加：

```swift
    @MainActor
    func testOpenSettingsCommandIsForwarded() {
        let (controller, _) = makeController()
        var opened = 0
        controller.onOpenSettings = { opened += 1 }
        controller.show()

        controller.handle(.openSettings)

        XCTAssertEqual(opened, 1)
    }
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter "KeyCommandMapperTests|LauncherControllerTests" 2>&1 | grep -E "error:" | head -2`
Expected: 编译错误，`LauncherCommand` 没有 `openSettings`。

- [ ] **Step 3: 实现**

`LauncherCommand` 增加 `case openSettings`；`KeyCommandMapper` 的 `switch` 在 `default` 前加：

```swift
        case (43, [.command]):
            return .openSettings
```

`LauncherHideReason` 增加 `case settings`，`restoresPreviousApp` 中归入 `false` 一组：

```swift
        case .launchedApp, .resignedActive, .settings:
            false
```

`LauncherController` 增加 `var onOpenSettings: (() -> Void)?`，`handle(_:)` 增加：

```swift
        case .openSettings:
            onOpenSettings?()
```

- [ ] **Step 4: 确认通过**

Run: `swift test --filter "KeyCommandMapperTests|LauncherControllerTests" 2>&1 | grep -E "error:|failed \(|Executed" | tail -2`
Expected: `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/KeyCommandMapper.swift Sources/LaunchApp/LauncherController.swift Tests/LaunchAppTests/KeyCommandMapperTests.swift Tests/LaunchAppTests/LauncherControllerTests.swift
git commit -m "feat(设置): ⌘, 打开设置"
```

---

### Task 6: 设置窗口与设置页

**Files:**
- Create: `Sources/LaunchApp/SettingsWindowController.swift`、`Sources/LaunchApp/SettingsView.swift`

SwiftUI 表单没有单元测试，靠 Task 8 的 e2e 验证。

- [ ] **Step 1: `SettingsWindowController.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let onWillShow: () -> Void
    private let makeContent: () -> AnyView
    private var window: NSWindow?

    init(onWillShow: @escaping () -> Void, makeContent: @escaping () -> AnyView) {
        self.onWillShow = onWillShow
        self.makeContent = makeContent
    }

    func show() {
        onWillShow()
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            center(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Launch 设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: makeContent())
        return window
    }

    private func center(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }
}
```

- [ ] **Step 2: `SettingsView.swift`**

```swift
import AppKit
import KeyboardShortcuts
import LaunchCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: LauncherSettings
    let model: LauncherModel
    let loginItemService: LoginItemService
    let hasHotKeyConflict: () -> Bool
    let onUnhide: (CatalogApp) -> Void
    let onUnhideAll: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(
                settings: settings,
                loginItemService: loginItemService,
                hasHotKeyConflict: hasHotKeyConflict
            )
            .tabItem { Label("通用", systemImage: "gearshape") }
            AppearanceSettingsView(settings: settings)
                .tabItem { Label("外观", systemImage: "paintpalette") }
            HiddenAppsSettingsView(settings: settings, model: model, onUnhide: onUnhide, onUnhideAll: onUnhideAll)
                .tabItem { Label("应用", systemImage: "eye.slash") }
        }
        .frame(width: 520, height: 440)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: LauncherSettings
    let loginItemService: LoginItemService
    let hasHotKeyConflict: () -> Bool

    @State private var startsAtLogin = false
    @State private var hasConflict = false

    var body: some View {
        Form {
            Toggle("开机启动", isOn: Binding(get: { startsAtLogin }, set: setStartsAtLogin))
                .disabled(!loginItemService.isAvailable)
            if !loginItemService.isAvailable {
                Text("需安装到 ~/Applications 后才能开机启动")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("唤起快捷键") {
                KeyboardShortcuts.Recorder(for: .toggleLauncher) { _ in
                    hasConflict = hasHotKeyConflict()
                }
            }
            if hasConflict {
                Text("⚠︎ 与 LaunchOS 的快捷键冲突")
                    .foregroundStyle(.orange)
            }
            Toggle("显示菜单栏图标", isOn: $settings.showsMenuBarIcon)
            Picker("重新打开时", selection: $settings.reopenBehavior) {
                Text("停在上次的位置").tag(ReopenBehavior.resume)
                Text("回到第一页").tag(ReopenBehavior.firstPage)
            }
            .pickerStyle(.radioGroup)
        }
        .formStyle(.grouped)
        .onAppear {
            startsAtLogin = loginItemService.isEnabled
            hasConflict = hasHotKeyConflict()
        }
    }

    private func setStartsAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
        } catch {
            NSAlert(error: error).runModal()
        }
        startsAtLogin = loginItemService.isEnabled
    }
}

private struct AppearanceSettingsView: View {
    @Bindable var settings: LauncherSettings

    var body: some View {
        Form {
            Picker("背景", selection: $settings.background) {
                Text("玻璃材质").tag(LauncherBackgroundStyle.glass)
                Text("模糊壁纸").tag(LauncherBackgroundStyle.blurredWallpaper)
                Text("系统壁纸").tag(LauncherBackgroundStyle.wallpaper)
            }
            .pickerStyle(.radioGroup)
            LabeledContent("暗度") {
                HStack {
                    Slider(value: $settings.dimming, in: 0 ... 0.8)
                    Text("\(Int((settings.dimming * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Toggle("隐藏图标名称", isOn: $settings.hidesNames)
        }
        .formStyle(.grouped)
    }
}

private struct HiddenAppsSettingsView: View {
    @Bindable var settings: LauncherSettings
    let model: LauncherModel
    let onUnhide: (CatalogApp) -> Void
    let onUnhideAll: () -> Void

    var body: some View {
        Form {
            Toggle("在搜索结果中显示隐藏应用", isOn: $settings.showsHiddenAppsInSearch)
            Section("隐藏的应用") {
                if model.hiddenApps.isEmpty {
                    Text("没有隐藏的应用")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.hiddenApps, id: \.identity) { app in
                        HStack {
                            Image(nsImage: IconCache.shared.icon(for: app.identity.path))
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text(app.displayName)
                            Spacer()
                            Button("取消隐藏") {
                                onUnhide(app)
                            }
                        }
                    }
                }
            }
            Button("全部取消隐藏", action: onUnhideAll)
                .disabled(model.hiddenApps.isEmpty)
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 3: 构建**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete"`
Expected: `Build complete`，无警告。

- [ ] **Step 4: 提交**

```bash
git add Sources/LaunchApp/SettingsWindowController.swift Sources/LaunchApp/SettingsView.swift
git commit -m "feat(设置): 设置窗口的通用、外观与应用三页"
```

---

### Task 7: 界面与接入

**Files:**
- Modify: `Sources/LaunchApp/LauncherView.swift`、`ScreenPresenter.swift`、`ItemDragController.swift`、`StatusItemController.swift`、`LaunchApp.swift`

- [ ] **Step 1: `LauncherView.swift`**

文件中（`SearchPresentation` 之前）加入：

```swift
extension EnvironmentValues {
    @Entry var showsItemNames = true
}
```

`LauncherView` 增加属性 `let settings: LauncherSettings`（在 `model` 之后）与 `let onMainMenu: () -> Void`（在 `onLaunch` 之后）。

`body` 中的背景：

```swift
                Rectangle()
                    .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.47))
                    .ignoresSafeArea()
                    .onTapGesture(perform: onBackgroundClick)
```

改为：

```swift
                LauncherBackground(model: model, settings: settings)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onBackgroundClick)
```

`body` 最外层 `GeometryReader { ... }` 之后（`.onExitCommand` 之前）加：

```swift
        .environment(\.showsItemNames, !settings.hidesNames)
```

`itemView(_:layout:isSelected:)` 的 `.app` 分支给磁贴加半透明：

```swift
            LauncherAppTile(app: app, layout: layout, isSelected: isSelected) {
                if !dragTracker.suppressesTap {
                    onLaunch(app)
                }
            }
            .opacity(model.isHiddenApp(app) ? 0.45 : 1)
```

搜索栏的「…」：

```swift
            } else if SearchPresentation.showsMoreControl(for: model.query) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: layout.searchIconSize))
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityLabel("更多选项")
            }
```

改为：

```swift
            } else if SearchPresentation.showsMoreControl(for: model.query) {
                Button(action: onMainMenu) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: layout.searchIconSize))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多选项")
            }
```

`LauncherAppTile` 与 `LauncherFolderTile` 各加 `@Environment(\.showsItemNames) private var showsName`，名称 `Text(...)` 修饰链末尾（`.frame(height: layout.labelHeight)` 之后）加 `.opacity(showsName ? 1 : 0)`。

`DragCardRenderer.image` 增加 `showsName: Bool` 参数（在 `count` 之后）并传给 `DragCard(item:count:showsName:layout:)`；`DragCard` 增加 `let showsName: Bool`，`label(_:)` 返回的 `Text` 末尾加 `.opacity(showsName ? 1 : 0)`。

`MarqueeOverlay` 之后新增：

```swift
// 只有这一层读取背景设置与壁纸，切换时不重建网格
private struct LauncherBackground: View {
    let model: LauncherModel
    let settings: LauncherSettings

    var body: some View {
        ZStack {
            if settings.background != .glass, let wallpaper = model.wallpaper {
                WallpaperImage(wallpaper: wallpaper)
                    .blur(radius: settings.background == .blurredWallpaper ? 40 : 0, opaque: true)
            } else {
                Rectangle()
                    .fill(.regularMaterial)
            }
            Color.black.opacity(settings.dimming)
        }
        .contentShape(Rectangle())
    }
}

private struct WallpaperImage: View {
    let wallpaper: Wallpaper

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: wallpaper.fillColor ?? .black)
                switch wallpaper.fill {
                case .aspectFill:
                    image.aspectRatio(contentMode: .fill)
                case .aspectFit:
                    image.aspectRatio(contentMode: .fit)
                case .stretch:
                    image
                case .center:
                    Image(nsImage: wallpaper.image)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var image: some View {
        Image(nsImage: wallpaper.image)
            .resizable()
            .interpolation(.high)
    }
}
```

- [ ] **Step 2: `ScreenPresenter.swift`**

增加属性 `var onPresent: ((NSScreen) -> Void)?`；`present()` 中 `guard let screen = targetScreen() else { return }` 之后加 `onPresent?(screen)`。

- [ ] **Step 3: `ItemDragController.swift`**

`contextClick` 改为（文本框上交给系统的编辑菜单）：

```swift
    private func contextClick(at point: CGPoint, event: NSEvent) -> NSEvent? {
        guard let view = presenter.contentView, !isTextInput(at: event, in: view),
              let content = model.contextMenu(at: point) else {
            return event
        }
        let location = view.convert(event.locationInWindow, from: nil)
        itemMenu.makeMenu(content).popUp(positioning: nil, at: location, in: view)
        return nil
    }

    func showMainMenu() {
        guard let view = presenter.contentView, let window = view.window else {
            return
        }
        let location = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        itemMenu.makeMenu(.main).popUp(positioning: nil, at: location, in: view)
    }

    private func isTextInput(at event: NSEvent, in view: NSView) -> Bool {
        var hit = view.hitTest(view.convert(event.locationInWindow, from: nil))
        while let current = hit {
            if current is NSTextView || current is NSTextField {
                return true
            }
            hit = current.superview
        }
        return false
    }
```

- [ ] **Step 4: `StatusItemController.swift`**

属性：

```swift
    private let settingsItem = NSMenuItem(title: "设置…", action: nil, keyEquivalent: ",")
    private let onOpenSettings: () -> Void
```

`init` 增加参数 `onOpenSettings: @escaping () -> Void`（在 `onOpen` 之后）并赋值；`super.init()` 之后加：

```swift
        settingsItem.action = #selector(openSettings)
        settingsItem.target = self
```

`menu.items` 改为 `[openItem, settingsItem, conflictItem, .separator(), loginItem, importItem, restoreItem, hiddenItem, .separator(), quitItem]`。

新增：

```swift
    func setIconVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    @objc private func openSettings() {
        onOpenSettings()
    }
```

- [ ] **Step 5: `LaunchApp.swift`**

属性（`appActions` 之后）：

```swift
    private let settings = LauncherSettings()
    private let wallpaperProvider = WallpaperProvider()
    private lazy var settingsWindow = SettingsWindowController(
        onWillShow: { [weak self] in self?.controller.hide(.settings) },
        makeContent: { [unowned self] in
            AnyView(SettingsView(
                settings: settings,
                model: controller.model,
                loginItemService: loginItemService,
                hasHotKeyConflict: { [weak self] in self?.hasHotKeyConflict() ?? false },
                onUnhide: { [weak self] app in self?.layoutCoordinator.unhide(app) },
                onUnhideAll: { [weak self] in self?.layoutCoordinator.unhideAll() }
            ))
        }
    )
```

文件顶部加 `import SwiftUI`。

`presenter.setContent(LauncherView(...))` 改为传入 `settings: settings` 与 `onMainMenu: { [weak self] in self?.itemDragController.showMainMenu() }`。

`applicationDidFinishLaunching` 中 `controller.onUndoLayoutEdit = ...` 之后加：

```swift
        controller.onOpenSettings = { [weak self] in
            self?.settingsWindow.show()
        }
        presenter.onPresent = { [weak self] screen in
            guard let self else {
                return
            }
            let wallpaper = settings.background == .glass ? nil : wallpaperProvider.wallpaper(for: screen)
            controller.model.updateWallpaper(wallpaper)
        }
```

`StatusItemController(...)` 增加 `onOpenSettings: { [weak self] in self?.settingsWindow.show() }`；其后（`let watcher = ...` 之前）调用 `applySettings()`。

`performMenuCommand` 增加（`default` 之前）：

```swift
        case .openSettings:
            settingsWindow.show()
```

`dragImage(for:count:)` 中改为 `DragCardRenderer.image(for: item, count: count, showsName: !settings.hidesNames, layout: layout, scale: presenter.backingScaleFactor)`。

新增：

```swift
    // 设置变化时同步到模型与菜单栏；观察只触发一次，需要重新登记
    private func applySettings() {
        withObservationTracking {
            controller.model.reopensAtFirstPage = settings.reopenBehavior == .firstPage
            controller.model.showsHiddenAppsInSearch = settings.showsHiddenAppsInSearch
            statusItemController?.setIconVisible(settings.showsMenuBarIcon)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySettings()
            }
        }
    }
```

- [ ] **Step 6: 构建、测试、安装**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete"`、测试命令，再执行安装命令。
Expected: `Build complete`，无警告；无错误行；安装成功。

- [ ] **Step 7: 提交**

```bash
git add Sources/LaunchApp/LauncherView.swift Sources/LaunchApp/ScreenPresenter.swift Sources/LaunchApp/ItemDragController.swift Sources/LaunchApp/StatusItemController.swift Sources/LaunchApp/LaunchApp.swift
git commit -m "feat(设置): 背景、隐藏名称与主菜单接入设置"
```

---

### Task 8: 目标机验证与文档

- [ ] **Step 1: 离屏渲染核对外观**

临时测试 `Tests/LaunchAppTests/SettingsRenderProbe.swift`（核对后删除，不提交）：用 `NSHostingView(rootView: LauncherView(...))` 以 1512×982 渲染四种组合（玻璃 + 47%、模糊壁纸 + 47%、系统壁纸 + 20%、隐藏名称），壁纸取 `WallpaperProvider().wallpaper(for: NSScreen.screens[0])`，`cacheDisplay(in:to:)` 写入 `/tmp/launch-5a-*.png`，逐张查看：背景按选项变化、暗度深浅不同、隐藏名称时图标下无文字且位置不变。

```swift
import AppKit
import LaunchCore
import SwiftUI
import XCTest
@testable import LaunchApp

@MainActor
final class SettingsRenderProbe: XCTestCase {
    func testRender() throws {
        let apps = (0 ..< 12).map { CatalogApp(identity: AppIdentity(bundleIdentifier: nil, path: "/System/Applications/Calculator.app"), displayName: "应用 \($0)") }
        let cases: [(String, LauncherBackgroundStyle, Double, Bool)] = [
            ("glass", .glass, 0.47, false), ("blur", .blurredWallpaper, 0.47, false),
            ("wallpaper", .wallpaper, 0.2, false), ("names", .glass, 0.47, true),
        ]
        for (name, background, dimming, hidesNames) in cases {
            let defaults = UserDefaults(suiteName: "probe-\(name)")!
            let settings = LauncherSettings(defaults: defaults)
            settings.background = background
            settings.dimming = dimming
            settings.hidesNames = hidesNames
            let model = LauncherModel(apps: apps)
            model.updateLayout([apps.map(ResolvedItem.app)])
            model.updateWallpaper(WallpaperProvider().wallpaper(for: NSScreen.screens[0]))
            let view = NSHostingView(rootView: LauncherView(
                model: model, settings: settings, onEscape: {}, onBackgroundClick: {}, onLaunch: { _ in }, onMainMenu: {}
            ))
            view.frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/launch-5a-\(name).png"))
            defaults.removePersistentDomain(forName: "probe-\(name)")
        }
    }
}
```

Run: `swift test --filter SettingsRenderProbe 2>&1 | grep -E "error:|Executed" | tail -1`，用 Read 查看四张图后 `rm Tests/LaunchAppTests/SettingsRenderProbe.swift /tmp/launch-5a-*.png`。

- [ ] **Step 2: 备份设置与布局**

```bash
L="$HOME/Library/Application Support/Launch"; B=$(mktemp -d); echo "$B" > /tmp/launch-layout-backup-dir
cp "$L/layout.json" "$B/"; [ -f "$L/layout.json.backup" ] && cp "$L/layout.json.backup" "$B/"
shasum -a 256 "$L"/layout.json* | tee "$B/sha.txt"
defaults export dev.yocn.launch "$B/defaults.plist"
```

- [ ] **Step 3: e2e**

```bash
E=$(mktemp -d); echo "$E" > /tmp/launch-e2e-5a-dir; mkdir -p "$E/s"
cp "$(cat /tmp/launch-e2e-4b-dir)/prelude.swift" "$E/"
```

`$E/s/main.swift`：

```swift
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IONBF, 0)

func extrasBar() -> AXUIElement? {
    guard let app = appElement(), let bar = attr(app, "AXExtrasMenuBar") else { return nil }
    return (bar as! AXUIElement)
}
func anyMenuItem(_ name: String) -> AXUIElement? {
    menuItem(name) ?? extrasBar().map { all($0) }?.first { role($0) == kAXMenuItemRole && title($0) == name }
}
func press(_ element: AXUIElement?) { if let element { AXUIElementPerformAction(element, kAXPressAction as CFString) }; wait(1.0) }
func settingsWindow() -> AXUIElement? { windows().first { title($0) == "Launch 设置" } }
func control(_ name: String, role wanted: String) -> AXUIElement? {
    settingsWindow().map { all($0) }?.first { role($0) == wanted && (title($0) == name || desc($0) == name) }
}
// 分组表单里的开关没有标题，标签是紧挨在前面的一段文字
func toggle(_ label: String) -> AXUIElement? {
    guard let window = settingsWindow() else { return nil }
    var seen = false
    for e in all(window) {
        if role(e) == kAXStaticTextRole, (attr(e, kAXValueAttribute) as? String) == label { seen = true }
        if seen, role(e) == kAXCheckBoxRole { return e }
    }
    return nil
}
func closeSettings() { if let w = settingsWindow(), let close = attr(w, kAXCloseButtonAttribute) { press((close as! AXUIElement)) } }
func pref(_ key: String) -> String {
    let p = Process(); let pipe = Pipe(); p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    p.arguments = ["read", "dev.yocn.launch", key]; p.standardOutput = pipe; p.standardError = Pipe()
    try? p.run(); p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

dismissDialogs()
let originalMouse = CGEvent(source: nil)?.location ?? .zero
let appsBefore = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
CGWarpMouseCursorPosition(CGPoint(x: 756, y: 491)); mouse(.mouseMoved, CGPoint(x: 756, y: 491)); wait(0.3)

// S1 「…」主菜单打开设置
openLauncher(); selectPage("第 1 页")
let page1 = names()
if let more = elements().first(where: { role($0) == kAXButtonRole && desc($0) == "更多选项" }).flatMap(frame) {
    click(CGPoint(x: more.midX, y: more.midY)); wait(0.8)
}
check(anyMenuItem("设置…") != nil, "S1 「…」弹出主菜单")
press(anyMenuItem("设置…"))
check(settingsWindow() != nil && !panelVisible(), "S1 打开设置窗口并关闭启动器")

// S2 回到第一页
press(control("回到第一页", role: kAXRadioButtonRole))
check(pref("reopenBehavior") == "firstPage", "S2 写入回到第一页")
closeSettings()
openLauncher(); selectPage("第 2 页")
key(53); wait(0.6)
openLauncher()
check(names() == page1, "S2 重新打开回到第一页")

// S3 空白处右键主菜单
let f = tiles().map(\.frame)
guard f.count > 3 else { print("FAIL 启动器没有显示图标"); exit(1) }
rightClick(CGPoint(x: f[0].minX - 30, y: f[0].midY)); wait(0.8)
check(anyMenuItem("设置…") != nil, "S3 空白处右键弹出主菜单")
press(anyMenuItem("设置…"))
check(settingsWindow() != nil, "S3 打开设置窗口")

// S4 外观与应用开关写入
press(control("外观", role: kAXRadioButtonRole) ?? control("外观", role: kAXButtonRole))
press(toggle("隐藏图标名称"))
check(pref("hidesNames") == "1", "S4 写入隐藏名称")
press(control("模糊壁纸", role: kAXRadioButtonRole))
check(pref("background") == "blurredWallpaper", "S4 写入模糊壁纸")
press(control("应用", role: kAXRadioButtonRole) ?? control("应用", role: kAXButtonRole))
press(toggle("在搜索结果中显示隐藏应用"))
check(pref("showsHiddenAppsInSearch") == "1", "S4 写入搜索显示隐藏应用")
closeSettings()

// S5 设置页取消隐藏
openLauncher()
let target = page1[3]
rightClick(iconCenter(f[3])); wait(0.8)
press(anyMenuItem("隐藏"))
check(!names().contains(target), "S5 隐藏「\(target)」")
key(43, flags: .maskCommand); wait(1.0)
check(settingsWindow() != nil, "S5 ⌘, 打开设置")
press(control("应用", role: kAXRadioButtonRole) ?? control("应用", role: kAXButtonRole))
check(settingsWindow().map { all($0) }?.contains { (attr($0, kAXValueAttribute) as? String) == target || title($0) == target || desc($0) == target } == true, "S5 设置页列出「\(target)」")
press(control("全部取消隐藏", role: kAXButtonRole))
closeSettings()
openLauncher()
check(names() == page1, "S5 取消隐藏后回到原位")
key(53); wait(0.5)

// S6 菜单栏图标与「设置…」
if let item = extrasBar().flatMap({ kids($0).first }) { press(item) }
check(anyMenuItem("设置…") != nil, "S6 菜单栏有「设置…」")
press(anyMenuItem("设置…"))
press(control("通用", role: kAXRadioButtonRole) ?? control("通用", role: kAXButtonRole))
press(toggle("显示菜单栏图标"))
check(extrasBar().map { kids($0).isEmpty } ?? true, "S6 关闭后菜单栏图标消失")
press(toggle("显示菜单栏图标"))
check(extrasBar().map { !kids($0).isEmpty } ?? false, "S6 打开后菜单栏图标恢复")
closeSettings()

let appsAfter = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
let launched = appsAfter.subtracting(appsBefore).subtracting([launchID])
check(launched.isEmpty, "全程未启动应用\(launched.isEmpty ? "" : "（\(launched.sorted())）")")
CGWarpMouseCursorPosition(originalMouse)
print("FAILURES \(failures)")
```

Run: `E=$(cat /tmp/launch-e2e-5a-dir); swiftc -O "$E/prelude.swift" "$E/s/main.swift" -o "$E/s/run" && "$E/s/run"`
Expected: 全部 `PASS`。辅助功能角色与实际不符时，先用 `all(settingsWindow)` 打印角色与标题对照后修正脚本，不改产品代码。

- [ ] **Step 4: 回归第 4b/4c 期 e2e**

Run: `"$(cat /tmp/launch-e2e-4b-dir)/m/run" | tail -1; "$(cat /tmp/launch-e2e-4c-dir)/c/run" | tail -1`
Expected: 两行 `FAILURES 0`。

- [ ] **Step 5: 还原设置与布局**

```bash
B=$(cat /tmp/launch-layout-backup-dir); L="$HOME/Library/Application Support/Launch"
pkill -x LaunchApp; sleep 1
defaults delete dev.yocn.launch 2>/dev/null; defaults import dev.yocn.launch "$B/defaults.plist"
cp "$B/layout.json" "$L/layout.json"; [ -f "$B/layout.json.backup" ] && cp "$B/layout.json.backup" "$L/layout.json.backup"
shasum -a 256 "$L"/layout.json* | diff - "$B/sha.txt" && echo "布局已还原"
defaults export dev.yocn.launch - | diff - <(plutil -convert xml1 -o - "$B/defaults.plist") && echo "设置已还原"
open "$HOME/Applications/Launch.app"
```

- [ ] **Step 6: 文档**

- `README.md`：第 4c 期描述之后加「第 5a 期设置窗口已完成：菜单栏、搜索框右侧「…」、空白处右键或 ⌘, 打开设置，可设置开机启动、唤起快捷键、菜单栏图标、重新打开时回第一页、背景（玻璃材质、模糊壁纸、系统壁纸）与暗度、隐藏图标名称、隐藏的应用及其在搜索中的显示。」；「F4/手势等系统入口与设置窗口仍未实现」改为「行列数、排序与整理、浏览模式、F4/手势等系统入口仍未实现」。
- `docs/architecture.md` 第 7 节第 4 条末尾加：第 5 期 2026-10-20 拆为 5a 设置窗口与显示（已完成，见 `docs/superpowers/specs/2026-10-20-settings-window-design.md`）、行列数、5b 排序与整理、5c 浏览模式、5d 数据。
- `docs/manual-verification.md`：当前结果追加离屏渲染与 e2e 结果、4b/4c 回归、设置与布局还原；待验证追加「快捷键录制（会改动全局快捷键）、壁纸背景在动态壁纸下的退回、真实使用中的暗度与模糊观感」。

```bash
git add README.md docs/architecture.md docs/manual-verification.md
git commit -m "chore(文档): 记录第 5a 期设置窗口的验证结果"
```

---

## Self-Review

- Spec 覆盖：3.1 打开设置 → Task 3（主菜单）、5（⌘,）、6（窗口）、7（「…」、右键空白、菜单栏「设置…」）；3.2 设置内容 → Task 1、6；3.3 效果 → Task 2、4、7；4 组件 → 各任务；5 测试 → Task 1–5 单测、Task 8 离屏渲染与 e2e。
- 类型一致：`LauncherSettings(defaults:)`、`ReopenBehavior`、`LauncherBackgroundStyle`、`Wallpaper(image:fill:fillColor:)`、`WallpaperProvider.wallpaper(for:)/wallpaper(url:options:)`、`AppMenuContent.isHidden`、`ItemMenuContent.main`、`ItemMenuCommand.openSettings/unhide`、`LauncherModel.hiddenApps/showsHiddenAppsInSearch/reopensAtFirstPage/isHiddenApp/updateWallpaper/wallpaper`、`LauncherCommand.openSettings`、`LauncherHideReason.settings`、`LauncherController.onOpenSettings`、`SettingsWindowController(onWillShow:makeContent:)`、`SettingsView(settings:model:loginItemService:hasHotKeyConflict:onUnhide:onUnhideAll:)`、`DragCardRenderer.image(for:count:showsName:layout:scale:)`、`ScreenPresenter.onPresent`、`ItemDragController.showMainMenu()`、`StatusItemController.setIconVisible(_:)` 与 `onOpenSettings` 各处一致。
