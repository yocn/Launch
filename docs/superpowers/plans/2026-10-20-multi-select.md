# 第 4b 期：多选与批量操作 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 主网格中 ⌘ 点选或框选多个图标，一起拖动，或用右键菜单合并到新文件夹、合并到选中的文件夹、移动到指定页。

**Architecture:** `LayoutEditor` 新增 `moveGroup` 与 `mergeIntoNewFolder` 两种整体编辑；`MultiSelection` 管理选中集合与选框；`DragPreview`/`DragSession` 支持一组被拖项；`SelectionMenu` 生成 `NSMenu`；`LauncherModel` 持有选择、选框与批量命令；`ItemDragController` 处理 ⌘ 单击、⌘ 拖动、右键与 ⌃ 单击；视图绘制选中标记、选框与数量角标。

**Tech Stack:** Swift 6，AppKit（`NSMenu`、`NSDraggingSession`、本地事件监听），SwiftUI，XCTest。

**Spec:** `docs/superpowers/specs/2026-10-20-multi-select-design.md`

---

## 文件结构

| 文件 | 动作 | 职责 |
| --- | --- | --- |
| `Sources/LaunchCore/LayoutEditor.swift` | 修改 | `moveGroup`、`mergeIntoNewFolder`；挤页改为整批挤出 |
| `Tests/LaunchCoreTests/LayoutEditorTests.swift` | 修改 | 整体编辑测试 |
| `Sources/LaunchApp/MultiSelection.swift` | 新建 | 选中集合与选框 |
| `Tests/LaunchAppTests/MultiSelectionTests.swift` | 新建 | 对应测试 |
| `Sources/LaunchApp/GridHitTester.swift` | 修改 | 矩形相交的格子 |
| `Tests/LaunchAppTests/GridHitTesterTests.swift` | 修改 | 对应测试 |
| `Sources/LaunchApp/DragSession.swift` | 修改 | 一组被拖项的预览、命中与放下 |
| `Tests/LaunchAppTests/DragSessionTests.swift` | 修改 | 对应测试 |
| `Sources/LaunchApp/SelectionMenu.swift` | 新建 | 菜单内容、命令与 `NSMenu` 生成 |
| `Tests/LaunchAppTests/SelectionMenuTests.swift` | 新建 | 对应测试 |
| `Sources/LaunchApp/LauncherModel.swift` | 修改 | 选择、选框、清空时机、Esc、整体拖动、菜单命令 |
| `Tests/LaunchAppTests/LauncherModelSelectionTests.swift` | 新建 | 对应测试 |
| `Tests/LaunchAppTests/LauncherModelDragTests.swift` | 修改 | `Landing.entryIDs` |
| `Sources/LaunchApp/LauncherController.swift` | 修改 | 点空白分层、忽略带修饰键的点击 |
| `Tests/LaunchAppTests/LauncherControllerTests.swift` | 修改 | 对应测试 |
| `Sources/LaunchApp/ItemDragController.swift` | 修改 | ⌘ 单击、选框、右键菜单、整体拖动图像 |
| `Sources/LaunchApp/LaunchApp.swift` | 修改 | 拖拽图像带数量 |
| `Sources/LaunchApp/LauncherView.swift` | 修改 | 落位集合、数量角标、选中标记、选框 |

命令（项目根目录）：`swift build 2>&1 | grep -E "error:|warning:|Build complete"`；`swift test 2>&1 | grep -E "error: -|Executed .* tests"`；`swift test --filter <类名>`；安装 `LAUNCH_SIGN_IDENTITY="Apple Development: zhaoyingkun@163.com" ./scripts/build-app.sh --install`。

---

### Task 1: 最小验证（右键菜单在面板之上）

只做验证，不提交；结束后还原代码。

**Files:**
- Modify（临时）: `Sources/LaunchApp/ItemDragController.swift`

- [ ] **Step 1: 临时探针**

在 `start()` 的 `monitors = ...` 之前加入右键监听，并在类里加两个动作：

```swift
        let probe = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, presenter.isLauncherWindow(event.window), let view = presenter.contentView else {
                return event
            }
            let menu = NSMenu()
            menu.addItem(withTitle: "探针", action: #selector(probeTop(_:)), keyEquivalent: "").target = self
            let sub = NSMenu()
            sub.addItem(withTitle: "子探针", action: #selector(probeSub(_:)), keyEquivalent: "").target = self
            let parent = NSMenuItem(title: "子菜单", action: nil, keyEquivalent: "")
            parent.submenu = sub
            menu.addItem(parent)
            menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
            return nil
        }
        monitors.append(probe as Any)
```

```swift
    @objc private func probeTop(_ sender: Any?) {
        try? "top".write(toFile: "/tmp/launch-menu-probe.log", atomically: true, encoding: .utf8)
    }

    @objc private func probeSub(_ sender: Any?) {
        try? "sub".write(toFile: "/tmp/launch-menu-probe.log", atomically: true, encoding: .utf8)
    }
```

（`monitors = [down, drag, up].compactMap { $0 }` 会覆盖数组，所以 `append` 放在它之后。）

- [ ] **Step 2: 构建安装**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete"` 后执行安装命令。Expected: `Build complete`，安装成功。

- [ ] **Step 3: e2e 公共函数**（后面 Task 10 复用）

```bash
E=$(mktemp -d); echo "$E" > /tmp/launch-e2e-4b-dir
```

`$E/prelude.swift`：

```swift
import AppKit
import ApplicationServices

let launchID = "dev.yocn.launch"
let src = CGEventSource(stateID: .hidSystemState)
var failures = 0

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
func appElement() -> AXUIElement? { pid().map(AXUIElementCreateApplication) }
func windows() -> [AXUIElement] { appElement().map { (attr($0, kAXWindowsAttribute) as? [AXUIElement]) ?? [] } ?? [] }
func elements() -> [AXUIElement] { windows().flatMap { all($0) } }
func menuItem(_ name: String) -> AXUIElement? {
    appElement().map { all($0) }?.first { role($0) == kAXMenuItemRole && title($0) == name }
}
func layers() -> [Int] {
    guard let pid = pid() else { return [] }
    return (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap {
        ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid ? ($0[kCGWindowLayer as String] as? NSNumber)?.intValue : nil
    }
}
func panelVisible() -> Bool { layers().contains(25) }
func mouse(_ type: CGEventType, _ p: CGPoint, flags: CGEventFlags = [], button: CGMouseButton = .left) {
    let event = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button)
    event?.flags = flags
    event?.post(tap: .cghidEventTap)
}
func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
}
func click(_ p: CGPoint, flags: CGEventFlags = []) {
    mouse(.mouseMoved, p); usleep(150_000)
    mouse(.leftMouseDown, p, flags: flags); usleep(60_000)
    mouse(.leftMouseUp, p, flags: flags); wait(0.4)
}
func rightClick(_ p: CGPoint) {
    mouse(.mouseMoved, p); usleep(150_000)
    mouse(.rightMouseDown, p, button: .right); usleep(60_000)
    mouse(.rightMouseUp, p, button: .right)
}
func drag(from a: CGPoint, to b: CGPoint, flags: CGEventFlags = [], hold: Double = 0.5, steps: Int = 24) {
    mouse(.mouseMoved, a); usleep(150_000)
    mouse(.leftMouseDown, a, flags: flags); usleep(80_000)
    for i in 1 ... steps {
        let t = CGFloat(i) / CGFloat(steps)
        mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), flags: flags)
        usleep(16_000)
    }
    let end = Date().addingTimeInterval(hold)
    while Date() < end { mouse(.leftMouseDragged, b, flags: flags); wait(0.05) }
    mouse(.leftMouseUp, b, flags: flags); wait(0.8)
}
func openLauncher() {
    let open = Process(); open.executableURL = URL(fileURLWithPath: "/usr/bin/open"); open.arguments = [NSHomeDirectory() + "/Applications/Launch.app"]
    try? open.run(); open.waitUntilExit(); wait(1.5)
}
func pageDots() -> [AXUIElement] { elements().filter { role($0) == kAXButtonRole && desc($0).hasPrefix("第 ") && desc($0).hasSuffix(" 页") } }
func selectPage(_ label: String) {
    if let dot = pageDots().first(where: { desc($0) == label }) { AXUIElementPerformAction(dot, kAXPressAction as CFString); wait(0.9) }
}
func tiles() -> [(name: String, frame: CGRect)] {
    let screen = CGDisplayBounds(CGMainDisplayID())
    return elements().compactMap { e -> (name: String, frame: CGRect)? in
        guard role(e) == kAXButtonRole, let f = frame(e), f.height > 60, screen.contains(CGPoint(x: f.midX, y: f.midY)) else { return nil }
        return (desc(e), f)
    }.sorted { ($0.frame.minY.rounded(), $0.frame.minX) < ($1.frame.minY.rounded(), $1.frame.minX) }
}
func names() -> [String] { tiles().map(\.name) }
func iconCenter(_ f: CGRect) -> CGPoint { CGPoint(x: f.midX, y: f.minY + 12 + 44) }
func leadingPoint(_ f: CGRect) -> CGPoint { CGPoint(x: f.minX + 4, y: f.maxY - 6) }
func pickedCount() -> Int { elements().filter { desc($0) == "已选中" }.count }
func dismissDialogs() {
    for _ in 0 ..< 8 {
        for w in windows() where (attr(w, kAXSubroleAttribute) as? String) == "AXDialog" {
            if let ok = all(w).first(where: { role($0) == kAXButtonRole }) { AXUIElementPerformAction(ok, kAXPressAction as CFString) }
        }
        wait(0.3)
    }
}
```

- [ ] **Step 4: 探针脚本**

`$E/spike/main.swift`：

```swift
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IONBF, 0)
dismissDialogs()
let originalMouse = CGEvent(source: nil)?.location ?? .zero
CGWarpMouseCursorPosition(CGPoint(x: 756, y: 491)); wait(0.3)
openLauncher(); selectPage("第 1 页")
guard let first = tiles().first else { print("FAIL 没有图标"); exit(1) }
let log = "/tmp/launch-menu-probe.log"
try? FileManager.default.removeItem(atPath: log)

rightClick(iconCenter(first.frame)); wait(0.8)
check(layers().contains { $0 > 25 }, "S1 菜单层级高于面板（\(layers())）")
let top = menuItem("探针")
check(top != nil, "S1 辅助功能能找到菜单项")
if let top { AXUIElementPerformAction(top, kAXPressAction as CFString) } else { key(125); key(36) }
wait(0.6)
check((try? String(contentsOfFile: log, encoding: .utf8)) == "top", "S1 菜单项动作执行")
check(panelVisible(), "S1 菜单关闭后面板仍显示")

rightClick(iconCenter(first.frame)); wait(0.8)
if let parent = menuItem("子菜单").flatMap(frame) { mouse(.mouseMoved, CGPoint(x: parent.midX, y: parent.midY)); wait(0.8) }
let sub = menuItem("子探针")
check(sub != nil, "S2 悬停后能找到子菜单项")
if let sub { AXUIElementPerformAction(sub, kAXPressAction as CFString) }
wait(0.6)
check((try? String(contentsOfFile: log, encoding: .utf8)) == "sub", "S2 子菜单项动作执行")
check(panelVisible(), "S2 菜单关闭后面板仍显示")
key(53); wait(0.5)
CGWarpMouseCursorPosition(originalMouse)
print("FAILURES \(failures)")
```

Run: `E=$(cat /tmp/launch-e2e-4b-dir); swiftc -O "$E/prelude.swift" "$E/spike/main.swift" -o "$E/spike/run" && "$E/spike/run"`
Expected: 全部 `PASS`。若同步弹出有问题（菜单不出现或面板被关），改为在 `DispatchQueue.main.async` 中弹出后重试，并把结论带到 Task 8。

- [ ] **Step 5: 还原**

Run: `git checkout Sources/LaunchApp/ItemDragController.swift && rm -f /tmp/launch-menu-probe.log && git status --short`
Expected: 无输出（工作区干净）。

---

### Task 2: LayoutEditor 整体编辑

**Files:**
- Modify: `Sources/LaunchCore/LayoutEditor.swift`
- Test: `Tests/LaunchCoreTests/LayoutEditorTests.swift`

- [ ] **Step 1: 失败测试**（追加到 `LayoutEditorTests` 类末尾）

```swift
    func testGroupInsertKeepsGroupOrderBeforeAnchor() {
        let result = apply(
            .moveGroup([id(a), id(e)], to: .insert(page: 0, before: id(c))),
            [[slot(a), slot(b), slot(c), slot(d), slot(e)]]
        )

        XCTAssertEqual(result, [[slot(b), slot(a), slot(e), slot(c), slot(d)]])
    }

    func testGroupInsertAtEndOfAnotherPage() {
        let result = apply(
            .moveGroup([id(a), id(c)], to: .insert(page: 1, before: nil)),
            [[slot(a), slot(b)], [slot(c), slot(d)]]
        )

        XCTAssertEqual(result, [[slot(b)], [slot(d), slot(a), slot(c)]])
    }

    func testGroupOverflowMovesInBulk() {
        let result = apply(
            .moveGroup([id(d), id(e)], to: .insert(page: 0, before: id(a))),
            [[slot(a), slot(b)], [slot(c), slot(d)], [slot(e)]],
            capacity: 2
        )

        XCTAssertEqual(result, [[slot(d), slot(e)], [slot(a), slot(b)], [slot(c)]])
    }

    func testGroupToNewPageOverflowsIntoFollowingPage() {
        let result = apply(
            .moveGroup([id(a), id(b), id(c)], to: .newPage),
            [[slot(a), slot(b)], [slot(c), slot(d)]],
            capacity: 2
        )

        XCTAssertEqual(result, [[slot(d)], [slot(a), slot(b)], [slot(c)]])
    }

    func testGroupInsertAnchoredOnGroupMemberIsIgnored() {
        let pages = [[slot(a), slot(b), slot(c)]]

        XCTAssertEqual(apply(.moveGroup([id(a), id(b)], to: .insert(page: 0, before: id(b))), pages), pages)
    }

    func testGroupMergeIntoAppFlattensSelectedFolders() {
        let result = apply(
            .moveGroup([.folder("f"), id(e)], to: .merge(id(a))),
            [[slot(a), folder("f", [b, c]), slot(d), slot(e)]]
        )

        XCTAssertEqual(result, [[folder("new", [a, b, c, e], name: "未命名"), slot(d)]])
    }

    func testGroupMergeIntoSelectedFolderAppendsOthers() {
        let result = apply(
            .moveGroup([.folder("f"), id(b), .folder("g")], to: .merge(.folder("f"))),
            [[folder("f", [a]), slot(b), folder("g", [c, d])]]
        )

        XCTAssertEqual(result, [[folder("f", [a, b, c, d])]])
    }

    func testGroupMergeKeepsMissingMembersOfFlattenedFolder() {
        let g = LayoutSlot.folder(LayoutFolder(id: "g", name: "效率", apps: [c.identity, gone]))

        let result = apply(.moveGroup([.folder("g")], to: .merge(id(a))), [[slot(a), g]])

        XCTAssertEqual(result, [[.folder(LayoutFolder(id: "new", name: "未命名", apps: [a.identity, c.identity, gone]))]])
    }

    func testMergeIntoNewFolderTakesFirstItemPosition() {
        let result = apply(
            .mergeIntoNewFolder([id(b), .folder("f")]),
            [[slot(a), slot(b), slot(c)], [slot(d), folder("f", [e])]]
        )

        XCTAssertEqual(result, [[slot(a), folder("new", [b, e], name: "未命名"), slot(c)], [slot(d)]])
    }

    func testMergeIntoNewFolderNeedsTwoItems() {
        let pages = [[slot(a), slot(b)]]

        XCTAssertEqual(apply(.mergeIntoNewFolder([id(a)]), pages), pages)
    }
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter LayoutEditorTests 2>&1 | grep -E "error:|Executed"`
Expected: 编译错误，`LayoutEdit` 没有 `moveGroup`/`mergeIntoNewFolder`。

- [ ] **Step 3: 实现**

`LayoutEdit` 增加两项：

```swift
public enum LayoutEdit: Equatable, Sendable {
    case move(LayoutItemID, to: LayoutDropTarget)
    case moveGroup([LayoutItemID], to: LayoutDropTarget)
    case mergeIntoNewFolder([LayoutItemID])
    case moveOutOfFolder(app: String, folder: String, to: LayoutDropTarget)
    case reorderInFolder(folder: String, app: String, before: String?)
    case renameFolder(folder: String, name: String)
}
```

`perform(_:)` 增加分支：

```swift
        case .moveGroup(let items, let target):
            moveGroup(items, to: target)
        case .mergeIntoNewFolder(let items):
            mergeIntoNewFolder(items)
```

`cascade(from:)` 改为整批挤出（单项时行为不变）：

```swift
    mutating func cascade(from start: Int) {
        var page = start
        while page < pages.count, visibleCount(page) > capacity {
            var overflow: [LayoutSlot] = []
            while visibleCount(page) > capacity, let last = pages[page].lastIndex(where: { itemID(of: $0) != nil }) {
                overflow.insert(pages[page].remove(at: last), at: 0)
            }
            if page + 1 == pages.count {
                pages.append([])
            }
            pages[page + 1].insert(contentsOf: overflow, at: 0)
            page += 1
        }
    }
```

在 `Editor` 末尾（`rename` 之后）加入：

```swift
    mutating func moveGroup(_ items: [LayoutItemID], to target: LayoutDropTarget) -> Bool {
        switch target {
        case .merge(let into):
            return merge(items.filter { $0 != into }, into: into)
        case .insert(_, let before?) where items.contains(before):
            return false
        default:
            break
        }
        let page = documentPage(for: target)
        let slots = remove(items)
        guard !slots.isEmpty else {
            return false
        }
        let start: Int
        if let page {
            var index = pages[page].endIndex
            if case .insert(_, let before?) = target, let anchor = locate(before), anchor.page == page {
                index = anchor.slot
            }
            pages[page].insert(contentsOf: slots, at: index)
            start = page
        } else {
            pages.append(slots)
            start = pages.count - 1
        }
        cascade(from: start)
        pages = pages.filter { !$0.isEmpty }
        return true
    }

    mutating func mergeIntoNewFolder(_ items: [LayoutItemID]) -> Bool {
        let present = items.filter { locate($0) != nil }
        guard present.count >= 2, let first = locate(present[0]) else {
            return false
        }
        let head = Self.apps(in: pages[first.page][first.slot])
        let members = head + remove(Array(present.dropFirst())).flatMap(Self.apps(in:))
        guard let anchor = locate(present[0]) else {
            return false
        }
        pages[anchor.page][anchor.slot] = .folder(LayoutFolder(
            id: newFolderID,
            name: LayoutEditor.untitledFolderName,
            apps: members
        ))
        pages = pages.filter { !$0.isEmpty }
        return true
    }

    // 选中的文件夹拆开，成员（含未安装应用）并入目标
    mutating func merge(_ items: [LayoutItemID], into target: LayoutItemID) -> Bool {
        guard locate(target) != nil else {
            return false
        }
        let members = remove(items).flatMap(Self.apps(in:))
        guard !members.isEmpty, let anchor = locate(target) else {
            return false
        }
        switch pages[anchor.page][anchor.slot] {
        case .app(let identity):
            pages[anchor.page][anchor.slot] = .folder(LayoutFolder(
                id: newFolderID,
                name: LayoutEditor.untitledFolderName,
                apps: [identity] + members
            ))
        case .folder(let folder):
            pages[anchor.page][anchor.slot] = .folder(LayoutFolder(
                id: folder.id,
                name: folder.name,
                apps: folder.apps + members
            ))
        case .empty:
            return false
        }
        pages = pages.filter { !$0.isEmpty }
        return true
    }

    mutating func remove(_ items: [LayoutItemID]) -> [LayoutSlot] {
        var removed: [LayoutSlot] = []
        for item in items {
            if let location = locate(item) {
                removed.append(pages[location.page].remove(at: location.slot))
            }
        }
        return removed
    }

    static func apps(in slot: LayoutSlot) -> [AppIdentity] {
        switch slot {
        case .app(let identity):
            [identity]
        case .folder(let folder):
            folder.apps
        case .empty:
            []
        }
    }
```

- [ ] **Step 4: 确认通过**

Run: `swift test --filter LayoutEditorTests 2>&1 | grep -E "error:|Executed"`
Expected: `Executed 30 tests, with 0 failures`（原 20 个 + 新 10 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchCore/LayoutEditor.swift Tests/LaunchCoreTests/LayoutEditorTests.swift
git commit -m "feat(布局): 整体移动与合并到新文件夹的布局编辑"
```

---

### Task 3: MultiSelection 与矩形命中

**Files:**
- Create: `Sources/LaunchApp/MultiSelection.swift`
- Modify: `Sources/LaunchApp/GridHitTester.swift`
- Test: `Tests/LaunchAppTests/MultiSelectionTests.swift`、`Tests/LaunchAppTests/GridHitTesterTests.swift`

- [ ] **Step 1: 失败测试**

`Tests/LaunchAppTests/MultiSelectionTests.swift`：

```swift
import LaunchCore
import XCTest
@testable import LaunchApp

final class MultiSelectionTests: XCTestCase {
    private let apps = makeApps(count: 4)

    private func id(_ index: Int) -> LayoutItemID {
        .app(apps[index].identity.stableKey)
    }

    func testToggleAddsAndRemoves() {
        var selection = MultiSelection()

        selection.toggle(id(0))
        selection.toggle(id(1))
        selection.toggle(id(0))

        XCTAssertEqual(selection.items, [id(1)])
    }

    func testMarqueeAddsHitsOnTopOfBaseAndShrinksBack() {
        var selection = MultiSelection()
        selection.toggle(id(0))

        selection.beginMarquee()
        selection.updateMarquee(hits: [id(1), id(2)])
        XCTAssertEqual(selection.items, [id(0), id(1), id(2)])

        selection.updateMarquee(hits: [id(1)])
        XCTAssertEqual(selection.items, [id(0), id(1)])

        selection.endMarquee()
        XCTAssertEqual(selection.count, 2)
    }

    func testOrderedFollowsPagesAndRetainDropsMissing() {
        var selection = MultiSelection()
        selection.toggle(id(3))
        selection.toggle(.folder("f"))
        selection.toggle(id(0))
        let pages: [[ResolvedItem]] = [
            [.app(apps[0]), makeFolder(id: "f", name: "效率", apps: [apps[1]])],
            [.app(apps[2]), .app(apps[3])],
        ]

        XCTAssertEqual(selection.ordered(in: pages), [id(0), .folder("f"), id(3)])

        selection.retain([id(0)])
        XCTAssertEqual(selection.items, [id(0)])
    }
}
```

追加到 `GridHitTesterTests` 类末尾：

```swift
    func testTilesIntersectingRect() {
        let first = tester.tileRect(0)
        let ninth = tester.tileRect(8)
        let rect = CGRect(x: first.midX, y: first.midY, width: ninth.midX - first.midX, height: ninth.midY - first.midY)

        XCTAssertEqual(tester.tileIndices(intersecting: rect, itemCount: 20), [0, 1, 7, 8])
        XCTAssertEqual(tester.tileIndices(intersecting: rect, itemCount: 8), [0, 1, 7])
    }
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter "MultiSelectionTests|GridHitTesterTests" 2>&1 | grep -E "error:|Executed"`
Expected: 编译错误，找不到 `MultiSelection` 与 `tileIndices`。

- [ ] **Step 3: 实现**

`Sources/LaunchApp/MultiSelection.swift`：

```swift
import LaunchCore

// 选框期间以按下前的选择为底，加上框到的项
struct MultiSelection: Equatable {
    private(set) var items: Set<LayoutItemID> = []
    private var marqueeBase: Set<LayoutItemID>?

    var isEmpty: Bool {
        items.isEmpty
    }

    var count: Int {
        items.count
    }

    func contains(_ item: LayoutItemID) -> Bool {
        items.contains(item)
    }

    mutating func toggle(_ item: LayoutItemID) {
        if items.remove(item) == nil {
            items.insert(item)
        }
    }

    mutating func beginMarquee() {
        marqueeBase = items
    }

    mutating func updateMarquee(hits: Set<LayoutItemID>) {
        items = (marqueeBase ?? items).union(hits)
    }

    mutating func endMarquee() {
        marqueeBase = nil
    }

    mutating func retain(_ existing: Set<LayoutItemID>) {
        items.formIntersection(existing)
        marqueeBase?.formIntersection(existing)
    }

    func ordered(in pages: [[ResolvedItem]]) -> [LayoutItemID] {
        pages.joined().compactMap(\.layoutID).filter(items.contains)
    }
}
```

`GridHitTester` 在 `tileIndex(at:itemCount:)` 之后加：

```swift
    func tileIndices(intersecting rect: CGRect, itemCount: Int) -> [Int] {
        (0 ..< itemCount).filter { tileRect($0).intersects(rect) }
    }
```

- [ ] **Step 4: 确认通过**

Run: `swift test --filter "MultiSelectionTests|GridHitTesterTests" 2>&1 | grep -E "error:|Executed"`
Expected: `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/MultiSelection.swift Sources/LaunchApp/GridHitTester.swift Tests/LaunchAppTests/MultiSelectionTests.swift Tests/LaunchAppTests/GridHitTesterTests.swift
git commit -m "feat(编辑): 多选集合与选框命中"
```

---

### Task 4: 拖拽会话支持一组图标

**Files:**
- Modify: `Sources/LaunchApp/DragSession.swift`
- Test: `Tests/LaunchAppTests/DragSessionTests.swift`

- [ ] **Step 1: 失败测试**（追加到 `DragSessionTests` 类末尾）

```swift
    private func groupSession(target: DragTarget? = nil) -> DragSession {
        var session = DragSession(item: .app(app), origin: .grid(page: 0, index: 1), group: [0: [1, 3], 1: [0]])
        if let target {
            _ = session.update(hit: .target(target), outsideFolder: false, now: 0)
            _ = session.update(hit: .target(target), outsideFolder: false, now: 1)
        }
        return session
    }

    func testGroupPreviewRemovesPickedItemsOnEveryPage() {
        let preview = groupSession().preview

        XCTAssertEqual(preview.count, 3)
        XCTAssertEqual(preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid), [.item(0), .item(2), .item(4)])
        XCTAssertEqual(preview.entries(page: 1, itemCount: 2, capacity: 35, in: .grid), [.item(1)])
    }

    func testGroupPreviewOpensOneGapPerItemAtInsertion() {
        let preview = groupSession(target: .insert(page: 0, index: 1)).preview

        XCTAssertEqual(
            preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid),
            [.item(0), .gap, .gap, .gap, .item(2), .item(4)]
        )
        XCTAssertEqual(preview.entries(page: 0, itemCount: 5, capacity: 4, in: .grid), [.item(0), .gap, .gap, .gap])
    }

    func testGroupHitSkipsPickedItemsAndGapsKeepTarget() {
        let preview = groupSession(target: .insert(page: 0, index: 1)).preview
        let entries = preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid)

        XCTAssertEqual(preview.hit(for: .item(4, .leading), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 1)))
        XCTAssertEqual(preview.hit(for: .item(5, .trailing), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 3)))
        XCTAssertEqual(preview.hit(for: .item(3, .leading), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 1)))
        XCTAssertEqual(preview.hit(for: .item(4, .center), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.merge(page: 0, index: 2)))
        XCTAssertEqual(preview.hit(for: .end, entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 3)))
    }

    func testGroupLedByFolderCanMerge() {
        let folder = ResolvedItem.folder(ResolvedFolder(id: "f", name: "x", apps: [app]))
        let preview = DragSession(item: folder, origin: .grid(page: 0, index: 0), group: [0: [0, 1]]).preview
        let entries = preview.entries(page: 0, itemCount: 4, capacity: 35, in: .grid)

        XCTAssertEqual(preview.hit(for: .item(0, .center), entries: entries, itemCount: 4, page: 0, in: .grid), .target(.merge(page: 0, index: 2)))
    }

    func testGroupDropTreatsUnconfirmedMergeAsInsert() {
        XCTAssertEqual(groupSession().dropTarget(for: .target(.merge(page: 0, index: 4))), .insert(page: 0, index: 2))
    }
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter DragSessionTests 2>&1 | grep -E "error:|Executed"`
Expected: 编译错误，`DragSession` 没有 `group` 参数。

- [ ] **Step 3: 实现**

`DragPreview` 改为（`sourceIndex` 保持不变）：

```swift
struct DragPreview: Equatable {
    let item: ResolvedItem
    let origin: DragOrigin
    // 一起拖动时各页被拿起项的位置（含按住的那个）；单项拖拽为空
    let group: [Int: [Int]]
    let area: DragArea
    let target: DragTarget?
    let hasExtraPage: Bool

    var isGroup: Bool {
        !group.isEmpty
    }

    var count: Int {
        isGroup ? group.values.reduce(0) { $0 + $1.count } : 1
    }

    var canMerge: Bool {
        if isGroup {
            return true
        }
        if case .app = item {
            return true
        }
        return false
    }

    func sourceIndex(onPage page: Int, in pageArea: DragArea) -> Int? {
        // 原实现不变
    }

    func sourceIndices(onPage page: Int, in pageArea: DragArea) -> [Int] {
        guard isGroup else {
            return sourceIndex(onPage: page, in: pageArea).map { [$0] } ?? []
        }
        return pageArea == .grid ? group[page] ?? [] : []
    }

    func entries(page: Int, itemCount: Int, capacity: Int, in pageArea: DragArea) -> [PreviewEntry] {
        if isGroup {
            return groupEntries(page: page, itemCount: itemCount, capacity: capacity, in: pageArea)
        }
        // 以下为原单项实现，不变
    }

    private func groupEntries(page: Int, itemCount: Int, capacity: Int, in pageArea: DragArea) -> [PreviewEntry] {
        let sources = Set(sourceIndices(onPage: page, in: pageArea))
        var entries = (0 ..< itemCount).filter { !sources.contains($0) }.map(PreviewEntry.item)
        if pageArea == area, case .insert(let targetPage, let index)? = target, targetPage == page {
            entries.insert(contentsOf: repeatElement(.gap, count: count), at: min(index, entries.count))
            return Array(entries.prefix(capacity))
        }
        return entries
    }

    func hit(for gridHit: GridHit, entries: [PreviewEntry], itemCount: Int, page: Int, in pageArea: DragArea) -> DragHit {
        let sources = sourceIndices(onPage: page, in: pageArea)
        switch gridHit {
        case .outside:
            return .none
        case .edge(let direction):
            return pageArea == .grid ? .edge(direction) : .none
        case .end:
            return .target(.insert(page: page, index: itemCount - sources.count))
        case .item(let cell, let zone):
            guard case .item(let index) = entries[cell] else {
                // 一组空位都代表当前插入位置
                if isGroup, pageArea == area, let target, case .insert = target, target.page == page {
                    return .target(target)
                }
                return .target(.insert(page: page, index: cell))
            }
            if zone == .center, canMerge, pageArea == .grid {
                return .target(.merge(page: page, index: index))
            }
            let remaining = index - sources.filter { $0 < index }.count
            return .target(.insert(page: page, index: zone == .trailing ? remaining + 1 : remaining))
        }
    }
}
```

`DragSession`：

```swift
    let item: ResolvedItem
    let origin: DragOrigin
    let group: [Int: [Int]]
```

```swift
    init(item: ResolvedItem, origin: DragOrigin, group: [Int: [Int]] = [:]) {
        self.item = item
        self.origin = origin
        self.group = group
        if case .folder = origin {
            area = .folder
        } else {
            area = .grid
        }
    }

    var preview: DragPreview {
        DragPreview(item: item, origin: origin, group: group, area: area, target: target, hasExtraPage: hasExtraPage)
    }
```

`dropTarget(for:)` 最后两行改为：

```swift
        let sources = preview.sourceIndices(onPage: page, in: area)
        return .insert(page: page, index: index - sources.filter { $0 < index }.count)
```

- [ ] **Step 4: 确认通过**

Run: `swift test --filter "DragSessionTests|LauncherModelDragTests" 2>&1 | grep -E "error:|Executed"`
Expected: `0 failures`（单项拖拽的原有测试不受影响）。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/DragSession.swift Tests/LaunchAppTests/DragSessionTests.swift
git commit -m "feat(编辑): 拖拽会话支持一组图标"
```

---

### Task 5: 多选菜单

**Files:**
- Create: `Sources/LaunchApp/SelectionMenu.swift`
- Test: `Tests/LaunchAppTests/SelectionMenuTests.swift`

- [ ] **Step 1: 失败测试**

```swift
import AppKit
import XCTest
@testable import LaunchApp

@MainActor
final class SelectionMenuTests: XCTestCase {
    private func trigger(_ item: NSMenuItem?) {
        guard let item, let action = item.action else {
            return XCTFail("菜单项没有动作")
        }
        _ = (item.target as? NSObject)?.perform(action, with: item)
    }

    func testMenuListsCommandsForSelection() {
        var chosen: [SelectionCommand] = []
        let builder = SelectionMenu { chosen.append($0) }
        let menu = builder.makeMenu(SelectionMenuContent(
            count: 3,
            folders: [.init(id: "f", name: "效率")],
            pageCount: 2
        ))
        let pages = menu.items[5].submenu

        XCTAssertEqual(menu.items.map(\.title), ["已选中 3 个项目", "", "合并到新文件夹", "合并到“效率”", "", "移动到"])
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertTrue(menu.items[2].isEnabled)
        XCTAssertEqual(pages?.items.map(\.title), ["第 1 页", "第 2 页", "", "新页面"])

        trigger(menu.items[2])
        trigger(menu.items[3])
        trigger(pages?.items[1])
        trigger(pages?.items[3])
        XCTAssertEqual(chosen, [.mergeIntoNewFolder, .mergeInto(folder: "f"), .moveToPage(1), .moveToNewPage])
    }

    func testSingleItemCannotMerge() {
        let menu = SelectionMenu { _ in }.makeMenu(SelectionMenuContent(
            count: 1,
            folders: [.init(id: "f", name: "效率")],
            pageCount: 1
        ))

        XCTAssertEqual(menu.items.map(\.title), ["已选中 1 个项目", "", "合并到新文件夹", "", "移动到"])
        XCTAssertFalse(menu.items[2].isEnabled)
    }
}
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter SelectionMenuTests 2>&1 | grep -E "error:|Executed"`
Expected: 编译错误，找不到 `SelectionMenu`。

- [ ] **Step 3: 实现** `Sources/LaunchApp/SelectionMenu.swift`

```swift
import AppKit

struct SelectionMenuContent: Equatable {
    struct Folder: Equatable {
        let id: String
        let name: String
    }

    let count: Int
    let folders: [Folder]
    let pageCount: Int

    var canMerge: Bool {
        count >= 2
    }
}

enum SelectionCommand: Equatable {
    case mergeIntoNewFolder
    case mergeInto(folder: String)
    case moveToPage(Int)
    case moveToNewPage
}

@MainActor
final class SelectionMenu: NSObject {
    private let onCommand: (SelectionCommand) -> Void
    private var commands: [SelectionCommand] = []

    init(onCommand: @escaping (SelectionCommand) -> Void) {
        self.onCommand = onCommand
    }

    func makeMenu(_ content: SelectionMenuContent) -> NSMenu {
        commands = []
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "已选中 \(content.count) 个项目", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item("合并到新文件夹", .mergeIntoNewFolder, isEnabled: content.canMerge))
        if content.canMerge {
            for folder in content.folders {
                menu.addItem(item("合并到“\(folder.name)”", .mergeInto(folder: folder.id)))
            }
        }
        menu.addItem(.separator())
        let pages = NSMenu()
        pages.autoenablesItems = false
        for page in 0 ..< content.pageCount {
            pages.addItem(item("第 \(page + 1) 页", .moveToPage(page)))
        }
        pages.addItem(.separator())
        pages.addItem(item("新页面", .moveToNewPage))
        let move = NSMenuItem(title: "移动到", action: nil, keyEquivalent: "")
        move.submenu = pages
        menu.addItem(move)
        return menu
    }

    private func item(_ title: String, _ command: SelectionCommand, isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.tag = commands.count
        item.isEnabled = isEnabled
        commands.append(command)
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        onCommand(commands[sender.tag])
    }
}
```

- [ ] **Step 4: 确认通过**

Run: `swift test --filter SelectionMenuTests 2>&1 | grep -E "error:|Executed"`
Expected: `Executed 2 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/SelectionMenu.swift Tests/LaunchAppTests/SelectionMenuTests.swift
git commit -m "feat(编辑): 多选右键菜单"
```

---

### Task 6: LauncherModel 多选

**Files:**
- Modify: `Sources/LaunchApp/LauncherModel.swift`、`Sources/LaunchApp/LauncherView.swift:376`
- Modify: `Tests/LaunchAppTests/LauncherModelDragTests.swift:298`
- Test: `Tests/LaunchAppTests/LauncherModelSelectionTests.swift`

- [ ] **Step 1: 失败测试** `Tests/LaunchAppTests/LauncherModelSelectionTests.swift`

```swift
import CoreGraphics
import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelSelectionTests: XCTestCase {
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

    private func center(_ index: Int) -> CGPoint {
        let rect = tile(index)
        return CGPoint(x: rect.midX, y: rect.minY + layout.tilePadding + layout.iconSide / 2)
    }

    private func leading(_ index: Int) -> CGPoint {
        let rect = tile(index)
        return CGPoint(x: rect.minX + 4, y: rect.maxY - 6)
    }

    private func id(_ app: CatalogApp) -> LayoutItemID {
        .app(app.identity.stableKey)
    }

    @MainActor
    private func makeModel(pages: [[ResolvedItem]]) -> (LauncherModel, EditLog) {
        let model = LauncherModel()
        let log = EditLog()
        model.updateLayout(pages)
        model.canEditLayout = true
        model.onEdit = { log.edits.append($0) }
        model.updateHomeLayout(layout)
        model.updatePageWidth(layout.contentSize.width)
        model.updateGridFrame(gridFrame)
        return (model, log)
    }

    @MainActor
    private func commandClick(_ model: LauncherModel, _ index: Int) {
        XCTAssertTrue(model.beginMarquee(at: center(index)))
        model.endMarquee()
    }

    @MainActor
    func testCommandClickTogglesItems() {
        let apps = makeApps(count: 4)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])

        commandClick(model, 1)
        commandClick(model, 3)
        commandClick(model, 1)

        XCTAssertEqual(model.multiSelection.items, [id(apps[3])])
        XCTAssertNil(model.marqueeRect)
    }

    @MainActor
    func testMarqueeAddsIntersectingTilesToExistingSelection() {
        let apps = makeApps(count: 12)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 10)

        XCTAssertTrue(model.beginMarquee(at: CGPoint(x: tile(0).minX - 2, y: tile(0).minY + 1)))
        model.updateMarquee(to: center(8))
        XCTAssertNotNil(model.marqueeRect)
        XCTAssertEqual(model.multiSelection.items, Set([0, 1, 7, 8, 10].map { id(apps[$0]) }))

        model.updateMarquee(to: center(1))
        XCTAssertEqual(model.multiSelection.items, Set([0, 1, 10].map { id(apps[$0]) }))
        model.endMarquee()

        XCTAssertNil(model.marqueeRect)
        XCTAssertEqual(model.multiSelection.count, 3)
    }

    @MainActor
    func testMultiSelectNeedsEditableGridWithoutSearchOrFolder() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [[makeFolder(id: "f", name: "效率", apps: apps)]])

        XCTAssertFalse(model.beginMarquee(at: CGPoint(x: 5, y: 5)))
        model.canEditLayout = false
        XCTAssertFalse(model.beginMarquee(at: center(0)))
        model.canEditLayout = true
        model.showFolder(id: "f")
        XCTAssertFalse(model.beginMarquee(at: center(0)))
        model.closeFolder()
        model.setQuery("App")
        XCTAssertFalse(model.beginMarquee(at: center(0)))
        model.setQuery("")
        XCTAssertTrue(model.beginMarquee(at: center(0)))
    }

    @MainActor
    func testEscapeClearsSelectionBeforeStoppingJiggle() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        model.beginJiggling()
        commandClick(model, 0)

        XCTAssertEqual(model.handleEscape(), .clearedSelection)
        XCTAssertTrue(model.multiSelection.isEmpty)
        XCTAssertEqual(model.handleEscape(), .stoppedJiggling)
    }

    @MainActor
    func testSearchActivationAndPresentationClearSelection() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])

        commandClick(model, 0)
        model.setQuery("App")
        XCTAssertTrue(model.multiSelection.isEmpty)

        model.setQuery("")
        commandClick(model, 0)
        model.moveSelection(.right)
        XCTAssertNil(model.activateSelection())
        XCTAssertTrue(model.multiSelection.isEmpty)
        XCTAssertNotNil(model.activateSelection())

        commandClick(model, 1)
        model.prepareForPresentation()
        XCTAssertTrue(model.multiSelection.isEmpty)
    }

    @MainActor
    func testLayoutUpdateDropsMissingItems() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 0)
        commandClick(model, 1)

        model.updateLayout([[.app(apps[0]), .app(apps[2])]])

        XCTAssertEqual(model.multiSelection.items, [id(apps[0])])
    }

    @MainActor
    func testPickedEntriesAreMarked() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 1)

        XCTAssertEqual(
            model.gridEntries(page: 0, items: model.pages[0], area: .grid).map(\.isPicked),
            [false, true, false]
        )
    }

    @MainActor
    func testMenuOnlyOnPickedItemAndListsPickedFolders() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [[.app(apps[0]), .app(apps[1]), makeFolder(id: "f", name: "效率", apps: [apps[2]])]])
        commandClick(model, 2)
        commandClick(model, 1)

        XCTAssertNil(model.selectionMenu(at: center(0)))
        XCTAssertEqual(
            model.selectionMenu(at: center(1)),
            SelectionMenuContent(count: 2, folders: [.init(id: "f", name: "效率")], pageCount: 1)
        )
    }

    @MainActor
    func testMenuCommandsBecomeGroupEditsInPageOrder() {
        let apps = makeApps(count: 4)
        let (model, log) = makeModel(pages: [
            [.app(apps[0]), .app(apps[1])],
            [makeFolder(id: "f", name: "效率", apps: [apps[3]]), .app(apps[2])],
        ])
        let picked: [LayoutItemID] = [id(apps[1]), .folder("f"), id(apps[2])]
        let commands: [SelectionCommand] = [.mergeIntoNewFolder, .mergeInto(folder: "f"), .moveToPage(0), .moveToNewPage]

        for command in commands {
            for item in picked.reversed() {
                model.toggleMultiSelection(item)
            }
            model.performSelectionCommand(command)
            XCTAssertTrue(model.multiSelection.isEmpty)
        }

        XCTAssertEqual(log.edits, [
            .mergeIntoNewFolder(picked),
            .moveGroup(picked, to: .merge(.folder("f"))),
            .moveGroup(picked, to: .insert(page: 0, before: nil)),
            .moveGroup(picked, to: .newPage),
        ])
    }

    @MainActor
    func testDraggingPickedItemMovesWholeGroup() {
        let apps = makeApps(count: 8)
        let (model, log) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 3)
        commandClick(model, 1)
        guard let press = model.itemPress(at: center(3)) else {
            return XCTFail("no item")
        }

        XCTAssertEqual(model.dragCount(for: press), 2)
        model.beginItemDrag(press, at: center(3))
        XCTAssertEqual(model.dragPreview?.count, 2)
        model.updateItemDrag(at: leading(3), now: 0)
        model.updateItemDrag(at: leading(3), now: 0.2)
        XCTAssertEqual(model.dragPreview?.target, .insert(page: 0, index: 3))
        model.endItemDrag(at: leading(3), now: 0.3)

        XCTAssertEqual(log.edits, [.moveGroup([id(apps[1]), id(apps[3])], to: .insert(page: 0, before: id(apps[5])))])
        XCTAssertTrue(model.multiSelection.isEmpty)
        XCTAssertEqual(model.landing?.entryIDs, ["app:" + apps[1].identity.stableKey, "app:" + apps[3].identity.stableKey])
    }

    @MainActor
    func testGroupDroppedOnAppCenterMerges() {
        let apps = makeApps(count: 6)
        let (model, log) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 0)
        commandClick(model, 1)
        guard let press = model.itemPress(at: center(0)) else {
            return XCTFail("no item")
        }

        model.beginItemDrag(press, at: center(0))
        model.updateItemDrag(at: center(1), now: 0)
        model.updateItemDrag(at: center(1), now: 0.15)
        model.endItemDrag(at: center(1), now: 0.2)

        XCTAssertEqual(log.edits, [.moveGroup([id(apps[0]), id(apps[1])], to: .merge(id(apps[3])))])
    }

    @MainActor
    func testDraggingUnpickedItemDropsSelection() {
        let apps = makeApps(count: 4)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        commandClick(model, 1)
        commandClick(model, 2)
        guard let press = model.itemPress(at: center(0)) else {
            return XCTFail("no item")
        }

        XCTAssertEqual(model.dragCount(for: press), 1)
        model.beginItemDrag(press, at: center(0))

        XCTAssertTrue(model.multiSelection.isEmpty)
        XCTAssertEqual(model.dragPreview?.isGroup, false)
    }

    @MainActor
    func testModifiedClickDoesNotDragPages() {
        let apps = makeApps(count: 40)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        model.isModifiedClick = true

        model.dragPage(by: -300)

        XCTAssertFalse(model.isPageDragging)
    }
}
```

`LauncherModelDragTests.swift:298` 改为：

```swift
        XCTAssertEqual(model.landing?.entryIDs, ["app:" + apps[4].identity.stableKey])
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter LauncherModelSelectionTests 2>&1 | grep -E "error:|Executed"`
Expected: 编译错误，找不到 `multiSelection`、`beginMarquee` 等。

- [ ] **Step 3: 实现** `LauncherModel.swift`

`EscapeOutcome` 在 `closedFolder` 之后加 `case clearedSelection`。

`GridEntry` 增加字段：

```swift
        let id: String
        let content: Content
        let isMergeTarget: Bool
        let isPicked: Bool
```

`Landing` 改为：

```swift
    struct Landing: Equatable {
        let entryIDs: Set<String>
        let from: CGRect
    }
```

属性：在 `var folderNameDraft = ""` 之前加

```swift
    private(set) var multiSelection = MultiSelection()
    private(set) var marqueeRect: CGRect?
```

在 `@ObservationIgnored private var pendingLayout` 之后加

```swift
    // ⌘ 或 ⌃ 按下的点击；SwiftUI 的翻页与点空白手势不受事件监听拦截，靠它忽略
    @ObservationIgnored var isModifiedClick = false
    @ObservationIgnored private var marqueeStart: CGPoint?
    @ObservationIgnored private var dragGroup: [LayoutItemID] = []
```

`canDragItems` 之后加：

```swift
    var canMultiSelect: Bool {
        canDragItems && openFolder == nil
    }

    func toggleMultiSelection(_ item: LayoutItemID) {
        guard canMultiSelect else {
            return
        }
        multiSelection.toggle(item)
    }

    @discardableResult
    func clearMultiSelection() -> Bool {
        guard !multiSelection.isEmpty else {
            return false
        }
        multiSelection = MultiSelection()
        return true
    }

    func beginMarquee(at point: CGPoint) -> Bool {
        guard canMultiSelect, gridFrame.contains(point) else {
            return false
        }
        marqueeStart = point
        multiSelection.beginMarquee()
        return true
    }

    func updateMarquee(to point: CGPoint) {
        guard let start = marqueeStart, let homeLayout else {
            return
        }
        let rect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        marqueeRect = rect
        let items = visibleItems
        let hits = GridHitTester(layout: homeLayout, frame: gridFrame)
            .tileIndices(intersecting: rect, itemCount: items.count)
            .compactMap { items[$0].layoutID }
        var selection = multiSelection
        selection.updateMarquee(hits: Set(hits))
        setMultiSelection(selection)
    }

    // 没拖出选框即为 ⌘ 单击，切换按下处图标的选中状态
    func endMarquee() {
        guard let start = marqueeStart else {
            return
        }
        var selection = multiSelection
        if marqueeRect == nil, let item = itemPress(at: start)?.item.layoutID {
            selection.toggle(item)
        }
        selection.endMarquee()
        setMultiSelection(selection)
        marqueeStart = nil
        marqueeRect = nil
    }

    func dragCount(for press: ItemPress) -> Int {
        isGroupDrag(press) ? multiSelection.count : 1
    }

    func selectionMenu(at point: CGPoint) -> SelectionMenuContent? {
        guard canMultiSelect, let item = itemPress(at: point)?.item.layoutID, multiSelection.contains(item) else {
            return nil
        }
        let gridPages = pages
        let folders = gridPages.joined().compactMap { item -> SelectionMenuContent.Folder? in
            guard case .folder(let folder) = item, multiSelection.contains(.folder(folder.id)) else {
                return nil
            }
            return SelectionMenuContent.Folder(id: folder.id, name: folder.name)
        }
        return SelectionMenuContent(
            count: multiSelection.ordered(in: gridPages).count,
            folders: folders,
            pageCount: gridPages.count
        )
    }

    func performSelectionCommand(_ command: SelectionCommand) {
        let items = multiSelection.ordered(in: pages)
        guard canMultiSelect, !items.isEmpty else {
            return
        }
        let edit: LayoutEdit
        switch command {
        case .mergeIntoNewFolder:
            edit = .mergeIntoNewFolder(items)
        case .mergeInto(let folder):
            edit = .moveGroup(items, to: .merge(.folder(folder)))
        case .moveToPage(let page):
            edit = .moveGroup(items, to: .insert(page: page, before: nil))
        case .moveToNewPage:
            edit = .moveGroup(items, to: .newPage)
        }
        clearMultiSelection()
        selectedIndex = nil
        onEdit?(edit)
    }

    private func isGroupDrag(_ press: ItemPress) -> Bool {
        guard case .grid = press.origin, let item = press.item.layoutID else {
            return false
        }
        return multiSelection.count > 1 && multiSelection.contains(item)
    }

    private func setMultiSelection(_ selection: MultiSelection) {
        if selection != multiSelection {
            multiSelection = selection
        }
    }

    private static func groupSources(_ items: [LayoutItemID], in pages: [[ResolvedItem]]) -> [Int: [Int]] {
        let wanted = Set(items)
        var sources: [Int: [Int]] = [:]
        for (page, pageItems) in pages.enumerated() {
            for (index, item) in pageItems.enumerated() where item.layoutID.map(wanted.contains) == true {
                sources[page, default: []].append(index)
            }
        }
        return sources
    }
```

`beginItemDrag`：

```swift
    func beginItemDrag(_ press: ItemPress, at point: CGPoint) {
        guard canDragItems else {
            return
        }
        selectedIndex = nil
        folderSelectedIndex = nil
        dragStartPoint = point
        if isGroupDrag(press) {
            dragGroup = multiSelection.ordered(in: pages)
        } else {
            dragGroup = []
            clearMultiSelection()
        }
        dragSession = DragSession(item: press.item, origin: press.origin, group: Self.groupSources(dragGroup, in: pages))
        publishDragPreview()
    }
```

`endItemDrag` 中落位与清空：

```swift
        if edit != nil, case .insert? = target, let frame = frame(of: preview.origin) {
            let ids = preview.isGroup ? dragGroup.map { Self.entryID($0) } : [Self.entryID(preview.item, index: 0)]
            landing = Landing(
                entryIDs: Set(ids),
                from: frame.offsetBy(dx: point.x - dragStartPoint.x, dy: point.y - dragStartPoint.y)
            )
        }
        if edit != nil, preview.isGroup {
            clearMultiSelection()
        }
        finishItemDrag()
```

`entryID(_:index:)` 之后加：

```swift
    static func entryID(_ item: LayoutItemID) -> String {
        switch item {
        case .app(let key):
            "app:" + key
        case .folder(let id):
            "folder:" + id
        }
    }
```

`gridEntries`：空位编号去重，并标记选中：

```swift
        var seen = Set<String>()
        var gaps = 0
        return entries.map { entry in
            switch entry {
            case .gap:
                defer { gaps += 1 }
                return GridEntry(id: gaps == 0 ? "drag-gap" : "drag-gap-\(gaps)", content: .gap, isMergeTarget: false, isPicked: false)
            case .item(let index):
                let base = Self.entryID(items[index], index: index)
                let id = seen.insert(base).inserted ? base : "\(base)#\(index)"
                let isMergeTarget = preview?.area == area && preview?.target == .merge(page: page, index: index)
                let isPicked = area == .grid && items[index].layoutID.map(multiSelection.contains) == true
                return GridEntry(id: id, content: .item(items[index], index: index), isMergeTarget: isMergeTarget, isPicked: isPicked)
            }
        }
```

`finishItemDrag()` 开头加 `dragGroup = []`。

`layoutEdit(for:preview:)` 的 `.insert` 分支与结尾：

```swift
        case .insert(let page, let index):
            if preview.hasExtraPage, page == gridPages.count - 1 {
                dropTarget = .newPage
            } else {
                let sources = Set(preview.sourceIndices(onPage: page, in: .grid))
                let items = (gridPages.indices.contains(page) ? gridPages[page] : [])
                    .enumerated()
                    .filter { !sources.contains($0.offset) }
                    .map(\.element)
                dropTarget = .insert(page: page, before: index < items.count ? items[index].layoutID : nil)
            }
        }
        if preview.isGroup {
            return .moveGroup(dragGroup, to: dropTarget)
        }
```

`dragPage(by:)` 的 guard 改为 `guard dragSession == nil, !isModifiedClick else {`。

`setQuery` 的 `else` 分支在 `isJiggling = false` 后加 `clearMultiSelection()`。

`activateSelection()` 开头加：

```swift
        if clearMultiSelection() {
            return nil
        }
```

`prepareForPresentation()` 在 `isJiggling = false` 后加 `clearMultiSelection()`。

`handleEscape()` 在关闭文件夹分支之后、`if isJiggling` 之前加：

```swift
        if clearMultiSelection() {
            return .clearedSelection
        }
```

`normalizeState()` 开头加：

```swift
        if let layoutPages {
            var selection = multiSelection
            selection.retain(Set(layoutPages.joined().compactMap(\.layoutID)))
            setMultiSelection(selection)
        }
```

`LauncherView.swift:376` 改为：

```swift
                    from: model.landing?.entryIDs.contains(entry.id) == true ? model.landing?.from : nil,
```

- [ ] **Step 4: 确认通过**

Run: `swift test 2>&1 | grep -E "error: -|Executed .* tests"`
Expected: 全部 `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/LauncherModel.swift Sources/LaunchApp/LauncherView.swift Tests/LaunchAppTests/LauncherModelSelectionTests.swift Tests/LaunchAppTests/LauncherModelDragTests.swift
git commit -m "feat(编辑): 模型支持多选、选框与批量命令"
```

---

### Task 7: 点空白与带修饰键的点击

**Files:**
- Modify: `Sources/LaunchApp/LauncherController.swift`
- Test: `Tests/LaunchAppTests/LauncherControllerTests.swift`

- [ ] **Step 1: 失败测试**（追加到 `LauncherControllerTests`，放在 `makeController` 之前）

```swift
    @MainActor
    func testBackgroundClickClearsSelectionBeforeJigglingAndClosing() {
        let apps = makeApps(count: 3)
        let (controller, presenter) = makeController(apps: apps)
        controller.show()
        controller.model.updateLayout([apps.map(ResolvedItem.app)])
        controller.model.canEditLayout = true
        controller.model.beginJiggling()
        controller.model.toggleMultiSelection(.app(apps[1].identity.stableKey))

        controller.handleBackgroundClick()
        XCTAssertTrue(controller.model.multiSelection.isEmpty)
        XCTAssertTrue(controller.model.isJiggling)

        controller.handleBackgroundClick()
        XCTAssertFalse(controller.model.isJiggling)
        XCTAssertTrue(presenter.isVisible)

        controller.handleBackgroundClick()
        XCTAssertFalse(presenter.isVisible)
    }

    @MainActor
    func testModifiedBackgroundClickIsIgnored() {
        let (controller, presenter) = makeController()
        controller.show()
        controller.model.isModifiedClick = true

        controller.handleBackgroundClick()

        XCTAssertTrue(presenter.isVisible)
    }

    @MainActor
    func testReturnOnlyClearsSelection() {
        let apps = makeApps(count: 3)
        var opened: [URL] = []
        let (controller, _) = makeController(apps: apps) { url in
            opened.append(url)
            return true
        }
        controller.show()
        controller.model.updateLayout([apps.map(ResolvedItem.app)])
        controller.model.canEditLayout = true
        controller.handle(.move(.right))
        controller.model.toggleMultiSelection(.app(apps[2].identity.stableKey))

        controller.handle(.activate)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(controller.model.multiSelection.isEmpty)

        controller.handle(.activate)
        XCTAssertEqual(opened.count, 1)
    }
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter LauncherControllerTests 2>&1 | grep -E "error:|failed|Executed"`
Expected: `testBackgroundClickClearsSelectionBeforeJigglingAndClosing` 与 `testModifiedBackgroundClickIsIgnored` 失败（`testReturnOnlyClearsSelection` 已由 Task 6 的模型改动满足）。

- [ ] **Step 3: 实现**

```swift
    func handleBackgroundClick() {
        guard !model.isModifiedClick else {
            return
        }
        if model.openFolderID != nil {
            model.closeFolder()
        } else if !model.multiSelection.isEmpty {
            model.clearMultiSelection()
        } else if model.isJiggling {
            model.endJiggling()
        } else {
            hide(.backgroundClick)
        }
    }
```

- [ ] **Step 4: 确认通过**

Run: `swift test --filter LauncherControllerTests 2>&1 | grep -E "error:|Executed"`
Expected: `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/LauncherController.swift Tests/LaunchAppTests/LauncherControllerTests.swift
git commit -m "feat(编辑): 点空白先清空多选，忽略带修饰键的点击"
```

---

### Task 8: 鼠标接入与拖拽数量角标

**Files:**
- Modify: `Sources/LaunchApp/ItemDragController.swift`、`Sources/LaunchApp/LaunchApp.swift`、`Sources/LaunchApp/LauncherView.swift`（`DragCard`、`DragCardRenderer`）

AppKit 事件接入没有单元测试，靠 Task 10 的 e2e 验证。Task 1 若改为异步弹出菜单，这里同样处理。

- [ ] **Step 1: `ItemDragController`**

属性与初始化：

```swift
    private let makeDragImage: (ResolvedItem, Int) -> NSImage?
    private lazy var selectionMenu = SelectionMenu { [weak self] command in
        self?.model.performSelectionCommand(command)
    }
    private var monitors: [Any] = []
    private var press: LauncherModel.ItemPress?
    private var badgePress: CatalogApp?
    private var marqueePoint: CGPoint?
    private var isMarqueeing = false
```

`init` 的参数改为 `makeDragImage: @escaping (ResolvedItem, Int) -> NSImage?`。

`start()`：

```swift
        let rightDown = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.rightMouseDown(event) ?? event
        }
        monitors = [down, drag, up, rightDown].compactMap { $0 }
```

`mouseDown`：

```swift
    private func mouseDown(_ event: NSEvent) -> NSEvent? {
        press = nil
        badgePress = nil
        marqueePoint = nil
        cancelLongPress()
        guard let point = globalPoint(of: event) else {
            return event
        }
        let flags = event.modifierFlags
        model.isModifiedClick = flags.contains(.command) || flags.contains(.control)
        if flags.contains(.control) {
            return contextClick(at: point, event: event)
        }
        if flags.contains(.command), model.beginMarquee(at: point) {
            marqueePoint = point
            isMarqueeing = false
            return nil
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
```

`mouseDragged` 开头：

```swift
        if let start = marqueePoint {
            if let point = globalPoint(of: event),
               isMarqueeing || hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold {
                isMarqueeing = true
                model.updateMarquee(to: point)
            }
            return nil
        }
```

`mouseUp`：开头加

```swift
        if marqueePoint != nil {
            marqueePoint = nil
            model.endMarquee()
            return nil
        }
```

末尾的启动改为：

```swift
        if !didLongPress, !model.clearMultiSelection() {
            onActivate(press.item)
        }
        return nil
```

新增：

```swift
    private func rightMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let point = globalPoint(of: event) else {
            return event
        }
        return contextClick(at: point, event: event)
    }

    // 本期只有选中项有菜单；落在其他图标上也吞掉，免得 ⌃ 单击启动应用
    private func contextClick(at point: CGPoint, event: NSEvent) -> NSEvent? {
        if let content = model.selectionMenu(at: point), let view = presenter.contentView {
            let location = view.convert(event.locationInWindow, from: nil)
            selectionMenu.makeMenu(content).popUp(positioning: nil, at: location, in: view)
            return nil
        }
        return model.itemPress(at: point) == nil ? event : nil
    }
```

`beginSession` 中的图像：

```swift
        draggingItem.setDraggingFrame(
            view.convert(windowFrame, from: nil),
            contents: makeDragImage(press.item, model.dragCount(for: press))
        )
```

- [ ] **Step 2: `LaunchApp.swift`**

```swift
        makeDragImage: { [weak self] item, count in self?.dragImage(for: item, count: count) }
```

```swift
    private func dragImage(for item: ResolvedItem, count: Int) -> NSImage? {
        guard let layout = controller.model.homeLayout else {
            return nil
        }
        return DragCardRenderer.image(for: item, count: count, layout: layout, scale: presenter.backingScaleFactor)
    }
```

- [ ] **Step 3: `DragCard` 数量角标**（`LauncherView.swift`）

```swift
enum DragCardRenderer {
    static func image(for item: ResolvedItem, count: Int, layout: LauncherHomeLayout, scale: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: DragCard(item: item, count: count, layout: layout))
        renderer.scale = scale
        return renderer.nsImage
    }
}

private struct DragCard: View {
    let item: ResolvedItem
    let count: Int
    let layout: LauncherHomeLayout
```

`DragCard.body` 末尾 `.frame(width: layout.tileWidth)` 之后加：

```swift
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: layout.labelFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, layout.uninstallBadgeSide * 0.25)
                    .frame(minWidth: layout.uninstallBadgeSide, minHeight: layout.uninstallBadgeSide)
                    .background(Capsule().fill(.red))
            }
        }
```

- [ ] **Step 4: 构建与测试**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete"` 与 `swift test 2>&1 | grep -E "error: -|Executed .* tests"`
Expected: `Build complete`，无警告；全部 `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/ItemDragController.swift Sources/LaunchApp/LaunchApp.swift Sources/LaunchApp/LauncherView.swift
git commit -m "feat(编辑): ⌘ 点选、框选、整体拖动与右键菜单接入"
```

---

### Task 9: 选中标记与选框

**Files:**
- Modify: `Sources/LaunchApp/LauncherView.swift`

- [ ] **Step 1: `GridCell` 选中底板与对勾**

`case .item(let item, let index):` 中 `itemView(item, index)` 之后、合并底板 `.background(alignment: .top)` 之前加：

```swift
                .background {
                    if entry.isPicked {
                        RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous)
                            .fill(.white.opacity(0.32))
                    }
                }
```

合并底板之后、`LandingModifier` 之前加：

```swift
                .overlay(alignment: .topTrailing) {
                    if entry.isPicked {
                        SelectionCheck(layout: layout)
                    }
                }
```

`UninstallBadge` 之后新增：

```swift
private struct SelectionCheck: View {
    let layout: LauncherHomeLayout

    var body: some View {
        let side = layout.uninstallBadgeSide
        Image(systemName: "checkmark")
            .font(.system(size: side * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(Circle().fill(.blue))
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .offset(x: -((layout.tileWidth - layout.iconSide) / 2 - side * 0.2), y: layout.tilePadding - side * 0.2)
            .allowsHitTesting(false)
            .accessibilityLabel("已选中")
    }
}

// 只有这一层读取选框矩形，拖动选框时不重建网格
private struct MarqueeOverlay: View {
    let model: LauncherModel

    var body: some View {
        GeometryReader { proxy in
            if let rect = model.marqueeRect {
                let origin = proxy.frame(in: .global).origin
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(.white.opacity(0.6), lineWidth: 1)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX - origin.x, y: rect.midY - origin.y)
            }
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: 放入选框层**

`LauncherView.body` 外层 `ZStack` 中，内层 `ZStack { ... }` 的修饰链（`.onGeometryChange { ... model.updatePageWidth(width) }`）之后加：

```swift
                MarqueeOverlay(model: model)
                    .ignoresSafeArea()
```

- [ ] **Step 3: 构建、测试、安装**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete"`、`swift test 2>&1 | grep -E "error: -|Executed .* tests"`，再执行安装命令。
Expected: `Build complete`，全部 `0 failures`，安装成功。

- [ ] **Step 4: 提交**

```bash
git add Sources/LaunchApp/LauncherView.swift
git commit -m "feat(界面): 多选的选中标记与选框"
```

---

### Task 10: 目标机验证与文档

- [ ] **Step 1: 备份布局**

```bash
L="$HOME/Library/Application Support/Launch"; B=$(mktemp -d); echo "$B" > /tmp/launch-layout-backup-dir
cp "$L/layout.json" "$B/"; [ -f "$L/layout.json.backup" ] && cp "$L/layout.json.backup" "$B/"
shasum -a 256 "$L"/layout.json* | tee "$B/sha.txt"
```

- [ ] **Step 2: e2e**

`$E/m/main.swift`（`E=$(cat /tmp/launch-e2e-4b-dir)`，复用 Task 1 的 `prelude.swift`）：

```swift
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IONBF, 0)
dismissDialogs()
let originalMouse = CGEvent(source: nil)?.location ?? .zero
let appsBefore = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
CGWarpMouseCursorPosition(CGPoint(x: 756, y: 491)); mouse(.mouseMoved, CGPoint(x: 756, y: 491)); wait(0.3)
openLauncher()
selectPage("第 1 页")
let original = tiles()
let base = original.map(\.name)
guard original.count >= 12 else { print("FAIL 第 1 页图标不足"); exit(1) }
let f = original.map(\.frame)
let blank = CGPoint(x: f[0].minX - 20, y: f[0].midY)
let marqueeStart = CGPoint(x: f[0].minX - 4, y: f[0].minY + 2)
let cmd = CGEventFlags.maskCommand
func undo() { key(6, flags: cmd); wait(1.0) }

// M1 ⌘ 单击切换选中，Esc 先清空选择
click(iconCenter(f[2]), flags: cmd); click(iconCenter(f[4]), flags: cmd)
check(pickedCount() == 2, "M1 ⌘ 单击选中 2 项（\(pickedCount())）")
click(iconCenter(f[4]), flags: cmd)
check(pickedCount() == 1, "M1 再次 ⌘ 单击取消选中")
key(53); wait(0.5)
check(pickedCount() == 0 && panelVisible(), "M1 Esc 只清空选择")

// M2 选框，点空白只清空
drag(from: marqueeStart, to: iconCenter(f[8]), flags: cmd, hold: 0.2)
check(pickedCount() == 4, "M2 选框选中 4 项（\(pickedCount())）")
click(blank)
check(pickedCount() == 0 && panelVisible(), "M2 点空白只清空选择")

// M3 ⌘ 长距离横向拖动不翻页
drag(from: marqueeStart, to: CGPoint(x: f[0].minX + 900, y: f[0].minY + 30), flags: cmd, hold: 0.2)
check(tiles().first?.frame == f[0] && names() == base, "M3 ⌘ 拖动不翻页")
key(53); wait(0.5)

// M4 普通单击已选中图标只清空不启动
click(iconCenter(f[3]), flags: cmd)
click(iconCenter(f[3]))
check(pickedCount() == 0 && panelVisible(), "M4 普通单击只清空选择")

// M5 菜单：合并到新文件夹
click(iconCenter(f[2]), flags: cmd); click(iconCenter(f[4]), flags: cmd)
rightClick(iconCenter(f[2])); wait(0.8)
check(menuItem("已选中 2 个项目") != nil, "M5 右键弹出多选菜单")
if let merge = menuItem("合并到新文件夹") { AXUIElementPerformAction(merge, kAXPressAction as CFString) }
wait(1.0)
var folded = base; folded.remove(at: 4); folded[2] = "未命名"
check(Array(names().prefix(10)) == Array(folded.prefix(10)), "M5 合并到新文件夹")
undo()
check(names() == base, "M5 ⌘Z 撤销")

// M6 菜单：移动到新页面
let dotCount = pageDots().count
click(iconCenter(f[0]), flags: cmd); click(iconCenter(f[1]), flags: cmd)
rightClick(iconCenter(f[0])); wait(0.8)
if let move = menuItem("移动到").flatMap(frame) { mouse(.mouseMoved, CGPoint(x: move.midX, y: move.midY)); wait(0.8) }
if let newPage = menuItem("新页面") { AXUIElementPerformAction(newPage, kAXPressAction as CFString) }
wait(1.0)
check(pageDots().count == dotCount + 1, "M6 新增一页")
check(Array(names().prefix(10)) == Array(base.dropFirst(2).prefix(10)), "M6 选中项移出第 1 页")
if let last = pageDots().last { AXUIElementPerformAction(last, kAXPressAction as CFString); wait(0.9) }
check(names() == Array(base.prefix(2)), "M6 新页面只有选中项")
undo()
selectPage("第 1 页")
check(names() == base && pageDots().count == dotCount, "M6 ⌘Z 撤销")

// M7 整体拖动插入
click(iconCenter(f[0]), flags: cmd); click(iconCenter(f[1]), flags: cmd)
drag(from: iconCenter(f[0]), to: leadingPoint(f[5]), hold: 0.6)
var inserted = Array(base.dropFirst(2)); inserted.insert(contentsOf: base.prefix(2), at: 5)
check(Array(names().prefix(12)) == Array(inserted.prefix(12)), "M7 两项一起插到第 6 格前")
check(pickedCount() == 0, "M7 放下后清空选择")
undo()
check(names() == base, "M7 ⌘Z 撤销")

// M8 整体拖到应用上合并
click(iconCenter(f[0]), flags: cmd); click(iconCenter(f[1]), flags: cmd)
drag(from: iconCenter(f[0]), to: iconCenter(f[1]), hold: 0.5, steps: 4)
var merged = Array(base.dropFirst(2)); merged[1] = "未命名"
check(Array(names().prefix(10)) == Array(merged.prefix(10)), "M8 两项与目标合并为文件夹")
undo()
check(names() == base, "M8 ⌘Z 撤销")

let appsAfter = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
check(appsAfter.subtracting(appsBefore).subtracting([launchID]).isEmpty, "全程未启动应用")
key(53); wait(0.5)
CGWarpMouseCursorPosition(originalMouse)
print("FAILURES \(failures)")
```

Run: `E=$(cat /tmp/launch-e2e-4b-dir); mkdir -p "$E/m"`（写入上面的脚本后）`swiftc -O "$E/prelude.swift" "$E/m/main.swift" -o "$E/m/run" && "$E/m/run"`
Expected: 全部 `PASS`。

- [ ] **Step 3: 还原布局**

```bash
L="$HOME/Library/Application Support/Launch"; B=$(cat /tmp/launch-layout-backup-dir)
cp "$B/layout.json" "$L/layout.json"; [ -f "$B/layout.json.backup" ] && cp "$B/layout.json.backup" "$L/layout.json.backup"
shasum -a 256 "$L"/layout.json* | diff - "$B/sha.txt" && echo "布局已还原"
pkill -x LaunchApp; sleep 1; open "$HOME/Applications/Launch.app"
```

- [ ] **Step 4: 文档**

- `README.md`：把「多选、右键菜单、隐藏应用（4b/4c）……仍未实现」改为先写 4b 已完成（⌘ 点选或框选多个图标，一起拖动，或右键合并到新文件夹、合并到选中的文件夹、移动到指定页），再写「单项右键菜单、隐藏应用（4c）和 F4/手势等系统入口仍未实现」。
- `docs/architecture.md` 第 7 节第 4 条：4b 标为已完成并引用 `docs/superpowers/specs/2026-10-20-multi-select-design.md`；第 9 节待验证中的「编辑中的多选、隐藏与右键菜单细节（4b/4c）」改为「隐藏与单项右键菜单细节（4c）」。
- `docs/manual-verification.md`：当前结果追加 Task 1 探针与本次 e2e 结果、布局还原哈希；待验证追加「选中标记与选框观感、拖动数量角标、多项落位动画」。

```bash
git add README.md docs/architecture.md docs/manual-verification.md
git commit -m "chore(文档): 记录第 4b 期多选的验证结果"
```

---

## Self-Review

- Spec 覆盖：3.1 选择 → Task 3/6/7/8/9；3.2 一起拖动 → Task 4/6/8；3.3 多选菜单 → Task 5/6/8；4 组件 → 各任务；5 `LayoutEditor` 规则 → Task 2；6 测试与验证 → Task 1–7 单测、Task 1 最小验证、Task 10 e2e。
- 类型一致：`LayoutEdit.moveGroup/mergeIntoNewFolder`、`MultiSelection.items/count/toggle/beginMarquee/updateMarquee/endMarquee/retain/ordered(in:)`、`GridHitTester.tileIndices(intersecting:itemCount:)`、`DragSession(item:origin:group:)`、`DragPreview.group/isGroup/count/sourceIndices(onPage:in:)`、`SelectionMenuContent(count:folders:pageCount:)`、`SelectionCommand`、`LauncherModel.multiSelection/marqueeRect/isModifiedClick/canMultiSelect/toggleMultiSelection/clearMultiSelection/beginMarquee/updateMarquee/endMarquee/dragCount(for:)/selectionMenu(at:)/performSelectionCommand`、`Landing.entryIDs`、`GridEntry.isPicked`、`EscapeOutcome.clearedSelection`、`DragCardRenderer.image(for:count:layout:scale:)` 各处一致。
