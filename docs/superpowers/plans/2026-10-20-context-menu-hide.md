# 第 4c 期：右键菜单与隐藏应用 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 右键单个应用或文件夹弹出菜单（打开、在访达中显示、显示简介、隐藏、移到废纸篓；文件夹为打开、重命名、取消分组、隐藏），隐藏的应用可在菜单栏取消隐藏。

**Architecture:** `LayoutDocument` 增加 `hiddenApps`，`LayoutEngine`/`LayoutEditor` 把隐藏应用按未安装处理，并新增 `hide`/`unhide`/`ungroupFolder` 编辑；`LayoutCoordinator` 发布隐藏列表并提供取消隐藏；`SelectionMenu` 扩展为 `ItemMenu`，按多选、应用、文件夹生成菜单；`LauncherModel` 给出菜单内容并处理布局类命令，系统类命令交给 `AppActions`；菜单栏增加「隐藏的应用」子菜单。

**Tech Stack:** Swift 6，AppKit（`NSMenu`、`NSWorkspace`、`NSAppleScript`、`NSAlert`），SwiftUI，XCTest。

**Spec:** `docs/superpowers/specs/2026-10-20-context-menu-hide-design.md`

---

## 文件结构

| 文件 | 动作 | 职责 |
| --- | --- | --- |
| `Sources/LaunchCore/Models.swift` | 修改 | `LayoutDocument.hiddenApps`，兼容旧文件 |
| `Sources/LaunchCore/LayoutEngine.swift` | 修改 | 隐藏应用不显示、不追加；`ReconciledLayout.hiddenApps`；`CatalogResolver.keys(of:)` |
| `Sources/LaunchCore/LayoutEditor.swift` | 修改 | 隐藏应用按未安装处理；`hide`/`unhide`/`ungroupFolder` |
| `Tests/LaunchCoreTests/LayoutStoreTests.swift`、`LayoutEngineTests.swift`、`LayoutEditorTests.swift` | 修改 | 对应测试 |
| `Sources/LaunchApp/LayoutCoordinator.swift` | 修改 | `hiddenApps`、`unhide`、`unhideAll`、重新导入保留隐藏 |
| `Tests/LaunchAppTests/LayoutCoordinatorTests.swift` | 修改 | 对应测试 |
| `Sources/LaunchApp/ItemMenu.swift` | 由 `SelectionMenu.swift` 改名 | 三种菜单内容与命令 |
| `Tests/LaunchAppTests/ItemMenuTests.swift` | 由 `SelectionMenuTests.swift` 改名 | 对应测试 |
| `Sources/LaunchApp/LauncherModel.swift` | 修改 | `hiddenApps`、`contextMenu(at:)`、`performMenuCommand` |
| `Tests/LaunchAppTests/LauncherModelMenuTests.swift` | 新建 | 对应测试 |
| `Tests/LaunchAppTests/LauncherModelSelectionTests.swift` | 修改 | 命令改名 |
| `Sources/LaunchApp/AppActions.swift` | 新建 | 在访达中显示、显示简介 |
| `Tests/LaunchAppTests/AppActionsTests.swift` | 新建 | 脚本转义 |
| `Sources/LaunchApp/UninstallCoordinator.swift` | 修改 | 弹窗调高层级的方法改为 `NSAlert` 扩展，供 `AppActions` 复用 |
| `Resources/Info.plist` | 修改 | `NSAppleEventsUsageDescription`（构建脚本直接拷贝此文件） |
| `Sources/LaunchApp/ItemDragController.swift` | 修改 | 菜单内容来自 `contextMenu(at:)`，命令交给外部 |
| `Sources/LaunchApp/StatusItemController.swift` | 修改 | 「隐藏的应用」子菜单 |
| `Sources/LaunchApp/LaunchApp.swift` | 修改 | 组装 |

命令（项目根目录）：`swift build 2>&1 | grep -E "error:|warning:|Build complete"`；`swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | tail -3`；`swift test --filter <类名>`；安装 `LAUNCH_SIGN_IDENTITY="Apple Development: zhaoyingkun@163.com" ./scripts/build-app.sh --install`。

---

### Task 1: 布局文档增加隐藏列表

**Files:**
- Modify: `Sources/LaunchCore/Models.swift`、`Sources/LaunchCore/LayoutEngine.swift`、`Sources/LaunchCore/LayoutEditor.swift`
- Test: `Tests/LaunchCoreTests/LayoutStoreTests.swift`、`LayoutEngineTests.swift`、`LayoutEditorTests.swift`

- [ ] **Step 1: 失败测试**

`LayoutStoreTests` 类末尾（`temporaryStore()` 之前）：

```swift
    func testLoadsLayoutWithoutHiddenApps() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"schemaVersion":1,"pages":[{"slots":[{"empty":{}}]}]}"#.utf8).write(to: store.fileURL)

        XCTAssertEqual(try store.load(), LayoutDocument(pages: [LayoutPage(slots: [.empty])]))
    }

    func testSaveKeepsHiddenApps() throws {
        let store = try temporaryStore()
        let document = LayoutDocument(
            pages: [LayoutPage(slots: [.empty])],
            hiddenApps: [AppIdentity(bundleIdentifier: "com.example.a", path: "/Applications/A.app")]
        )

        try store.save(document)

        XCTAssertEqual(try store.load(), document)
    }
```

`LayoutEngineTests` 类末尾：

```swift
    func testAppendingKeepsHiddenApps() {
        let document = LayoutDocument(pages: [], hiddenApps: [zoom.identity])

        let result = LayoutEngine.appending([mail.identity], to: document, pageCapacity: 35)

        XCTAssertEqual(result.hiddenApps, [zoom.identity])
    }
```

`LayoutEditorTests` 类末尾：

```swift
    func testEditKeepsHiddenApps() {
        let document = LayoutDocument(pages: [LayoutPage(slots: [slot(a), slot(b)])], hiddenApps: [gone])

        let result = LayoutEditor.apply(
            .move(id(b), to: .insert(page: 0, before: id(a))),
            to: document,
            catalog: catalog,
            pageCapacity: 35
        )

        XCTAssertEqual(result.hiddenApps, [gone])
    }
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter "LayoutStoreTests|LayoutEngineTests|LayoutEditorTests" 2>&1 | grep -E "error:" | head -3`
Expected: 编译错误，`LayoutDocument` 没有 `hiddenApps`。

- [ ] **Step 3: 实现**

`Models.swift` 中 `LayoutDocument` 改为：

```swift
public struct LayoutDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let schemaVersion: Int
    public let pages: [LayoutPage]
    public let hiddenApps: [AppIdentity]

    public init(
        schemaVersion: Int = LayoutDocument.currentVersion,
        pages: [LayoutPage] = [],
        hiddenApps: [AppIdentity] = []
    ) {
        self.schemaVersion = schemaVersion
        self.pages = pages
        self.hiddenApps = hiddenApps
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case pages
        case hiddenApps
    }

    // 早期文件没有 hiddenApps
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        pages = try container.decode([LayoutPage].self, forKey: .pages)
        hiddenApps = try container.decodeIfPresent([AppIdentity].self, forKey: .hiddenApps) ?? []
    }
}
```

`LayoutEngine.appending` 末尾：

```swift
        return LayoutDocument(
            schemaVersion: document.schemaVersion,
            pages: pages.map { LayoutPage(slots: $0) },
            hiddenApps: document.hiddenApps
        )
```

`LayoutEditor.apply` 末尾：

```swift
        return LayoutDocument(
            schemaVersion: document.schemaVersion,
            pages: editor.pages.map { LayoutPage(slots: $0) },
            hiddenApps: document.hiddenApps
        )
```

- [ ] **Step 4: 确认通过**

Run: `swift test --filter "LayoutStoreTests|LayoutEngineTests|LayoutEditorTests" 2>&1 | grep -E "error:|failed \(|Executed" | tail -2`
Expected: `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchCore/Models.swift Sources/LaunchCore/LayoutEngine.swift Sources/LaunchCore/LayoutEditor.swift Tests/LaunchCoreTests/LayoutStoreTests.swift Tests/LaunchCoreTests/LayoutEngineTests.swift Tests/LaunchCoreTests/LayoutEditorTests.swift
git commit -m "feat(布局): 布局文件记录隐藏的应用"
```

---

### Task 2: 解析时跳过隐藏应用

**Files:**
- Modify: `Sources/LaunchCore/LayoutEngine.swift`
- Test: `Tests/LaunchCoreTests/LayoutEngineTests.swift`

- [ ] **Step 1: 失败测试**（`LayoutEngineTests` 类末尾）

```swift
    func testHiddenAppsStayPlacedButInvisible() {
        let folder = LayoutFolder(id: "f", name: "效率", apps: [notes.identity, zoom.identity])
        let document = LayoutDocument(
            pages: [LayoutPage(slots: [.app(mail.identity), .folder(folder)])],
            hiddenApps: [zoom.identity, mail.identity]
        )

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes, zoom], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.folder(ResolvedFolder(id: "f", name: "效率", apps: [notes]))]])
        XCTAssertEqual(result.appendedApps, [])
        XCTAssertEqual(result.hiddenApps, [mail, zoom])
    }

    func testFolderWithOnlyHiddenMembersDisappears() {
        let folder = LayoutFolder(id: "f", name: "效率", apps: [notes.identity])
        let document = LayoutDocument(
            pages: [LayoutPage(slots: [.app(mail.identity), .folder(folder)])],
            hiddenApps: [notes.identity]
        )

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.app(mail)]])
    }

    func testHiddenAppMatchesMovedInstall() {
        let saved = AppIdentity(bundleIdentifier: mail.identity.bundleIdentifier, path: "/Old/Mail.app")
        let document = LayoutDocument(
            pages: [LayoutPage(slots: [.app(mail.identity), .app(notes.identity)])],
            hiddenApps: [saved]
        )

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.app(notes)]])
        XCTAssertEqual(result.hiddenApps, [mail])
    }
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter LayoutEngineTests 2>&1 | grep -E "error:" | head -3`
Expected: 编译错误，`ReconciledLayout` 没有 `hiddenApps`。

- [ ] **Step 3: 实现**

`ReconciledLayout` 增加字段：

```swift
public struct ReconciledLayout: Equatable, Sendable {
    public let pages: [[ResolvedItem]]
    public let document: LayoutDocument
    public let appendedApps: [CatalogApp]
    public let hiddenApps: [CatalogApp]
}
```

`CatalogResolver` 增加：

```swift
    func keys(of identities: [AppIdentity]) -> Set<String> {
        Set(identities.compactMap { app(for: $0)?.identity.stableKey })
    }
```

`reconcile`：

```swift
    public static func reconcile(
        layout: LayoutDocument,
        catalog: [CatalogApp],
        pageCapacity: Int
    ) -> ReconciledLayout {
        let resolver = CatalogResolver(catalog: catalog)
        let hidden = resolver.keys(of: layout.hiddenApps)
        let hiddenApps = catalog
            .filter { hidden.contains($0.identity.stableKey) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        let initial = resolve(layout, with: resolver, hidden: hidden)
        let unplaced = catalog.filter { !initial.placedKeys.contains($0.identity.stableKey) }
        guard !unplaced.isEmpty else {
            return ReconciledLayout(pages: initial.pages, document: layout, appendedApps: [], hiddenApps: hiddenApps)
        }
        let document = appending(unplaced.map(\.identity), to: layout, pageCapacity: pageCapacity)
        return ReconciledLayout(
            pages: resolve(document, with: resolver, hidden: hidden).pages,
            document: document,
            appendedApps: unplaced,
            hiddenApps: hiddenApps
        )
    }
```

`resolve` 增加 `hidden` 参数，隐藏应用计为已放置但不显示：

```swift
    private static func resolve(
        _ document: LayoutDocument,
        with resolver: CatalogResolver,
        hidden: Set<String>
    ) -> (pages: [[ResolvedItem]], placedKeys: Set<String>) {
        var placedKeys = Set<String>()
        let pages: [[ResolvedItem]] = document.pages.compactMap { page in
            let items: [ResolvedItem] = page.slots.compactMap { slot in
                switch slot {
                case .empty:
                    return .empty
                case .app(let identity):
                    guard let app = resolver.app(for: identity) else {
                        return nil
                    }
                    placedKeys.insert(app.identity.stableKey)
                    return hidden.contains(app.identity.stableKey) ? nil : .app(app)
                case .folder(let folder):
                    let apps = folder.apps.compactMap { resolver.app(for: $0) }
                    placedKeys.formUnion(apps.map(\.identity.stableKey))
                    let visible = apps.filter { !hidden.contains($0.identity.stableKey) }
                    guard !visible.isEmpty else {
                        return nil
                    }
                    return .folder(ResolvedFolder(id: folder.id, name: folder.name, apps: visible))
                }
            }
            return items.contains { $0 != .empty } ? items : nil
        }
        return (pages, placedKeys)
    }
```

- [ ] **Step 4: 确认通过**

Run: `swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | tail -3`
Expected: 全部 `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchCore/LayoutEngine.swift Tests/LaunchCoreTests/LayoutEngineTests.swift
git commit -m "feat(布局): 隐藏的应用不显示也不追加到末尾"
```

---

### Task 3: 隐藏、取消隐藏与取消分组编辑

**Files:**
- Modify: `Sources/LaunchCore/LayoutEditor.swift`
- Test: `Tests/LaunchCoreTests/LayoutEditorTests.swift`

- [ ] **Step 1: 失败测试**（`LayoutEditorTests` 类末尾）

```swift
    private func applyDocument(
        _ edit: LayoutEdit,
        _ pages: [[LayoutSlot]],
        hidden: [AppIdentity] = [],
        capacity: Int = 35
    ) -> LayoutDocument {
        LayoutEditor.apply(
            edit,
            to: LayoutDocument(pages: pages.map { LayoutPage(slots: $0) }, hiddenApps: hidden),
            catalog: catalog,
            pageCapacity: capacity,
            makeFolderID: { "new" }
        )
    }

    func testHideAppAndFolderMembersKeepsPositions() {
        let pages = [[slot(a), folder("f", [b, c]), slot(d)]]

        let result = applyDocument(.hide([id(a), .folder("f")]), pages)

        XCTAssertEqual(result.pages.map(\.slots), pages)
        XCTAssertEqual(result.hiddenApps, [a.identity, b.identity, c.identity])
    }

    func testHideFolderMemberByKey() {
        let result = applyDocument(.hide([id(b)]), [[folder("f", [b, c])]])

        XCTAssertEqual(result.hiddenApps, [b.identity])
    }

    func testHidingHiddenAppChangesNothing() {
        let document = LayoutDocument(pages: [LayoutPage(slots: [slot(a), slot(b)])], hiddenApps: [a.identity])

        XCTAssertEqual(
            LayoutEditor.apply(.hide([id(a)]), to: document, catalog: catalog, pageCapacity: 35),
            document
        )
    }

    func testHiddenAppsTakeNoCapacityAndCannotAnchor() {
        let result = applyDocument(
            .move(id(d), to: .insert(page: 0, before: id(b))),
            [[slot(a), slot(b), slot(c)], [slot(d)]],
            hidden: [b.identity],
            capacity: 3
        )

        XCTAssertEqual(result.pages.map(\.slots), [[slot(a), slot(b), slot(c), slot(d)]])
    }

    func testUnhideRestoresOriginalPosition() {
        let pages = [[slot(a), slot(b), slot(c)]]

        let result = applyDocument(.unhide([b.identity]), pages, hidden: [b.identity, c.identity])

        XCTAssertEqual(result.pages.map(\.slots), pages)
        XCTAssertEqual(result.hiddenApps, [c.identity])
    }

    func testUnhideMatchesMovedInstall() {
        let moved = AppIdentity(bundleIdentifier: b.identity.bundleIdentifier, path: "/Old/B.app")

        let result = applyDocument(.unhide([b.identity]), [[slot(a), slot(b)]], hidden: [moved])

        XCTAssertEqual(result.hiddenApps, [])
    }

    func testUngroupAppendsMembersToPageEndAndCascades() {
        let result = applyDocument(
            .ungroupFolder("f"),
            [[folder("f", [b, c]), slot(a), .app(gone)], [slot(d)]],
            capacity: 2
        )

        XCTAssertEqual(result.pages.map(\.slots), [[slot(a), .app(gone), slot(b)], [slot(c), slot(d)]])
    }
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter LayoutEditorTests 2>&1 | grep -E "error:" | head -3`
Expected: 编译错误，`LayoutEdit` 没有 `hide`。

- [ ] **Step 3: 实现**

`LayoutEdit` 增加：

```swift
    case hide([LayoutItemID])
    case unhide([AppIdentity])
    case ungroupFolder(String)
```

`LayoutEditor.apply` 改为同时比较隐藏列表，并写回编辑后的隐藏列表：

```swift
        var editor = Editor(document: document, catalog: catalog, capacity: pageCapacity, newFolderID: makeFolderID())
        let base = editor.pages
        let baseHidden = editor.hidden
        guard editor.perform(edit), editor.pages != base || editor.hidden != baseHidden else {
            return document
        }
        return LayoutDocument(
            schemaVersion: document.schemaVersion,
            pages: editor.pages.map { LayoutPage(slots: $0) },
            hiddenApps: editor.hidden
        )
```

`Editor` 头部改为：

```swift
private struct Editor {
    var pages: [[LayoutSlot]]
    var hidden: [AppIdentity] {
        didSet {
            hiddenKeys = resolver.keys(of: hidden)
        }
    }
    let resolver: CatalogResolver
    let capacity: Int
    let newFolderID: String
    var hiddenKeys: Set<String>
    let appsByKey: [String: CatalogApp]

    init(document: LayoutDocument, catalog: [CatalogApp], capacity: Int, newFolderID: String) {
        let resolver = CatalogResolver(catalog: catalog)
        let hiddenKeys = resolver.keys(of: document.hiddenApps)
        self.resolver = resolver
        self.capacity = capacity
        self.newFolderID = newFolderID
        hidden = document.hiddenApps
        self.hiddenKeys = hiddenKeys
        appsByKey = Dictionary(catalog.map { ($0.identity.stableKey, $0) }, uniquingKeysWith: { first, _ in first })
        pages = document.pages
            .flatMap { Self.split($0.slots.filter { $0 != .empty }, resolver: resolver, hidden: hiddenKeys, capacity: capacity) }
            .filter { !$0.isEmpty }
    }

    // 可见项超过容量的旧页先拆开，使可见页与界面分页一一对应
    static func split(_ slots: [LayoutSlot], resolver: CatalogResolver, hidden: Set<String>, capacity: Int) -> [[LayoutSlot]] {
        var result: [[LayoutSlot]] = [[]]
        var visible = 0
        for slot in slots {
            if itemID(of: slot, resolver: resolver, hidden: hidden) != nil {
                if visible == capacity {
                    result.append([])
                    visible = 0
                }
                visible += 1
            }
            result[result.count - 1].append(slot)
        }
        return result
    }

    // 隐藏应用与未安装应用一样不可见
    static func itemID(of slot: LayoutSlot, resolver: CatalogResolver, hidden: Set<String>) -> LayoutItemID? {
        switch slot {
        case .app(let identity):
            guard let key = resolver.app(for: identity)?.identity.stableKey, !hidden.contains(key) else {
                return nil
            }
            return .app(key)
        case .folder(let folder):
            let isVisible = folder.apps.contains { identity in
                resolver.app(for: identity).map { !hidden.contains($0.identity.stableKey) } ?? false
            }
            return isVisible ? .folder(folder.id) : nil
        case .empty:
            return nil
        }
    }

    func itemID(of slot: LayoutSlot) -> LayoutItemID? {
        Self.itemID(of: slot, resolver: resolver, hidden: hiddenKeys)
    }
```

`perform(_:)` 增加：

```swift
        case .hide(let items):
            hide(items)
        case .unhide(let identities):
            unhide(identities)
        case .ungroupFolder(let folder):
            ungroup(folder: folder)
```

`Editor` 末尾增加：

```swift
    // 文件夹按全部成员（含未安装）隐藏；应用按身份查找，文件夹内的也能找到
    mutating func hide(_ items: [LayoutItemID]) -> Bool {
        var identities: [AppIdentity] = []
        for item in items {
            switch item {
            case .app(let key):
                if let app = appsByKey[key] {
                    identities.append(app.identity)
                }
            case .folder:
                if let location = locate(item), case .folder(let folder) = pages[location.page][location.slot] {
                    identities += folder.apps
                }
            }
        }
        var keys = hiddenKeys
        var next = hidden
        for identity in identities where !next.contains(identity) {
            if let key = key(of: identity) {
                guard keys.insert(key).inserted else {
                    continue
                }
            }
            next.append(identity)
        }
        hidden = next
        return true
    }

    mutating func unhide(_ identities: [AppIdentity]) -> Bool {
        let keys = resolver.keys(of: identities)
        hidden.removeAll { identity in
            identities.contains(identity) || key(of: identity).map(keys.contains) == true
        }
        return true
    }

    mutating func ungroup(folder folderID: String) -> Bool {
        guard let location = locate(.folder(folderID)),
              case .folder(let folder) = pages[location.page][location.slot] else {
            return false
        }
        pages[location.page].remove(at: location.slot)
        pages[location.page].append(contentsOf: folder.apps.map(LayoutSlot.app))
        cascade(from: location.page)
        pages = pages.filter { !$0.isEmpty }
        return true
    }
```

- [ ] **Step 4: 确认通过**

Run: `swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | tail -3`
Expected: 全部 `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchCore/LayoutEditor.swift Tests/LaunchCoreTests/LayoutEditorTests.swift
git commit -m "feat(布局): 隐藏、取消隐藏与取消分组的布局编辑"
```

---

### Task 4: LayoutCoordinator 发布隐藏列表

**Files:**
- Modify: `Sources/LaunchApp/LayoutCoordinator.swift`
- Test: `Tests/LaunchAppTests/LayoutCoordinatorTests.swift`

- [ ] **Step 1: 失败测试**（放在 `makeCoordinator` 之前）

```swift
    @MainActor
    func testHidingPublishesHiddenAppsAndUnhideRestores() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: apps.map { .app($0.identity) })]))
        let (coordinator, published) = makeCoordinator(store, FakePrompter(), FakeLaunchpad())
        coordinator.start()
        await coordinator.catalogDidChange(apps)

        coordinator.apply(.hide([.app(apps[1].identity.stableKey), .app(apps[2].identity.stableKey)]))
        XCTAssertEqual(published.last, [[.app(apps[0])]])
        XCTAssertEqual(coordinator.hiddenApps, [apps[1], apps[2]])
        XCTAssertEqual(try store.load()?.hiddenApps, [apps[1].identity, apps[2].identity])

        coordinator.unhide(apps[2])
        XCTAssertEqual(published.last, [[.app(apps[0]), .app(apps[2])]])

        coordinator.unhideAll()
        XCTAssertEqual(published.last, [apps.map(ResolvedItem.app)])
        XCTAssertEqual(coordinator.hiddenApps, [])

        coordinator.undo()
        XCTAssertEqual(coordinator.hiddenApps, [apps[1]])
    }

    @MainActor
    func testReimportKeepsHiddenApps() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(
            pages: [LayoutPage(slots: [.app(apps[2].identity)])],
            hiddenApps: [apps[1].identity]
        ))
        let snapshot = LaunchpadSnapshot(pages: [[.app(launchpadApp(apps[0]))]])
        let (coordinator, published) = makeCoordinator(store, FakePrompter(), FakeLaunchpad(snapshot: snapshot))
        coordinator.start()
        await coordinator.catalogDidChange(apps)

        await coordinator.importFromLaunchpad()

        XCTAssertEqual(published.last, [[.app(apps[0]), .app(apps[2])]])
        XCTAssertEqual(coordinator.hiddenApps, [apps[1]])
    }
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter LayoutCoordinatorTests 2>&1 | grep -E "error:" | head -3`
Expected: 编译错误，找不到 `hiddenApps`、`unhide`。

- [ ] **Step 3: 实现**

属性（`private var undoStack` 之后）：

```swift
    private(set) var hiddenApps: [CatalogApp] = []
```

`undo()` 之后：

```swift
    func unhide(_ app: CatalogApp) {
        apply(.unhide([app.identity]))
    }

    // 未安装的隐藏应用也一并取消
    func unhideAll() {
        apply(.unhide(document?.hiddenApps ?? []))
    }
```

`importFromLaunchpad` 中替换保存与赋值：

```swift
            let document = LayoutDocument(
                schemaVersion: result.document.schemaVersion,
                pages: result.document.pages,
                hiddenApps: self.document?.hiddenApps ?? []
            )
            try store.replace(with: document)
            self.document = document
```

`publish()`：

```swift
    private func publish() {
        guard let document else {
            let fallback = LayoutEngine.defaultDocument(catalog: catalog, pageCapacity: pageCapacity)
            hiddenApps = []
            onLayoutChange?(LayoutEngine.reconcile(layout: fallback, catalog: catalog, pageCapacity: pageCapacity).pages)
            return
        }
        let reconciled = LayoutEngine.reconcile(layout: document, catalog: catalog, pageCapacity: pageCapacity)
        if !reconciled.appendedApps.isEmpty {
            self.document = reconciled.document
            save(reconciled.document)
        }
        hiddenApps = reconciled.hiddenApps
        onLayoutChange?(reconciled.pages)
    }
```

- [ ] **Step 4: 确认通过**

Run: `swift test --filter LayoutCoordinatorTests 2>&1 | grep -E "error:|failed \(|Executed" | tail -2`
Expected: `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/LayoutCoordinator.swift Tests/LaunchAppTests/LayoutCoordinatorTests.swift
git commit -m "feat(布局): 发布隐藏的应用并支持取消隐藏"
```

---

### Task 5: ItemMenu

**Files:**
- Rename: `Sources/LaunchApp/SelectionMenu.swift` → `Sources/LaunchApp/ItemMenu.swift`；`Tests/LaunchAppTests/SelectionMenuTests.swift` → `Tests/LaunchAppTests/ItemMenuTests.swift`
- Modify: `Sources/LaunchApp/LauncherModel.swift`、`Sources/LaunchApp/ItemDragController.swift`、`Tests/LaunchAppTests/LauncherModelSelectionTests.swift`

- [ ] **Step 1: 改名**

```bash
git mv Sources/LaunchApp/SelectionMenu.swift Sources/LaunchApp/ItemMenu.swift
git mv Tests/LaunchAppTests/SelectionMenuTests.swift Tests/LaunchAppTests/ItemMenuTests.swift
```

- [ ] **Step 2: 失败测试** `Tests/LaunchAppTests/ItemMenuTests.swift` 全文

```swift
import AppKit
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
final class ItemMenuTests: XCTestCase {
    private func trigger(_ item: NSMenuItem?) {
        guard let item, let action = item.action else {
            return XCTFail("菜单项没有动作")
        }
        _ = (item.target as? NSObject)?.perform(action, with: item)
    }

    func testSelectionMenu() {
        var chosen: [ItemMenuCommand] = []
        let menu = ItemMenu { chosen.append($0) }.makeMenu(.selection(SelectionMenuContent(
            count: 3,
            folders: [.init(id: "f", name: "效率")],
            pageCount: 2
        )))
        let pages = menu.items[5].submenu

        XCTAssertEqual(menu.items.map(\.title), ["已选中 3 个项目", "", "合并到新文件夹", "合并到“效率”", "", "移动到", "隐藏"])
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertEqual(pages?.items.map(\.title), ["第 1 页", "第 2 页", "", "新页面"])

        trigger(menu.items[2])
        trigger(menu.items[3])
        trigger(pages?.items[1])
        trigger(pages?.items[3])
        trigger(menu.items[6])
        XCTAssertEqual(chosen, [.mergeIntoNewFolder, .mergeInto(folder: "f"), .moveToPage(1), .moveToNewPage, .hideSelection])
    }

    func testSingleSelectionCannotMerge() {
        let menu = ItemMenu { _ in }.makeMenu(.selection(SelectionMenuContent(
            count: 1,
            folders: [.init(id: "f", name: "效率")],
            pageCount: 1
        )))

        XCTAssertEqual(menu.items.map(\.title), ["已选中 1 个项目", "", "合并到新文件夹", "", "移动到", "隐藏"])
        XCTAssertFalse(menu.items[2].isEnabled)
    }

    func testAppMenu() {
        var chosen: [ItemMenuCommand] = []
        let app = makeApps(count: 1)[0]
        let menu = ItemMenu { chosen.append($0) }.makeMenu(.app(AppMenuContent(
            app: app,
            canOpen: false,
            canEdit: true,
            canUninstall: true
        )))

        XCTAssertEqual(menu.items.map(\.title), ["打开", "", "在访达中显示", "显示简介", "", "隐藏", "移到废纸篓…"])
        XCTAssertFalse(menu.items[0].isEnabled)
        for index in [2, 3, 5, 6] {
            trigger(menu.items[index])
        }
        XCTAssertEqual(chosen, [.revealInFinder(app), .showInfo(app), .hide(.app(app.identity.stableKey)), .moveToTrash(app)])

        let plain = ItemMenu { _ in }.makeMenu(.app(AppMenuContent(
            app: app,
            canOpen: true,
            canEdit: false,
            canUninstall: false
        )))
        XCTAssertEqual(plain.items.map(\.title), ["打开", "", "在访达中显示", "显示简介", "", "隐藏"])
        XCTAssertTrue(plain.items[0].isEnabled)
        XCTAssertFalse(plain.items[5].isEnabled)
    }

    func testFolderMenu() {
        var chosen: [ItemMenuCommand] = []
        let folder = ResolvedFolder(id: "f", name: "效率", apps: makeApps(count: 2))
        let menu = ItemMenu { chosen.append($0) }.makeMenu(.folder(FolderMenuContent(folder: folder, canEdit: true)))

        XCTAssertEqual(menu.items.map(\.title), ["打开", "", "重命名", "取消分组", "隐藏"])
        for index in [0, 2, 3, 4] {
            trigger(menu.items[index])
        }
        XCTAssertEqual(chosen, [.open(.folder(folder)), .rename(folder: "f"), .ungroup(folder: "f"), .hide(.folder("f"))])

        let locked = ItemMenu { _ in }.makeMenu(.folder(FolderMenuContent(folder: folder, canEdit: false)))
        XCTAssertEqual([2, 3, 4].map { locked.items[$0].isEnabled }, [false, false, false])
    }
}
```

- [ ] **Step 3: 确认失败**

Run: `swift test --filter ItemMenuTests 2>&1 | grep -E "error:" | head -3`
Expected: 编译错误，找不到 `ItemMenu`。

- [ ] **Step 4: 实现** `Sources/LaunchApp/ItemMenu.swift` 全文

```swift
import AppKit
import LaunchCore

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

struct AppMenuContent: Equatable {
    let app: CatalogApp
    let canOpen: Bool
    let canEdit: Bool
    let canUninstall: Bool
}

struct FolderMenuContent: Equatable {
    let folder: ResolvedFolder
    let canEdit: Bool
}

enum ItemMenuContent: Equatable {
    case selection(SelectionMenuContent)
    case app(AppMenuContent)
    case folder(FolderMenuContent)
}

enum ItemMenuCommand: Equatable {
    case mergeIntoNewFolder
    case mergeInto(folder: String)
    case moveToPage(Int)
    case moveToNewPage
    case hideSelection
    case open(ResolvedItem)
    case revealInFinder(CatalogApp)
    case showInfo(CatalogApp)
    case hide(LayoutItemID)
    case moveToTrash(CatalogApp)
    case rename(folder: String)
    case ungroup(folder: String)
}

@MainActor
final class ItemMenu: NSObject {
    private let onCommand: (ItemMenuCommand) -> Void
    private var commands: [ItemMenuCommand] = []

    init(onCommand: @escaping (ItemMenuCommand) -> Void) {
        self.onCommand = onCommand
    }

    func makeMenu(_ content: ItemMenuContent) -> NSMenu {
        commands = []
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch content {
        case .selection(let selection):
            addSelectionItems(selection, to: menu)
        case .app(let app):
            addAppItems(app, to: menu)
        case .folder(let folder):
            addFolderItems(folder, to: menu)
        }
        return menu
    }

    private func addSelectionItems(_ content: SelectionMenuContent, to menu: NSMenu) {
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
        menu.addItem(item("隐藏", .hideSelection))
    }

    private func addAppItems(_ content: AppMenuContent, to menu: NSMenu) {
        let app = content.app
        menu.addItem(item("打开", .open(.app(app)), isEnabled: content.canOpen))
        menu.addItem(.separator())
        menu.addItem(item("在访达中显示", .revealInFinder(app)))
        menu.addItem(item("显示简介", .showInfo(app)))
        menu.addItem(.separator())
        menu.addItem(item("隐藏", .hide(.app(app.identity.stableKey)), isEnabled: content.canEdit))
        if content.canUninstall {
            menu.addItem(item("移到废纸篓…", .moveToTrash(app)))
        }
    }

    private func addFolderItems(_ content: FolderMenuContent, to menu: NSMenu) {
        let folder = content.folder
        menu.addItem(item("打开", .open(.folder(folder))))
        menu.addItem(.separator())
        menu.addItem(item("重命名", .rename(folder: folder.id), isEnabled: content.canEdit))
        menu.addItem(item("取消分组", .ungroup(folder: folder.id), isEnabled: content.canEdit))
        menu.addItem(item("隐藏", .hide(.folder(folder.id)), isEnabled: content.canEdit))
    }

    private func item(_ title: String, _ command: ItemMenuCommand, isEnabled: Bool = true) -> NSMenuItem {
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

调用方随之改名（行为不变，新命令到 Task 6 再处理）：

`LauncherModel.performSelectionCommand` 的参数类型改为 `ItemMenuCommand`，`switch` 补上新命令：

```swift
    func performSelectionCommand(_ command: ItemMenuCommand) {
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
        case .hideSelection:
            edit = .hide(items)
        case .open, .revealInFinder, .showInfo, .hide, .moveToTrash, .rename, .ungroup:
            return
        }
        clearMultiSelection()
        selectedIndex = nil
        onEdit?(edit)
    }
```

`ItemDragController`：

```swift
    private lazy var selectionMenu = ItemMenu { [weak self] command in
        self?.model.performSelectionCommand(command)
    }
```

```swift
            selectionMenu.makeMenu(.selection(content)).popUp(positioning: nil, at: location, in: view)
```

`LauncherModelSelectionTests.swift` 中 `[SelectionCommand]` 改为 `[ItemMenuCommand]`。

- [ ] **Step 5: 确认通过**

Run: `swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | tail -3`
Expected: 全部 `0 failures`。

- [ ] **Step 6: 提交**

```bash
git add -A Sources/LaunchApp/ItemMenu.swift Sources/LaunchApp/SelectionMenu.swift Tests/LaunchAppTests/ItemMenuTests.swift Tests/LaunchAppTests/SelectionMenuTests.swift Sources/LaunchApp/LauncherModel.swift Sources/LaunchApp/ItemDragController.swift Tests/LaunchAppTests/LauncherModelSelectionTests.swift
git commit -m "feat(编辑): 应用与文件夹的右键菜单"
```

---

### Task 6: LauncherModel 菜单内容与命令

**Files:**
- Modify: `Sources/LaunchApp/LauncherModel.swift`、`Sources/LaunchApp/ItemDragController.swift`、`Tests/LaunchAppTests/LauncherModelSelectionTests.swift`
- Test: `Tests/LaunchAppTests/LauncherModelMenuTests.swift`

- [ ] **Step 1: 失败测试** `Tests/LaunchAppTests/LauncherModelMenuTests.swift`

```swift
import CoreGraphics
import LaunchCore
import XCTest
@testable import LaunchApp

final class LauncherModelMenuTests: XCTestCase {
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

    private func id(_ app: CatalogApp) -> LayoutItemID {
        .app(app.identity.stableKey)
    }

    @MainActor
    private func makeModel(pages: [[ResolvedItem]], apps: [CatalogApp] = []) -> (LauncherModel, EditLog) {
        let model = LauncherModel(apps: apps)
        let log = EditLog()
        model.updateLayout(pages)
        model.canEditLayout = true
        model.onEdit = { log.edits.append($0) }
        model.updateHomeLayout(layout)
        model.updateGridFrame(gridFrame)
        model.updateFolderGridFrame(gridFrame)
        return (model, log)
    }

    @MainActor
    func testAppAndFolderMenus() {
        let apps = makeApps(count: 3)
        let folder = ResolvedFolder(id: "f", name: "效率", apps: [apps[2]])
        let (model, _) = makeModel(pages: [[.app(apps[0]), .app(apps[1]), .folder(folder)]])
        model.canUninstall = { $0 == apps[1] }

        XCTAssertEqual(model.contextMenu(at: center(0)), .app(AppMenuContent(app: apps[0], canOpen: true, canEdit: true, canUninstall: false)))
        XCTAssertEqual(model.contextMenu(at: center(1)), .app(AppMenuContent(app: apps[1], canOpen: true, canEdit: true, canUninstall: true)))
        XCTAssertEqual(model.contextMenu(at: center(2)), .folder(FolderMenuContent(folder: folder, canEdit: true)))
        XCTAssertNil(model.contextMenu(at: CGPoint(x: 5, y: 5)))

        model.beginJiggling()
        model.canEditLayout = false
        XCTAssertEqual(model.contextMenu(at: center(0)), .app(AppMenuContent(app: apps[0], canOpen: false, canEdit: false, canUninstall: false)))
    }

    @MainActor
    func testPickedItemGetsSelectionMenuAndOtherItemClearsSelection() {
        let apps = makeApps(count: 3)
        let (model, _) = makeModel(pages: [apps.map(ResolvedItem.app)])
        model.toggleMultiSelection(id(apps[0]))
        model.toggleMultiSelection(id(apps[1]))

        guard case .selection? = model.contextMenu(at: center(0)) else {
            return XCTFail("expected selection menu")
        }
        XCTAssertEqual(model.multiSelection.count, 2)
        guard case .app? = model.contextMenu(at: center(2)) else {
            return XCTFail("expected app menu")
        }
        XCTAssertTrue(model.multiSelection.isEmpty)
    }

    @MainActor
    func testMemberMenuInsideOpenFolder() {
        let apps = makeApps(count: 2)
        let (model, _) = makeModel(pages: [[.folder(ResolvedFolder(id: "f", name: "效率", apps: apps))]])
        model.showFolder(id: "f")

        XCTAssertEqual(model.contextMenu(at: center(1)), .app(AppMenuContent(app: apps[1], canOpen: true, canEdit: true, canUninstall: false)))
    }

    @MainActor
    func testMenuCommandsBecomeEdits() {
        let apps = makeApps(count: 3)
        let (model, log) = makeModel(pages: [[.app(apps[0]), makeFolder(id: "f", name: "效率", apps: [apps[1], apps[2]])]])

        model.performMenuCommand(.hide(id(apps[0])))
        model.performMenuCommand(.ungroup(folder: "f"))
        model.toggleMultiSelection(id(apps[0]))
        model.toggleMultiSelection(.folder("f"))
        model.performMenuCommand(.hideSelection)
        model.performMenuCommand(.showInfo(apps[0]))

        XCTAssertEqual(log.edits, [.hide([id(apps[0])]), .ungroupFolder("f"), .hide([id(apps[0]), .folder("f")])])
        XCTAssertTrue(model.multiSelection.isEmpty)

        model.canEditLayout = false
        model.performMenuCommand(.hide(id(apps[0])))
        model.performMenuCommand(.ungroup(folder: "f"))
        XCTAssertEqual(log.edits.count, 3)
    }

    @MainActor
    func testRenameCommandOpensFolderAndStartsRenaming() {
        let apps = makeApps(count: 2)
        let (model, _) = makeModel(pages: [[makeFolder(id: "f", name: "效率", apps: apps)]])

        model.performMenuCommand(.rename(folder: "f"))

        XCTAssertEqual(model.openFolderID, "f")
        XCTAssertEqual(model.renamingFolderID, "f")
        XCTAssertEqual(model.folderNameDraft, "效率")
    }

    @MainActor
    func testSearchSkipsHiddenApps() {
        let apps = makeApps(count: 3)
        let model = LauncherModel(apps: apps)

        model.updateHiddenApps([apps[1]])
        model.setQuery("App")

        XCTAssertEqual(model.results, [apps[0], apps[2]])
    }
}
```

`LauncherModelSelectionTests.swift` 中 `model.performSelectionCommand(command)` 改为 `model.performMenuCommand(command)`。

- [ ] **Step 2: 确认失败**

Run: `swift test --filter LauncherModelMenuTests 2>&1 | grep -E "error:" | head -3`
Expected: 编译错误，找不到 `contextMenu`、`performMenuCommand`、`updateHiddenApps`。

- [ ] **Step 3: 实现** `LauncherModel.swift`

属性（`private(set) var marqueeRect` 之后）：

```swift
    private(set) var hiddenApps: Set<AppIdentity> = []
```

`results` 改为：

```swift
    var results: [CatalogApp] {
        SearchService.results(for: query, in: apps, hidden: hiddenApps)
    }
```

`updateApps` 之后：

```swift
    func updateHiddenApps(_ apps: [CatalogApp]) {
        let identities = Set(apps.map(\.identity))
        guard identities != hiddenApps else {
            return
        }
        hiddenApps = identities
        normalizeState()
    }
```

`selectionMenu(at:)` 之后：

```swift
    // 未选中的图标弹出自己的菜单前先清空多选
    func contextMenu(at point: CGPoint) -> ItemMenuContent? {
        if let selection = selectionMenu(at: point) {
            return .selection(selection)
        }
        guard let press = itemPress(at: point) else {
            return nil
        }
        clearMultiSelection()
        switch press.item {
        case .app(let app):
            return .app(AppMenuContent(
                app: app,
                canOpen: !isJiggling,
                canEdit: canEditMenuItems,
                canUninstall: canUninstall(app)
            ))
        case .folder(let folder):
            return .folder(FolderMenuContent(folder: folder, canEdit: canEditMenuItems))
        case .empty:
            return nil
        }
    }

    func performMenuCommand(_ command: ItemMenuCommand) {
        switch command {
        case .mergeIntoNewFolder, .mergeInto, .moveToPage, .moveToNewPage, .hideSelection:
            performSelectionCommand(command)
        case .hide(let item):
            if canEditMenuItems {
                onEdit?(.hide([item]))
            }
        case .ungroup(let folder):
            if canEditMenuItems {
                onEdit?(.ungroupFolder(folder))
            }
        case .rename(let folder):
            showFolder(id: folder)
            beginRenamingFolder()
        case .open, .revealInFinder, .showInfo, .moveToTrash:
            break
        }
    }

    // 搜索结果里也能隐藏，所以不要求搜索框为空
    private var canEditMenuItems: Bool {
        canEditLayout && layoutPages != nil && renamingFolderID == nil
    }
```

`performSelectionCommand` 改为 `private`。

`ItemDragController` 中 `self?.model.performSelectionCommand(command)` 改为 `self?.model.performMenuCommand(command)`。

- [ ] **Step 4: 确认通过**

Run: `swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | tail -3`
Expected: 全部 `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/LauncherModel.swift Sources/LaunchApp/ItemDragController.swift Tests/LaunchAppTests/LauncherModelMenuTests.swift Tests/LaunchAppTests/LauncherModelSelectionTests.swift
git commit -m "feat(编辑): 模型给出右键菜单并处理隐藏、取消分组与改名"
```

---

### Task 7: AppActions

**Files:**
- Create: `Sources/LaunchApp/AppActions.swift`
- Modify: `Sources/LaunchApp/UninstallCoordinator.swift`、`Resources/Info.plist`
- Test: `Tests/LaunchAppTests/AppActionsTests.swift`

- [ ] **Step 1: 失败测试**

```swift
import XCTest
@testable import LaunchApp

final class AppActionsTests: XCTestCase {
    func testInfoScriptEscapesPath() {
        let script = AppActions.infoScript(path: #"/Applications/A "B"\C.app"#)

        XCTAssertTrue(script.contains(#"open information window of (POSIX file "/Applications/A \"B\"\\C.app" as alias)"#))
        XCTAssertTrue(script.contains(#"tell application "Finder""#))
    }
}
```

- [ ] **Step 2: 确认失败**

Run: `swift test --filter AppActionsTests 2>&1 | grep -E "error:" | head -3`
Expected: 编译错误，找不到 `AppActions`。

- [ ] **Step 3: 实现**

`UninstallCoordinator.swift`：删除 `AlertUninstallPrompter` 的 `private static func run`，两处 `Self.run(alert)` 改为 `alert.runAboveLauncher()`，文件末尾加：

```swift
extension NSAlert {
    // 启动器面板在 statusBar 层级；runModal 会把层级重设为模态面板层级，要在模态会话里再调高
    // 主线程 Task 内模态期间主队列不会重入，只能用运行循环的模态模式执行
    func runAboveLauncher() -> NSApplication.ModalResponse {
        RunLoop.main.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated {
                self.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            }
        }
        return runModal()
    }
}
```

`Sources/LaunchApp/AppActions.swift`：

```swift
import AppKit
import LaunchCore

@MainActor
struct AppActions {
    private static let notPermitted = -1743

    func revealInFinder(_ app: CatalogApp) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.identity.path)])
    }

    // 访达没有公开的显示简介接口，只能用 Apple 事件，首次会弹出自动化授权
    func showInfo(_ app: CatalogApp) {
        var error: NSDictionary?
        NSAppleScript(source: Self.infoScript(path: app.identity.path))?.executeAndReturnError(&error)
        guard let error else {
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法显示简介"
        if error[NSAppleScript.errorNumber] as? Int == Self.notPermitted {
            alert.informativeText = "Launch 没有控制访达的权限，请在“系统设置 → 隐私与安全性 → 自动化”中允许 Launch 控制“访达”。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runAboveLauncher() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.informativeText = error[NSAppleScript.errorMessage] as? String ?? "访达没有响应。"
            _ = alert.runAboveLauncher()
        }
    }

    nonisolated static func infoScript(path: String) -> String {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Finder"
            activate
            open information window of (POSIX file "\(escaped)" as alias)
        end tell
        """
    }
}
```

`Resources/Info.plist` 在 `NSHighResolutionCapable` 之前加：

```xml
    <key>NSAppleEventsUsageDescription</key>
    <string>用于在访达中打开应用的简介窗口。</string>
```

- [ ] **Step 4: 确认通过**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete"` 与 `swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | tail -3`
Expected: `Build complete`；全部 `0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/AppActions.swift Sources/LaunchApp/UninstallCoordinator.swift Resources/Info.plist Tests/LaunchAppTests/AppActionsTests.swift
git commit -m "feat(编辑): 在访达中显示与显示简介"
```

---

### Task 8: 接入菜单命令与菜单栏取消隐藏

**Files:**
- Modify: `Sources/LaunchApp/ItemDragController.swift`、`Sources/LaunchApp/StatusItemController.swift`、`Sources/LaunchApp/LaunchApp.swift`

AppKit 接入没有单元测试，靠 Task 9 的 e2e 验证。

- [ ] **Step 1: `ItemDragController`**

属性与初始化：

```swift
    private let onMenuCommand: (ItemMenuCommand) -> Void
    private lazy var itemMenu = ItemMenu { [weak self] command in
        self?.onMenuCommand(command)
    }
```

（删除原 `selectionMenu`。）`init` 增加参数 `onMenuCommand: @escaping (ItemMenuCommand) -> Void`（放在 `onUninstall` 之后）并赋值。

`contextClick`：

```swift
    private func contextClick(at point: CGPoint, event: NSEvent) -> NSEvent? {
        guard let content = model.contextMenu(at: point), let view = presenter.contentView else {
            return event
        }
        let location = view.convert(event.locationInWindow, from: nil)
        itemMenu.makeMenu(content).popUp(positioning: nil, at: location, in: view)
        return nil
    }
```

- [ ] **Step 2: `StatusItemController`**

文件顶部加 `import LaunchCore`。`LayoutMenuActions` 增加：

```swift
    let hiddenApps: () -> [CatalogApp]
    let unhide: (CatalogApp) -> Void
    let unhideAll: () -> Void
```

属性：

```swift
    private let hiddenItem = NSMenuItem(title: "隐藏的应用", action: nil, keyEquivalent: "")
    private var hiddenApps: [CatalogApp] = []
```

`menu.items` 改为 `[openItem, conflictItem, .separator(), loginItem, importItem, restoreItem, hiddenItem, .separator(), quitItem]`。

`menuNeedsUpdate` 末尾：

```swift
        hiddenApps = layoutMenu.hiddenApps()
        hiddenItem.isEnabled = !hiddenApps.isEmpty
        hiddenItem.submenu = hiddenAppsMenu()
```

新增：

```swift
    private func hiddenAppsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, app) in hiddenApps.enumerated() {
            let item = NSMenuItem(title: app.displayName, action: #selector(unhideApp(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let all = NSMenuItem(title: "全部取消隐藏", action: #selector(unhideAll), keyEquivalent: "")
        all.target = self
        menu.addItem(all)
        return menu
    }

    @objc private func unhideApp(_ sender: NSMenuItem) {
        layoutMenu.unhide(hiddenApps[sender.tag])
    }

    @objc private func unhideAll() {
        layoutMenu.unhideAll()
    }
```

- [ ] **Step 3: `LaunchApp.swift`**

属性：`private let appActions = AppActions()`。

`itemDragController` 增加 `onMenuCommand: { [weak self] command in self?.performMenuCommand(command) },`（在 `onUninstall` 之后）。

`layoutCoordinator.onLayoutChange` 中 `controller.model.updateLayout(pages)` 之前加：

```swift
            controller.model.updateHiddenApps(layoutCoordinator.hiddenApps)
```

`LayoutMenuActions(...)` 增加：

```swift
                restoreLayout: { [weak self] in self?.layoutCoordinator.restoreBackup() },
                hiddenApps: { [weak self] in self?.layoutCoordinator.hiddenApps ?? [] },
                unhide: { [weak self] app in self?.layoutCoordinator.unhide(app) },
                unhideAll: { [weak self] in self?.layoutCoordinator.unhideAll() }
```

`activate(_:)` 之后新增：

```swift
    // NSObject 自带 perform(_:)，换个名字避免与选择器版本混淆
    private func performMenuCommand(_ command: ItemMenuCommand) {
        switch command {
        case .open(let item):
            activate(item)
        case .revealInFinder(let app):
            appActions.revealInFinder(app)
        case .showInfo(let app):
            appActions.showInfo(app)
        case .moveToTrash(let app):
            uninstall(app)
        default:
            controller.model.performMenuCommand(command)
        }
    }
```

- [ ] **Step 4: 构建、测试、安装**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete"`、`swift test 2>&1 | grep -E "error:|with [1-9][0-9]* failures|Executed [0-9]+ tests" | tail -3`，再执行安装命令。
Expected: `Build complete`，无警告；全部 `0 failures`；安装成功。

- [ ] **Step 5: 提交**

```bash
git add Sources/LaunchApp/ItemDragController.swift Sources/LaunchApp/StatusItemController.swift Sources/LaunchApp/LaunchApp.swift
git commit -m "feat(编辑): 接入右键菜单命令与菜单栏取消隐藏"
```

---

### Task 9: 目标机验证与文档

- [ ] **Step 1: 备份布局**

```bash
L="$HOME/Library/Application Support/Launch"; B=$(mktemp -d); echo "$B" > /tmp/launch-layout-backup-dir
cp "$L/layout.json" "$B/"; [ -f "$L/layout.json.backup" ] && cp "$L/layout.json.backup" "$B/"
shasum -a 256 "$L"/layout.json* | tee "$B/sha.txt"
```

- [ ] **Step 2: e2e**

复用第 4b 期的 `prelude.swift`：

```bash
E=$(mktemp -d); echo "$E" > /tmp/launch-e2e-4c-dir; mkdir -p "$E/c"
cp "$(cat /tmp/launch-e2e-4b-dir)/prelude.swift" "$E/"
```

`$E/c/main.swift`：

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
func press(_ name: String) -> Bool {
    guard let item = anyMenuItem(name) else { return false }
    AXUIElementPerformAction(item, kAXPressAction as CFString); wait(1.0); return true
}
func hover(_ name: String) {
    if let f = anyMenuItem(name).flatMap(frame) { mouse(.mouseMoved, CGPoint(x: f.midX, y: f.midY)); wait(0.8) }
}
func openStatusMenu() {
    if let item = extrasBar().flatMap({ kids($0).first }) { AXUIElementPerformAction(item, kAXPressAction as CFString) }
    wait(0.8)
}
func finderWindowCount() -> Int {
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return 0 }
    return (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []).filter {
        ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == finder.processIdentifier && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
    }.count
}

dismissDialogs()
let originalMouse = CGEvent(source: nil)?.location ?? .zero
let appsBefore = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
CGWarpMouseCursorPosition(CGPoint(x: 756, y: 491)); mouse(.mouseMoved, CGPoint(x: 756, y: 491)); wait(0.3)
openLauncher()
selectPage("第 1 页")
let base = names()
let f = tiles().map(\.frame)
guard base.count >= 6 else { print("FAIL 第 1 页图标不足"); exit(1) }
let cmd = CGEventFlags.maskCommand
let target = base[3]

// C1 应用菜单
rightClick(iconCenter(f[3])); wait(0.8)
check(["打开", "在访达中显示", "显示简介", "隐藏"].allSatisfy { menuItem($0) != nil }, "C1 应用菜单项齐全")
key(53); wait(0.5)
check(panelVisible() && menuItem("显示简介") == nil, "C1 Esc 只关闭菜单")

// C2 隐藏后从菜单栏取消隐藏
rightClick(iconCenter(f[3])); wait(0.8)
_ = press("隐藏")
check(!names().contains(target), "C2 隐藏后图标消失")
openStatusMenu(); hover("隐藏的应用")
check(anyMenuItem(target) != nil, "C2 菜单栏列出「\(target)」")
_ = press(target)
check(names() == base, "C2 取消隐藏后回到原位")
key(6, flags: cmd); wait(1.0)
check(!names().contains(target), "C2 ⌘Z 撤销取消隐藏")
key(6, flags: cmd); wait(1.0)
check(names() == base, "C2 再次 ⌘Z 撤销隐藏")

// C3 文件夹菜单：取消分组；C4 重命名
if let fi = base.firstIndex(of: "效率") {
    rightClick(iconCenter(f[fi])); wait(0.8)
    check(["打开", "重命名", "取消分组", "隐藏"].allSatisfy { menuItem($0) != nil }, "C3 文件夹菜单项齐全")
    _ = press("取消分组")
    check(!names().contains("效率") && names()[fi] == base[fi + 1], "C3 取消分组后文件夹消失、后面的图标前移")
    key(6, flags: cmd); wait(1.0)
    check(names() == base, "C3 ⌘Z 撤销取消分组")

    rightClick(iconCenter(f[fi])); wait(0.8)
    _ = press("重命名")
    check(elements().contains { role($0) == kAXTextFieldRole && (attr($0, kAXValueAttribute) as? String) == "效率" }, "C4 打开文件夹并进入改名")
    key(53); wait(0.4); key(53); wait(0.6)
    check(panelVisible() && names() == base, "C4 Esc 取消改名并关闭文件夹")
} else {
    check(false, "C3 第 1 页没有「效率」文件夹")
}

// C5 多选隐藏与全部取消隐藏
click(iconCenter(f[0]), flags: cmd); click(iconCenter(f[1]), flags: cmd)
rightClick(iconCenter(f[0])); wait(0.8)
_ = press("隐藏")
check(Array(names().prefix(4)) == Array(base.dropFirst(2).prefix(4)), "C5 多选隐藏两项")
openStatusMenu(); hover("隐藏的应用")
_ = press("全部取消隐藏")
check(names() == base, "C5 全部取消隐藏")

// C6 在访达中显示
let finderBefore = finderWindowCount()
rightClick(iconCenter(f[3])); wait(0.8)
_ = press("在访达中显示"); wait(1.0)
check(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder", "C6 访达到前台")
check(!panelVisible(), "C6 启动器随之隐藏")
if finderWindowCount() > finderBefore { key(13, flags: cmd); wait(0.6) }
check(finderWindowCount() == finderBefore, "C6 已关闭打开的访达窗口")

let appsAfter = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
check(appsAfter.subtracting(appsBefore).subtracting([launchID]).isEmpty, "全程未启动应用")
CGWarpMouseCursorPosition(originalMouse)
print("FAILURES \(failures)")
```

Run: `E=$(cat /tmp/launch-e2e-4c-dir); swiftc -O "$E/prelude.swift" "$E/c/main.swift" -o "$E/c/run" && "$E/c/run"`
Expected: 全部 `PASS`。

- [ ] **Step 3: 回归第 4b 期 e2e**

Run: `E=$(cat /tmp/launch-e2e-4b-dir); "$E/m/run" | tail -3`
Expected: `FAILURES 0`。

- [ ] **Step 4: 还原布局**

```bash
L="$HOME/Library/Application Support/Launch"; B=$(cat /tmp/launch-layout-backup-dir)
cp "$B/layout.json" "$L/layout.json"; [ -f "$B/layout.json.backup" ] && cp "$B/layout.json.backup" "$L/layout.json.backup"
shasum -a 256 "$L"/layout.json* | diff - "$B/sha.txt" && echo "布局已还原"
pkill -x LaunchApp; sleep 1; open "$HOME/Applications/Launch.app"
```

- [ ] **Step 5: 文档**

- `README.md`：把「单项右键菜单、隐藏应用（4c）和 F4/手势等系统入口仍未实现。」改为 4c 已完成（右键应用可打开、在访达中显示、显示简介、隐藏、移到废纸篓，右键文件夹可重命名、取消分组、隐藏；隐藏的应用在菜单栏「隐藏的应用」中取消隐藏），再写「F4/手势等系统入口与设置窗口仍未实现」。
- `docs/architecture.md` 第 7 节第 4 条：4c 标为已完成并引用 `docs/superpowers/specs/2026-10-20-context-menu-hide-design.md`；第 9 节删除「隐藏与单项右键菜单细节（4c）」。
- `docs/manual-verification.md`：当前结果追加本次 e2e、第 4b 期回归与布局还原；待验证追加「显示简介（首次需允许 Launch 控制访达）、对真实应用的移到废纸篓由用户自行决定」。

```bash
git add README.md docs/architecture.md docs/manual-verification.md
git commit -m "chore(文档): 记录第 4c 期右键菜单与隐藏的验证结果"
```

---

## Self-Review

- Spec 覆盖：3.1 右键菜单 → Task 5/6/7/8；3.2 隐藏 → Task 1/2/3/4/8；4 组件 → 各任务（Info.plist 实际在 `Resources/Info.plist`，构建脚本直接拷贝）；5 `LayoutEditor` 规则 → Task 3；6 测试与验证 → Task 1–7 单测、Task 9 e2e。
- 类型一致：`LayoutDocument.hiddenApps`、`ReconciledLayout.hiddenApps`、`CatalogResolver.keys(of:)`、`LayoutEdit.hide/unhide/ungroupFolder`、`LayoutCoordinator.hiddenApps/unhide/unhideAll`、`ItemMenu`、`ItemMenuContent`、`AppMenuContent(app:canOpen:canEdit:canUninstall:)`、`FolderMenuContent(folder:canEdit:)`、`ItemMenuCommand`、`LauncherModel.hiddenApps/updateHiddenApps/contextMenu(at:)/performMenuCommand`、`AppActions.revealInFinder/showInfo/infoScript(path:)`、`NSAlert.runAboveLauncher()`、`LayoutMenuActions.hiddenApps/unhide/unhideAll` 各处一致。
