# 第 3 期：键盘与翻页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按旧 Launchpad 惯例加入键盘选择、Return 启动、⌘/滚轮/触控板翻页与翻页动画；文件夹支持键盘导航、分页与从格子放大展开。

**Architecture:** 规则全部落在纯逻辑单元：`GridNavigator`（选中移动）、`KeyCommandMapper`（按键 → 命令）、`PageScrollInterpreter`（滚动 → 翻页）。`LauncherModel` 持有选中与文件夹分页状态，`LauncherController.handle(_:)` 统一处理命令，`LauncherInputMonitor` 用应用内本地监听把按键与滚动送进控制器。界面把所有页横向并排平移，文件夹展开用自定义转场从格子位置缩放。

**Tech Stack:** Swift 6.4、AppKit（NSEvent 本地监听）、SwiftUI、XCTest。

**Spec:** `docs/superpowers/specs/2026-10-19-keyboard-paging-design.md`

## 全局约束

- 只改本期必需的代码；注释一行为限。
- 每个任务完成并验证后直接提交，标题行 `<type>(<中文scope>): <中文描述>`，不加 `Co-Authored-By`。
- 测试：`swift test`；单个测试类 `swift test --filter <Target>.<Class>`。

## 文件结构

| 文件 | 操作 | 职责 |
| --- | --- | --- |
| `Sources/LaunchApp/GridNavigator.swift` | 新增 | `MoveDirection`、`GridPosition`、`GridNavigator` |
| `Sources/LaunchApp/KeyCommandMapper.swift` | 新增 | `LauncherCommand`、`KeyCommandMapper` |
| `Sources/LaunchApp/PageScrollInterpreter.swift` | 新增 | `PageDirection`、`ScrollSample`、`PageScrollInterpreter` |
| `Sources/LaunchApp/LauncherInputMonitor.swift` | 新增 | 本地监听与 `ScrollSample(event:)` |
| `Sources/LaunchApp/LauncherModel.swift` | 重写 | 选中、文件夹分页、命令对应的状态变化 |
| `Sources/LaunchApp/LauncherController.swift` | 修改 | `handle(_:)` |
| `Sources/LaunchApp/ScreenPresenter.swift` | 修改 | `isLauncherWindow(_:)`、`isComposingText` |
| `Sources/LaunchApp/LauncherView.swift` | 修改 | 横向分页、选中高亮、文件夹位置、放大转场、文件夹分页 |
| `Sources/LaunchApp/LaunchApp.swift` | 修改 | 启动监听 |
| `Tests/LaunchAppTests/*` | 新增/修改 | 各单元测试 |

---

### Task 1: 选中移动规则 `GridNavigator`

**Files:**
- Create: `Sources/LaunchApp/GridNavigator.swift`
- Create: `Tests/LaunchAppTests/GridNavigatorTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import LaunchApp

final class GridNavigatorTests: XCTestCase {
    private func move(
        _ position: GridPosition?,
        _ direction: MoveDirection,
        page: Int = 0,
        sizes: [Int]
    ) -> GridPosition? {
        GridNavigator.move(from: position, direction: direction, currentPage: page, pageSizes: sizes, columns: 7)
    }

    func testFirstMoveSelectsFirstItemOfCurrentPage() {
        XCTAssertEqual(move(nil, .right, page: 1, sizes: [35, 10]), GridPosition(page: 1, index: 0))
        XCTAssertEqual(move(nil, .down, page: 0, sizes: [35, 10]), GridPosition(page: 0, index: 0))
    }

    func testRightWrapsRowsAndCrossesToNextPage() {
        XCTAssertEqual(move(GridPosition(page: 0, index: 6), .right, sizes: [35, 10]), GridPosition(page: 0, index: 7))
        XCTAssertEqual(move(GridPosition(page: 0, index: 34), .right, sizes: [35, 10]), GridPosition(page: 1, index: 0))
        XCTAssertEqual(move(GridPosition(page: 1, index: 9), .right, sizes: [35, 10]), GridPosition(page: 1, index: 9))
    }

    func testLeftCrossesToPreviousPageLastItem() {
        XCTAssertEqual(move(GridPosition(page: 1, index: 0), .left, sizes: [35, 10]), GridPosition(page: 0, index: 34))
        XCTAssertEqual(move(GridPosition(page: 0, index: 0), .left, sizes: [35, 10]), GridPosition(page: 0, index: 0))
    }

    func testDownMovesByColumnAndLandsOnLastItemOfShortRow() {
        XCTAssertEqual(move(GridPosition(page: 0, index: 1), .down, sizes: [10]), GridPosition(page: 0, index: 8))
        XCTAssertEqual(move(GridPosition(page: 0, index: 5), .down, sizes: [10]), GridPosition(page: 0, index: 9))
        XCTAssertEqual(move(GridPosition(page: 0, index: 8), .down, sizes: [10]), GridPosition(page: 0, index: 8))
    }

    func testUpStopsAtTopRow() {
        XCTAssertEqual(move(GridPosition(page: 0, index: 9), .up, sizes: [10]), GridPosition(page: 0, index: 2))
        XCTAssertEqual(move(GridPosition(page: 0, index: 3), .up, sizes: [10]), GridPosition(page: 0, index: 3))
    }

    func testStalePositionRestartsOnCurrentPage() {
        XCTAssertEqual(move(GridPosition(page: 3, index: 0), .right, page: 0, sizes: [5]), GridPosition(page: 0, index: 0))
    }

    func testEmptyPagesKeepPosition() {
        XCTAssertNil(move(nil, .right, sizes: []))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchAppTests.GridNavigatorTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `cannot find 'GridNavigator' in scope`

- [ ] **Step 3: 实现 `Sources/LaunchApp/GridNavigator.swift`**

```swift
enum MoveDirection: Equatable {
    case left
    case right
    case up
    case down
}

struct GridPosition: Equatable {
    var page: Int
    var index: Int
}

enum GridNavigator {
    static func move(
        from position: GridPosition?,
        direction: MoveDirection,
        currentPage: Int,
        pageSizes: [Int],
        columns: Int
    ) -> GridPosition? {
        guard pageSizes.indices.contains(currentPage), pageSizes[currentPage] > 0 else {
            return position
        }
        guard let position,
              pageSizes.indices.contains(position.page),
              position.index < pageSizes[position.page] else {
            return GridPosition(page: currentPage, index: 0)
        }
        let size = pageSizes[position.page]
        let index = position.index
        switch direction {
        case .right:
            if index + 1 < size {
                return GridPosition(page: position.page, index: index + 1)
            }
            if position.page + 1 < pageSizes.count, pageSizes[position.page + 1] > 0 {
                return GridPosition(page: position.page + 1, index: 0)
            }
            return position
        case .left:
            if index > 0 {
                return GridPosition(page: position.page, index: index - 1)
            }
            if position.page > 0, pageSizes[position.page - 1] > 0 {
                return GridPosition(page: position.page - 1, index: pageSizes[position.page - 1] - 1)
            }
            return position
        case .down:
            guard index / columns < (size - 1) / columns else {
                return position
            }
            return GridPosition(page: position.page, index: min(index + columns, size - 1))
        case .up:
            guard index >= columns else {
                return position
            }
            return GridPosition(page: position.page, index: index - columns)
        }
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter LaunchAppTests.GridNavigatorTests 2>&1 | grep -E "error:|failed|Executed [1-9]" | sort -u | tail -2`
Expected: `Executed 7 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchApp/GridNavigator.swift Tests/LaunchAppTests/GridNavigatorTests.swift
git commit -m "feat(键盘): 添加网格选中移动规则"
```

---

### Task 2: 按键到命令 `KeyCommandMapper`

**Files:**
- Create: `Sources/LaunchApp/KeyCommandMapper.swift`
- Create: `Tests/LaunchAppTests/KeyCommandMapperTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import AppKit
import XCTest
@testable import LaunchApp

final class KeyCommandMapperTests: XCTestCase {
    private let arrowFlags: NSEvent.ModifierFlags = [.numericPad, .function]

    private func map(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = [], composing: Bool = false) -> LauncherCommand? {
        KeyCommandMapper.command(keyCode: keyCode, modifiers: modifiers, isComposingText: composing)
    }

    func testArrowsMoveSelectionEvenWithDeviceFlags() {
        XCTAssertEqual(map(123, arrowFlags), .move(.left))
        XCTAssertEqual(map(124, arrowFlags), .move(.right))
        XCTAssertEqual(map(125, arrowFlags), .move(.down))
        XCTAssertEqual(map(126, arrowFlags), .move(.up))
    }

    func testReturnAndEnterActivate() {
        XCTAssertEqual(map(36), .activate)
        XCTAssertEqual(map(76, [.numericPad]), .activate)
    }

    func testCommandArrowsTurnPages() {
        XCTAssertEqual(map(123, arrowFlags.union(.command)), .previousPage)
        XCTAssertEqual(map(124, arrowFlags.union(.command)), .nextPage)
        XCTAssertNil(map(126, arrowFlags.union(.command)))
    }

    func testComposingTextPassesKeysToInputMethod() {
        XCTAssertNil(map(124, arrowFlags, composing: true))
        XCTAssertNil(map(36, composing: true))
    }

    func testOtherModifiersAndKeysPassThrough() {
        XCTAssertNil(map(124, arrowFlags.union(.shift)))
        XCTAssertNil(map(124, arrowFlags.union(.option)))
        XCTAssertNil(map(0))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchAppTests.KeyCommandMapperTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `cannot find 'KeyCommandMapper' in scope`

- [ ] **Step 3: 实现 `Sources/LaunchApp/KeyCommandMapper.swift`**

```swift
import AppKit

enum LauncherCommand: Equatable {
    case move(MoveDirection)
    case activate
    case nextPage
    case previousPage
}

enum KeyCommandMapper {
    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isComposingText: Bool
    ) -> LauncherCommand? {
        guard !isComposingText else {
            return nil
        }
        // 方向键事件自带数字键盘与功能键标志，只比较用户按下的修饰键
        let pressed = modifiers.intersection([.command, .option, .control, .shift])
        switch (keyCode, pressed) {
        case (123, []):
            return .move(.left)
        case (124, []):
            return .move(.right)
        case (125, []):
            return .move(.down)
        case (126, []):
            return .move(.up)
        case (36, []), (76, []):
            return .activate
        case (123, [.command]):
            return .previousPage
        case (124, [.command]):
            return .nextPage
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter LaunchAppTests.KeyCommandMapperTests 2>&1 | grep -E "error:|failed|Executed [1-9]" | sort -u | tail -2`
Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchApp/KeyCommandMapper.swift Tests/LaunchAppTests/KeyCommandMapperTests.swift
git commit -m "feat(键盘): 将按键映射为启动器命令"
```

---

### Task 3: 滚动到翻页 `PageScrollInterpreter`

**Files:**
- Create: `Sources/LaunchApp/PageScrollInterpreter.swift`
- Create: `Tests/LaunchAppTests/PageScrollInterpreterTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import CoreGraphics
import XCTest
@testable import LaunchApp

final class PageScrollInterpreterTests: XCTestCase {
    private func trackpad(_ dx: CGFloat, _ dy: CGFloat = 0, _ phase: ScrollSample.Phase, momentum: Bool = false) -> ScrollSample {
        ScrollSample(deltaX: dx, deltaY: dy, isPrecise: true, phase: phase, isMomentum: momentum, timestamp: 0)
    }

    private func wheel(_ dy: CGFloat, at time: TimeInterval) -> ScrollSample {
        ScrollSample(deltaX: 0, deltaY: dy, isPrecise: false, phase: .none, isMomentum: false, timestamp: time)
    }

    func testTrackpadSwipeTurnsOnePagePerGesture() {
        var interpreter = PageScrollInterpreter()

        XCTAssertNil(interpreter.interpret(trackpad(-10, 0, .began)))
        XCTAssertNil(interpreter.interpret(trackpad(-20, 0, .changed)))
        XCTAssertEqual(interpreter.interpret(trackpad(-20, 0, .changed)), .next)
        XCTAssertNil(interpreter.interpret(trackpad(-60, 0, .changed)))
        XCTAssertNil(interpreter.interpret(trackpad(0, 0, .ended)))
        XCTAssertEqual(interpreter.interpret(trackpad(45, 0, .began)), .previous)
    }

    func testSmallSwipeAndMomentumDoNothing() {
        var interpreter = PageScrollInterpreter()

        XCTAssertNil(interpreter.interpret(trackpad(-30, 0, .began)))
        XCTAssertNil(interpreter.interpret(trackpad(0, 0, .ended)))
        XCTAssertNil(interpreter.interpret(trackpad(-200, 0, .none, momentum: true)))
    }

    func testVerticalTrackpadScrollUsesDominantAxis() {
        var interpreter = PageScrollInterpreter()

        XCTAssertEqual(interpreter.interpret(trackpad(5, -50, .began)), .next)
    }

    func testWheelTurnsAtMostOncePerInterval() {
        var interpreter = PageScrollInterpreter()

        XCTAssertEqual(interpreter.interpret(wheel(-1, at: 0)), .next)
        XCTAssertNil(interpreter.interpret(wheel(-1, at: 0.1)))
        XCTAssertEqual(interpreter.interpret(wheel(-1, at: 0.5)), .next)
        XCTAssertEqual(interpreter.interpret(wheel(1, at: 1.0)), .previous)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchAppTests.PageScrollInterpreterTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `cannot find 'ScrollSample' in scope`

- [ ] **Step 3: 实现 `Sources/LaunchApp/PageScrollInterpreter.swift`**

```swift
import CoreGraphics
import Foundation

enum PageDirection: Equatable {
    case next
    case previous
}

struct ScrollSample: Equatable {
    enum Phase: Equatable {
        case none
        case began
        case changed
        case ended
    }

    var deltaX: CGFloat
    var deltaY: CGFloat
    var isPrecise: Bool
    var phase: Phase
    var isMomentum: Bool
    var timestamp: TimeInterval
}

struct PageScrollInterpreter {
    var threshold: CGFloat = 40
    var wheelInterval: TimeInterval = 0.35
    private var accumulated: CGFloat = 0
    private var hasTurned = false
    private var lastWheelTurn: TimeInterval?

    mutating func interpret(_ sample: ScrollSample) -> PageDirection? {
        guard !sample.isMomentum else {
            return nil
        }
        return sample.isPrecise ? interpretGesture(sample) : interpretWheel(sample)
    }

    private mutating func interpretGesture(_ sample: ScrollSample) -> PageDirection? {
        if sample.phase == .began {
            accumulated = 0
            hasTurned = false
        }
        defer {
            if sample.phase == .ended {
                accumulated = 0
                hasTurned = false
            }
        }
        accumulated += abs(sample.deltaX) >= abs(sample.deltaY) ? sample.deltaX : sample.deltaY
        guard !hasTurned, abs(accumulated) >= threshold else {
            return nil
        }
        hasTurned = true
        return accumulated < 0 ? .next : .previous
    }

    private mutating func interpretWheel(_ sample: ScrollSample) -> PageDirection? {
        let delta = sample.deltaY != 0 ? sample.deltaY : sample.deltaX
        guard delta != 0 else {
            return nil
        }
        if let lastWheelTurn, sample.timestamp - lastWheelTurn < wheelInterval {
            return nil
        }
        lastWheelTurn = sample.timestamp
        return delta < 0 ? .next : .previous
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter LaunchAppTests.PageScrollInterpreterTests 2>&1 | grep -E "error:|failed|Executed [1-9]" | sort -u | tail -2`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchApp/PageScrollInterpreter.swift Tests/LaunchAppTests/PageScrollInterpreterTests.swift
git commit -m "feat(翻页): 将滚动与手势翻译为翻页"
```

---

### Task 4: 模型的选中与文件夹分页

**Files:**
- Rewrite: `Sources/LaunchApp/LauncherModel.swift`
- Modify: `Tests/LaunchAppTests/LauncherModelTests.swift`

- [ ] **Step 1: `LauncherModelTests` 类内追加失败测试**

```swift
    @MainActor
    func testTypingSelectsFirstResultAndClearingDeselects() {
        let model = LauncherModel(apps: makeApps(count: 3))

        model.setQuery("App")
        XCTAssertEqual(model.selectedIndex, 0)
        model.setQuery("zzz")
        XCTAssertNil(model.selectedIndex)
        model.setQuery("")
        XCTAssertNil(model.selectedIndex)
    }

    @MainActor
    func testArrowsCrossToNextPage() {
        let model = LauncherModel(apps: makeApps(count: 40))

        model.moveSelection(.right)
        XCTAssertEqual(model.selectedIndex, 0)
        for _ in 0 ..< 35 {
            model.moveSelection(.right)
        }

        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.selectedIndex, 0)
    }

    @MainActor
    func testActivateReturnsSelectedSearchResult() {
        let apps = makeApps(count: 3)
        let model = LauncherModel(apps: apps)

        model.setQuery("App 1")

        XCTAssertEqual(model.activateSelection(), apps[1])
    }

    @MainActor
    func testActivatingFolderOpensItAndSelectsFirstMember() {
        let apps = makeApps(count: 2)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.moveSelection(.right)

        XCTAssertNil(model.activateSelection())
        XCTAssertEqual(model.openFolderID, "f")
        XCTAssertEqual(model.folderSelectedIndex, 0)
        XCTAssertEqual(model.activateSelection(), apps[0])
    }

    @MainActor
    func testEscapeFromFolderSelectsFolderTile() {
        let apps = makeApps(count: 2)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[.app(apps[0]), makeFolder(id: "f", name: "效率", apps: [apps[1]])]])
        model.showFolder(id: "f")

        XCTAssertEqual(model.handleEscape(), .closedFolder)
        XCTAssertEqual(model.selectedIndex, 1)
    }

    @MainActor
    func testLargeFolderPagesAndArrowsStayInsideFolder() {
        let apps = makeApps(count: 40)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "其他", apps: apps)]])
        model.showFolder(id: "f")

        XCTAssertEqual(model.folderPages.count, 2)
        model.turnPage(.next)
        XCTAssertEqual(model.folderPage, 1)
        XCTAssertEqual(model.visibleFolderApps.count, 5)
        model.moveSelection(.right)
        XCTAssertEqual(model.folderSelectedIndex, 0)
        XCTAssertEqual(model.activateSelection(), model.visibleFolderApps[0])
    }

    @MainActor
    func testPageTurnClearsSelection() {
        let model = LauncherModel(apps: makeApps(count: 40))
        model.moveSelection(.right)

        model.turnPage(.next)

        XCTAssertEqual(model.currentPage, 1)
        XCTAssertNil(model.selectedIndex)
    }

    @MainActor
    func testShrinkingResultsClampsSelection() {
        let model = LauncherModel(apps: makeApps(count: 3))
        model.moveSelection(.right)
        model.moveSelection(.right)
        model.moveSelection(.right)

        model.updateApps(makeApps(count: 1))

        XCTAssertEqual(model.selectedIndex, 0)
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchAppTests.LauncherModelTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `has no member 'selectedIndex'` 等。

- [ ] **Step 3: 重写 `Sources/LaunchApp/LauncherModel.swift`**

```swift
import LaunchCore
import Observation

enum EscapeOutcome: Equatable {
    case closedFolder
    case clearedQuery
    case close
}

@MainActor
@Observable
final class LauncherModel {
    private(set) var apps: [CatalogApp]
    private(set) var layoutPages: [[ResolvedItem]]?
    private(set) var query = ""
    private(set) var currentPage = 0
    private(set) var selectedIndex: Int?
    private(set) var presentationCount = 0
    private(set) var openFolderID: String?
    private(set) var folderPage = 0
    private(set) var folderSelectedIndex: Int?

    init(apps: [CatalogApp] = []) {
        self.apps = apps
    }

    var results: [CatalogApp] {
        SearchService.results(for: query, in: apps, hidden: [])
    }

    var pages: [[ResolvedItem]] {
        let source: [[ResolvedItem]]
        if query.isEmpty, let layoutPages {
            source = layoutPages
        } else {
            source = [results.map(ResolvedItem.app)]
        }
        return source.flatMap {
            LauncherPagination.pages($0, capacity: LauncherHomeLayout.pageCapacity)
        }
    }

    var visibleItems: [ResolvedItem] {
        let pages = pages
        guard !pages.isEmpty else {
            return []
        }
        return pages[LauncherPagination.normalizedPageIndex(currentPage, pageCount: pages.count)]
    }

    var openFolder: ResolvedFolder? {
        guard let openFolderID, let layoutPages else {
            return nil
        }
        for item in layoutPages.joined() {
            if case .folder(let folder) = item, folder.id == openFolderID {
                return folder
            }
        }
        return nil
    }

    var folderPages: [[CatalogApp]] {
        guard let openFolder else {
            return []
        }
        return LauncherPagination.pages(openFolder.apps, capacity: LauncherHomeLayout.pageCapacity)
    }

    var visibleFolderApps: [CatalogApp] {
        let pages = folderPages
        guard !pages.isEmpty else {
            return []
        }
        return pages[LauncherPagination.normalizedPageIndex(folderPage, pageCount: pages.count)]
    }

    func setQuery(_ newQuery: String) {
        guard newQuery != query else {
            return
        }
        query = newQuery
        currentPage = 0
        if newQuery.isEmpty {
            selectedIndex = nil
        } else {
            closeFolder()
            selectedIndex = visibleItems.isEmpty ? nil : 0
        }
    }

    func selectPage(_ index: Int) {
        closeFolder()
        currentPage = clampedPage(index)
        selectedIndex = nil
    }

    func selectFolderPage(_ index: Int) {
        folderPage = LauncherPagination.normalizedPageIndex(index, pageCount: folderPages.count)
        folderSelectedIndex = nil
    }

    func turnPage(_ direction: PageDirection) {
        let step = direction == .next ? 1 : -1
        if openFolder != nil {
            selectFolderPage(folderPage + step)
        } else {
            selectPage(currentPage + step)
        }
    }

    func showFolder(id: String) {
        openFolderID = id
        folderPage = 0
        folderSelectedIndex = nil
    }

    func closeFolder() {
        openFolderID = nil
        folderPage = 0
        folderSelectedIndex = nil
    }

    func moveSelection(_ direction: MoveDirection) {
        if openFolder != nil {
            let current = folderSelectedIndex.map { GridPosition(page: folderPage, index: $0) }
            if let next = GridNavigator.move(
                from: current,
                direction: direction,
                currentPage: folderPage,
                pageSizes: folderPages.map(\.count),
                columns: LauncherHomeLayout.columnCount
            ) {
                folderPage = next.page
                folderSelectedIndex = next.index
            }
            return
        }
        let current = selectedIndex.map { GridPosition(page: currentPage, index: $0) }
        if let next = GridNavigator.move(
            from: current,
            direction: direction,
            currentPage: currentPage,
            pageSizes: pages.map(\.count),
            columns: LauncherHomeLayout.columnCount
        ) {
            currentPage = next.page
            selectedIndex = next.index
        }
    }

    func activateSelection() -> CatalogApp? {
        if openFolder != nil {
            guard let index = folderSelectedIndex, visibleFolderApps.indices.contains(index) else {
                return nil
            }
            return visibleFolderApps[index]
        }
        guard let index = selectedIndex, visibleItems.indices.contains(index) else {
            return nil
        }
        switch visibleItems[index] {
        case .app(let app):
            return app
        case .folder(let folder):
            showFolder(id: folder.id)
            folderSelectedIndex = folderPages.isEmpty ? nil : 0
            return nil
        case .empty:
            return nil
        }
    }

    func prepareForPresentation() {
        closeFolder()
        setQuery("")
        selectedIndex = nil
        currentPage = clampedPage(currentPage)
        presentationCount += 1
    }

    func handleEscape() -> EscapeOutcome {
        if let folderID = openFolderID {
            closeFolder()
            selectedIndex = visibleItems.firstIndex { item in
                if case .folder(let folder) = item {
                    return folder.id == folderID
                }
                return false
            }
            return .closedFolder
        }
        guard !query.isEmpty else {
            return .close
        }
        setQuery("")
        return .clearedQuery
    }

    func updateApps(_ newApps: [CatalogApp]) {
        apps = newApps
        normalizeState()
    }

    func updateLayout(_ pages: [[ResolvedItem]]) {
        layoutPages = pages
        normalizeState()
    }

    private func normalizeState() {
        currentPage = clampedPage(currentPage)
        selectedIndex = clampedSelection(selectedIndex, count: visibleItems.count)
        if openFolderID != nil, openFolder == nil {
            closeFolder()
        } else if openFolder != nil {
            folderPage = LauncherPagination.normalizedPageIndex(folderPage, pageCount: folderPages.count)
            folderSelectedIndex = clampedSelection(folderSelectedIndex, count: visibleFolderApps.count)
        }
    }

    private func clampedSelection(_ index: Int?, count: Int) -> Int? {
        guard let index, count > 0 else {
            return nil
        }
        return min(index, count - 1)
    }

    private func clampedPage(_ index: Int) -> Int {
        LauncherPagination.normalizedPageIndex(index, pageCount: pages.count)
    }
}
```

- [ ] **Step 4: 运行确认通过并全量测试**

Run: `swift build 2>&1 | grep -E "error:|Build complete" | tail -1 && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -3`
Expected: `Build complete!`；全部测试 0 failures。

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchApp/LauncherModel.swift Tests/LaunchAppTests/LauncherModelTests.swift
git commit -m "feat(键盘): 模型支持选中移动与文件夹分页"
```

---

### Task 5: 控制器统一处理命令

**Files:**
- Modify: `Sources/LaunchApp/LauncherController.swift`
- Modify: `Tests/LaunchAppTests/LauncherControllerTests.swift`

- [ ] **Step 1: `LauncherControllerTests` 类内追加失败测试**

```swift
    @MainActor
    func testActivateCommandLaunchesSelectedApp() {
        var openedPaths: [String] = []
        let apps = makeApps(count: 2)
        let (controller, presenter) = makeController(apps: apps) { url in
            openedPaths.append(url.path)
            return true
        }
        controller.show()
        controller.model.setQuery("App 1")

        controller.handle(.activate)

        XCTAssertEqual(openedPaths, [apps[1].identity.path])
        XCTAssertEqual(presenter.dismissals, [false])
    }

    @MainActor
    func testCommandsAreIgnoredWhileHidden() {
        let (controller, _) = makeController(apps: makeApps(count: 2))

        controller.handle(.move(.right))

        XCTAssertNil(controller.model.selectedIndex)
    }

    @MainActor
    func testPageCommandsTurnPages() {
        let (controller, _) = makeController(apps: makeApps(count: 40))
        controller.show()

        controller.handle(.nextPage)
        XCTAssertEqual(controller.model.currentPage, 1)
        controller.handle(.previousPage)
        XCTAssertEqual(controller.model.currentPage, 0)
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchAppTests.LauncherControllerTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `has no member 'handle'`

- [ ] **Step 3: `LauncherController` 在 `handleBackgroundClick()` 之后插入**

```swift
    func handle(_ command: LauncherCommand) {
        guard presenter.isVisible else {
            return
        }
        switch command {
        case .move(let direction):
            model.moveSelection(direction)
        case .activate:
            if let app = model.activateSelection() {
                launch(app)
            }
        case .nextPage:
            model.turnPage(.next)
        case .previousPage:
            model.turnPage(.previous)
        }
    }
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter LaunchAppTests.LauncherControllerTests 2>&1 | grep -E "error:|failed|Executed [1-9]" | sort -u | tail -2`
Expected: `Executed 13 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchApp/LauncherController.swift Tests/LaunchAppTests/LauncherControllerTests.swift
git commit -m "feat(键盘): 控制器统一处理键盘与翻页命令"
```

---

### Task 6: 本地监听并接入

**Files:**
- Create: `Sources/LaunchApp/LauncherInputMonitor.swift`
- Modify: `Sources/LaunchApp/ScreenPresenter.swift`
- Modify: `Sources/LaunchApp/LaunchApp.swift`

AppKit 胶水代码，不写单测，Task 8 端到端验证。

- [ ] **Step 1: 创建 `Sources/LaunchApp/LauncherInputMonitor.swift`**

```swift
import AppKit

@MainActor
final class LauncherInputMonitor {
    private var monitors: [Any] = []
    private var interpreter = PageScrollInterpreter()

    func start(
        isLauncherWindow: @escaping (NSWindow?) -> Bool,
        isComposingText: @escaping () -> Bool,
        onCommand: @escaping (LauncherCommand) -> Void
    ) {
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isLauncherWindow(event.window),
                  let command = KeyCommandMapper.command(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags,
                    isComposingText: isComposingText()
                  ) else {
                return event
            }
            onCommand(command)
            return nil
        }
        let scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, isLauncherWindow(event.window) else {
                return event
            }
            if let direction = interpreter.interpret(ScrollSample(event: event)) {
                onCommand(direction == .next ? .nextPage : .previousPage)
            }
            return nil
        }
        monitors = [keyMonitor, scrollMonitor].compactMap { $0 }
    }
}

extension ScrollSample {
    init(event: NSEvent) {
        let phase: Phase
        switch event.phase {
        case .began, .mayBegin:
            phase = .began
        case .ended, .cancelled:
            phase = .ended
        case []:
            phase = .none
        default:
            phase = .changed
        }
        self.init(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas,
            phase: phase,
            isMomentum: event.momentumPhase != [],
            timestamp: event.timestamp
        )
    }
}
```

若编译器要求显式隔离，在回调内以 `MainActor.assumeIsolated` 包裹并只返回 `Bool`（是否吞掉事件），事件对象在闭包外返回。

- [ ] **Step 2: `ScreenPresenter` 在 `isVisible` 之后插入**

```swift
    func isLauncherWindow(_ window: NSWindow?) -> Bool {
        window === panel
    }

    var isComposingText: Bool {
        (panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
```

- [ ] **Step 3: `LaunchApp.swift` 接入**

属性区 `private var catalogWatcher` 之后插入：

```swift
    private let inputMonitor = LauncherInputMonitor()
```

`HotKeyService.register` 之前插入：

```swift
        inputMonitor.start(
            isLauncherWindow: { [weak self] window in self?.presenter.isLauncherWindow(window) ?? false },
            isComposingText: { [weak self] in self?.presenter.isComposingText ?? false },
            onCommand: { [weak self] command in self?.controller.handle(command) }
        )
```

- [ ] **Step 4: 构建与全量测试**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete" | tail -3 && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -3`
Expected: `Build complete!`，无新警告；全部测试 0 failures。

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchApp/LauncherInputMonitor.swift Sources/LaunchApp/ScreenPresenter.swift Sources/LaunchApp/LaunchApp.swift
git commit -m "feat(键盘): 监听按键与滚动并接入启动器"
```

---

### Task 7: 横向翻页、选中高亮、文件夹分页与放大展开

**Files:**
- Modify: `Sources/LaunchApp/LauncherView.swift`

- [ ] **Step 1: `body` 改为在命名坐标空间内叠放网格与文件夹，并按格子位置转场**

`LauncherView` 增加：

```swift
    @State private var folderFrames: [String: CGRect] = [:]
    private static let contentSpace = "launcher-content"
```

`body` 中自 `let layout = ...` 之后、`ZStack` 结束之前的内容替换为：

```swift
                ZStack {
                    homeContent(layout: layout)
                        .opacity(model.openFolder == nil ? 1 : 0)
                        .allowsHitTesting(model.openFolder == nil)

                    if let folder = model.openFolder {
                        FolderOverlay(
                            model: model,
                            folder: folder,
                            layout: layout,
                            columns: gridColumns(layout),
                            onLaunch: onLaunch
                        )
                        .transition(.folderZoom(from: folderFrames[folder.id], in: layout.contentSize))
                    }
                }
                .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                .coordinateSpace(.named(Self.contentSpace))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.25), value: model.openFolderID)
```

- [ ] **Step 2: 主网格改为所有页横向并排**

`homeContent(layout:)` 中 `if model.visibleItems.isEmpty { ... } else { LazyVGrid ... }` 替换为：

```swift
            if model.pages.isEmpty {
                ContentUnavailableView(
                    "未找到应用",
                    systemImage: "magnifyingglass",
                    description: Text("换个关键词试试")
                )
                .foregroundStyle(.white)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(model.pages.enumerated()), id: \.offset) { pageIndex, items in
                        LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                itemView(
                                    item,
                                    layout: layout,
                                    isSelected: pageIndex == model.currentPage && index == model.selectedIndex
                                )
                            }
                        }
                        .padding(.horizontal, layout.horizontalInset)
                        .frame(width: layout.contentSize.width, height: layout.gridHeight, alignment: .top)
                        .allowsHitTesting(pageIndex == model.currentPage)
                    }
                }
                .offset(x: -CGFloat(model.currentPage) * layout.contentSize.width)
                .frame(width: layout.contentSize.width, height: layout.gridHeight, alignment: .topLeading)
                .clipped()
                .animation(.easeOut(duration: 0.3), value: model.currentPage)
            }
```

`itemView` 改为：

```swift
    @ViewBuilder
    private func itemView(_ item: ResolvedItem, layout: LauncherHomeLayout, isSelected: Bool) -> some View {
        switch item {
        case .app(let app):
            LauncherAppTile(app: app, layout: layout, isSelected: isSelected) {
                onLaunch(app)
            }
        case .folder(let folder):
            LauncherFolderTile(folder: folder, layout: layout, isSelected: isSelected) {
                model.showFolder(id: folder.id)
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.contentSpace))
            } action: { frame in
                folderFrames[folder.id] = frame
            }
        case .empty:
            Color.clear
                .frame(width: layout.tileWidth, height: layout.tileHeight)
        }
    }
```

- [ ] **Step 3: 格子支持选中高亮**

`LauncherAppTile` 与 `LauncherFolderTile` 各增加属性 `let isSelected: Bool`（位于 `layout` 之后），背景填充改为：

```swift
                    .fill(.white.opacity(isSelected ? 0.26 : (isHovering ? 0.15 : 0)))
```

- [ ] **Step 4: 文件夹展开视图支持分页**

`FolderOverlay` 整体替换为：

```swift
private struct FolderOverlay: View {
    let model: LauncherModel
    let folder: ResolvedFolder
    let layout: LauncherHomeLayout
    let columns: [GridItem]
    let onLaunch: (CatalogApp) -> Void

    var body: some View {
        let pages = model.folderPages
        VStack(spacing: layout.folderTitleSpacing) {
            Text(folder.name)
                .font(.system(size: layout.folderTitleFontSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(height: layout.folderTitleHeight)
            HStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, apps in
                    LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
                        ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                            LauncherAppTile(
                                app: app,
                                layout: layout,
                                isSelected: pageIndex == model.folderPage && index == model.folderSelectedIndex
                            ) {
                                onLaunch(app)
                            }
                        }
                    }
                    .padding(.horizontal, layout.horizontalInset)
                    .frame(width: layout.contentSize.width, alignment: .top)
                    .allowsHitTesting(pageIndex == model.folderPage)
                }
            }
            .offset(x: -CGFloat(model.folderPage) * layout.contentSize.width)
            .frame(
                width: layout.contentSize.width,
                height: layout.folderGridHeight(memberCount: folder.apps.count),
                alignment: .topLeading
            )
            .clipped()
            .animation(.easeOut(duration: 0.3), value: model.folderPage)
            .padding(.vertical, layout.folderPanelPadding)
            .background {
                RoundedRectangle(cornerRadius: layout.folderPanelCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: layout.folderPanelCornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    }
                    .padding(.horizontal, layout.horizontalInset - layout.folderPanelOutset)
                    .onTapGesture {}
            }
            if pages.count > 1 {
                HStack(spacing: layout.pageDotSpacing) {
                    ForEach(pages.indices, id: \.self) { pageIndex in
                        Button {
                            model.selectFolderPage(pageIndex)
                        } label: {
                            Circle()
                                .fill(pageIndex == model.folderPage ? .white : .white.opacity(0.4))
                                .frame(width: layout.pageDotSize, height: layout.pageDotSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("文件夹第 \(pageIndex + 1) 页")
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 5: 文件末尾追加放大转场**

```swift
private struct FolderZoomModifier: ViewModifier {
    let scale: CGFloat
    let offset: CGSize
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static func folderZoom(from source: CGRect?, in size: CGSize) -> AnyTransition {
        guard let source, size.width > 0 else {
            return .opacity.combined(with: .scale(scale: 0.92))
        }
        let offset = CGSize(width: source.midX - size.width / 2, height: source.midY - size.height / 2)
        return .modifier(
            active: FolderZoomModifier(scale: max(source.width / size.width, 0.05), offset: offset, opacity: 0),
            identity: FolderZoomModifier(scale: 1, offset: .zero, opacity: 1)
        )
    }
}
```

- [ ] **Step 6: 构建与全量测试**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete" | tail -3 && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -3`
Expected: `Build complete!`；全部测试 0 failures。

- [ ] **Step 7: Commit**

```bash
git add Sources/LaunchApp/LauncherView.swift
git commit -m "feat(界面): 横向翻页、选中高亮与文件夹放大展开"
```

---

### Task 8: 渲染、安装、端到端与文档

**Files:**
- Create（临时，不提交）: `Tests/LaunchAppTests/KeyboardSnapshotProbe.swift`
- Modify: `docs/manual-verification.md`、`README.md`

- [ ] **Step 1: 临时探针渲染**

```swift
import AppKit
import LaunchCore
import SwiftUI
import XCTest
@testable import LaunchApp

final class KeyboardSnapshotProbe: XCTestCase {
    @MainActor
    func testRenderSelectionAndFolderPaging() throws {
        let apps = try AppCatalog().scan(roots: ApplicationSources.defaultRoots())
        let model = LauncherModel(apps: apps)
        let members = Array(apps.prefix(40))
        model.updateLayout([[.folder(ResolvedFolder(id: "big", name: "四十个", apps: members))] + apps.dropFirst(40).prefix(20).map(ResolvedItem.app)])
        model.moveSelection(.right)
        model.moveSelection(.right)
        try render(model, "selection")
        model.showFolder(id: "big")
        model.moveSelection(.down)
        try render(model, "folder-page1")
        model.turnPage(.next)
        try render(model, "folder-page2")
    }

    @MainActor
    private func render(_ model: LauncherModel, _ name: String) throws {
        let view = LauncherView(model: model, onEscape: {}, onBackgroundClick: {}, onLaunch: { _ in })
            .frame(width: 1512, height: 982)
            .background(Color(white: 0.25))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/launch-keyboard-\(name).png"))
    }
}
```

Run: `swift test --filter LaunchAppTests.KeyboardSnapshotProbe 2>&1 | grep -E "error:|failed|Executed [1-9]"`，逐张查看：第 2 格高亮；文件夹第 1 页第 1 个成员高亮且下方有 2 个圆点；文件夹第 2 页 5 个成员。完成后删除探针。

- [ ] **Step 2: 安装**

Run: `LAUNCH_SIGN_IDENTITY="Apple Development: zhaoyingkun@163.com" ./scripts/build-app.sh --install`

- [ ] **Step 3: 端到端（辅助功能接口读状态，模拟键鼠前确认焦点在 Launch 的搜索框）**

1. 唤起，按 → 两次、Return：启动第 1 页第 2 格对应应用（读取按钮名后核对前台应用），测后退出。
2. 唤起，输入 `calc`（先切 ABC 输入法，测后恢复），按 Return：计算器启动；测后退出。
3. 唤起，按 ⌘→：分页圆点「第 2 页」为当前页（读取按钮状态或第一个格子名称变化）；按 ⌘←：回到第 1 页。
4. 唤起，发送滚轮事件（向下一格）：翻到第 2 页；0.1 秒内再发一次不再翻页。
5. 唤起，方向键选中「效率」所在格（读取格子顺序计算步数）后按 Return：出现成员按钮；Esc：成员消失、启动器仍显示。

- [ ] **Step 4: 请用户目测**

翻页滑动、文件夹从格子放大展开与缩回、拼音组字时方向键与 Return 交给输入法。

- [ ] **Step 5: 文档与提交**

`docs/manual-verification.md` 追加第 3 期结果与用户目测结论；`README.md` 当前状态加入第 3 期完成内容。

```bash
git add docs/manual-verification.md README.md
git commit -m "chore(文档): 同步第 3 期状态与验证结果"
```

---

## Self-Review

**Spec 覆盖：** §2.1 → Task 1、4、5、7；§2.2 → Task 4；§2.3 → Task 2、6；§2.4 → Task 3、4、6、7；§2.5 → Task 4、7；§3 组件 → Task 1–7；§4 状态规则 → Task 4；§5 验证 → Task 8。

**类型一致性：** `MoveDirection`、`GridPosition`（Task 1）用于 Task 2、4；`LauncherCommand`（Task 2）用于 Task 5、6；`PageDirection`、`ScrollSample`（Task 3）用于 Task 4、6；`LauncherModel` 的 `selectedIndex`、`folderPage`、`folderSelectedIndex`、`folderPages`、`visibleFolderApps`、`moveSelection`、`activateSelection`、`turnPage`、`selectFolderPage`（Task 4）用于 Task 5、7、8；`ScreenPresenter.isLauncherWindow(_:)`、`isComposingText`（Task 6）只在 Task 6 使用。
