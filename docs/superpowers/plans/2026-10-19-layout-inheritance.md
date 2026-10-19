# 第 2 期：布局继承 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 只读导入旧 Launchpad 布局（页面、顺序、文件夹），持久化为独立布局，启动器按布局显示并支持展开文件夹。

**Architecture:** `LaunchCore` 负责纯逻辑：SQLite 只读读取快照、快照转布局、布局与应用目录对齐、布局文件读写与备份互换。`LaunchApp` 的 `LayoutCoordinator` 串起启动加载、首次导入、目录变化保存与菜单操作，提示框与数据库来源经协议注入以便测试；`LauncherModel` 持有布局页与打开的文件夹，`LauncherView` 渲染应用、文件夹格子与展开面板。

**Tech Stack:** Swift 6.4（tools 6.2）、macOS 26、SQLite3（系统库）、AppKit、SwiftUI、XCTest。

**Spec:** `docs/superpowers/specs/2026-10-19-layout-inheritance-design.md`

## 全局约束

- 只改本期必需的代码；`LaunchpadProbe` 保持不动。
- 旧 Launchpad 数据库只读：只复制到临时目录后读取，绝不写原文件。
- 注释一行为限。
- 每个任务完成并验证后直接提交（用户已授权），标题行 `<type>(<中文scope>): <中文描述>`，不加 `Co-Authored-By`。
- 测试：`swift test`；单个测试类 `swift test --filter <Target>.<Class>`。

## 文件结构

| 文件 | 操作 | 职责 |
| --- | --- | --- |
| `Sources/LaunchCore/Models.swift` | 修改 | `LayoutFolder`、`.folder`、移除 `.missing`；`ResolvedItem`、`ResolvedFolder` |
| `Sources/LaunchCore/LayoutEngine.swift` | 重写 | `CatalogResolver`、`reconcile`、`appending`、`defaultDocument` |
| `Sources/LaunchCore/LayoutStore.swift` | 修改 | `backupURL`、`hasBackup`、`replace(with:)`、`swapWithBackup()`、错误描述 |
| `Sources/LaunchCore/LaunchpadSnapshot.swift` | 新增 | 快照类型 |
| `Sources/LaunchCore/LaunchpadSnapshotReader.swift` | 新增 | 定位、复制、SQLite 只读查询 |
| `Sources/LaunchCore/LaunchpadImporter.swift` | 新增 | 快照 → 布局与摘要 |
| `Sources/LaunchApp/LauncherHomeLayout.swift` | 修改 | 文件夹尺寸 |
| `Sources/LaunchApp/LauncherModel.swift` | 修改 | 布局页、文件夹状态、Esc 三层 |
| `Sources/LaunchApp/LauncherController.swift` | 修改 | 点击背景 |
| `Sources/LaunchApp/LauncherView.swift` | 修改 | 渲染条目、文件夹格子、展开面板 |
| `Sources/LaunchApp/LayoutCoordinator.swift` | 新增 | 协调器与 `LayoutPrompting`、`LaunchpadSource` 协议 |
| `Sources/LaunchApp/LayoutPrompts.swift` | 新增 | `LayoutPromptText`、`AlertLayoutPrompter`、`LiveLaunchpadSource` |
| `Sources/LaunchApp/StatusItemController.swift` | 修改 | 导入、恢复菜单项 |
| `Sources/LaunchApp/LaunchApp.swift` | 修改 | 组装协调器 |
| `Tests/LaunchCoreTests/LayoutFixtures.swift` | 新增 | `layoutApp(_:)` |
| `Tests/LaunchCoreTests/*` | 新增/修改 | 各组件单测 |
| `Tests/LaunchAppTests/*` | 新增/修改 | 各组件单测 |

---

### Task 1: 布局模型支持文件夹并按安装状态对齐

**Files:**
- Modify: `Sources/LaunchCore/Models.swift`
- Rewrite: `Sources/LaunchCore/LayoutEngine.swift`
- Create: `Tests/LaunchCoreTests/LayoutFixtures.swift`
- Rewrite: `Tests/LaunchCoreTests/LayoutEngineTests.swift`
- Modify: `Tests/LaunchCoreTests/ModelsTests.swift`

- [ ] **Step 1: 测试辅助 `Tests/LaunchCoreTests/LayoutFixtures.swift`**

```swift
import LaunchCore

func layoutApp(_ name: String) -> CatalogApp {
    CatalogApp(
        identity: AppIdentity(
            bundleIdentifier: "com.example.\(name.lowercased())",
            path: "/Applications/\(name).app"
        ),
        displayName: name
    )
}
```

- [ ] **Step 2: 重写 `Tests/LaunchCoreTests/LayoutEngineTests.swift`（失败测试）**

```swift
import XCTest
@testable import LaunchCore

final class LayoutEngineTests: XCTestCase {
    private let mail = layoutApp("Mail")
    private let notes = layoutApp("Notes")
    private let zoom = layoutApp("Zoom")
    private let gone = AppIdentity(bundleIdentifier: "com.example.gone", path: "")

    func testMissingAppIsHiddenButKeptInDocument() {
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.app(mail.identity), .app(gone), .app(notes.identity)]),
        ])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.app(mail), .app(notes)]])
        XCTAssertEqual(result.document, document)
        XCTAssertEqual(result.appendedApps, [])
    }

    func testBundleIdentifierMatchesMovedApp() {
        let saved = AppIdentity(bundleIdentifier: mail.identity.bundleIdentifier, path: "/Old/Mail.app")
        let document = LayoutDocument(pages: [LayoutPage(slots: [.app(saved)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.app(mail)]])
    }

    func testFolderShowsOnlyInstalledMembers() {
        let folder = LayoutFolder(id: "f", name: "效率", apps: [mail.identity, gone])
        let document = LayoutDocument(pages: [LayoutPage(slots: [.folder(folder)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.folder(ResolvedFolder(id: "f", name: "效率", apps: [mail]))]])
        XCTAssertEqual(result.appendedApps, [])
    }

    func testFolderWithoutInstalledMembersAndEmptiedPageAreHidden() {
        let folder = LayoutFolder(id: "f", name: "空", apps: [gone])
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.folder(folder)]),
            LayoutPage(slots: [.app(notes.identity)]),
        ])

        let result = LayoutEngine.reconcile(layout: document, catalog: [notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.app(notes)]])
    }

    func testIntentionalEmptySlotIsKept() {
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.app(mail.identity), .empty, .app(notes.identity)]),
        ])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.app(mail), .empty, .app(notes)]])
    }

    func testNewAppsAppendToLastPageThenOpenNewPage() {
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.app(mail.identity), .app(notes.identity)]),
        ])
        let alpha = layoutApp("Alpha")
        let beta = layoutApp("Beta")

        let result = LayoutEngine.reconcile(
            layout: document,
            catalog: [alpha, beta, mail, notes],
            pageCapacity: 3
        )

        XCTAssertEqual(result.appendedApps, [alpha, beta])
        XCTAssertEqual(result.document.pages, [
            LayoutPage(slots: [.app(mail.identity), .app(notes.identity), .app(alpha.identity)]),
            LayoutPage(slots: [.app(beta.identity)]),
        ])
        XCTAssertEqual(result.pages, [[.app(mail), .app(notes), .app(alpha)], [.app(beta)]])
    }

    func testAppsInsideFoldersAreNotAppendedAgain() {
        let folder = LayoutFolder(id: "f", name: "效率", apps: [mail.identity])
        let document = LayoutDocument(pages: [LayoutPage(slots: [.folder(folder)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail], pageCapacity: 35)

        XCTAssertEqual(result.appendedApps, [])
    }

    func testDefaultDocumentPaginatesCatalogInOrder() {
        let document = LayoutEngine.defaultDocument(catalog: [mail, notes, zoom], pageCapacity: 2)

        XCTAssertEqual(document.pages, [
            LayoutPage(slots: [.app(mail.identity), .app(notes.identity)]),
            LayoutPage(slots: [.app(zoom.identity)]),
        ])
    }
}
```

- [ ] **Step 3: `ModelsTests.swift` 末尾（类内）新增编码往返测试**

```swift
    func testLayoutWithFolderSurvivesJSONRoundTrip() throws {
        let reader = AppIdentity(bundleIdentifier: "com.example.Reader", path: "/Applications/Reader.app")
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.folder(LayoutFolder(id: "f", name: "阅读", apps: [reader])), .empty]),
        ])

        let decoded = try JSONDecoder().decode(
            LayoutDocument.self,
            from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(decoded, document)
    }
```

- [ ] **Step 4: 运行确认失败**

Run: `swift test --filter LaunchCoreTests 2>&1 | grep -E "error:" | sort -u | head -5`
Expected: 编译失败，含 `cannot find 'LayoutFolder' in scope` 或 `extra argument 'pageCapacity'`。

- [ ] **Step 5: 修改 `Sources/LaunchCore/Models.swift`**

将 `LayoutSlot` 替换为：

```swift
public struct LayoutFolder: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let apps: [AppIdentity]

    public init(id: String, name: String, apps: [AppIdentity]) {
        self.id = id
        self.name = name
        self.apps = apps
    }
}

public enum LayoutSlot: Codable, Equatable, Sendable {
    case app(AppIdentity)
    case folder(LayoutFolder)
    case empty
}
```

在文件末尾追加：

```swift
public struct ResolvedFolder: Equatable, Sendable {
    public let id: String
    public let name: String
    public let apps: [CatalogApp]

    public init(id: String, name: String, apps: [CatalogApp]) {
        self.id = id
        self.name = name
        self.apps = apps
    }
}

public enum ResolvedItem: Equatable, Sendable {
    case app(CatalogApp)
    case folder(ResolvedFolder)
    case empty
}
```

- [ ] **Step 6: 重写 `Sources/LaunchCore/LayoutEngine.swift`**

```swift
import Foundation

public struct ReconciledLayout: Equatable, Sendable {
    public let pages: [[ResolvedItem]]
    public let document: LayoutDocument
    public let appendedApps: [CatalogApp]
}

struct CatalogResolver {
    private let byBundleIdentifier: [String: CatalogApp]
    private let byPath: [String: CatalogApp]

    init(catalog: [CatalogApp]) {
        let ordered = catalog.sorted {
            $0.identity.path.localizedStandardCompare($1.identity.path) == .orderedAscending
        }
        byBundleIdentifier = Dictionary(
            ordered.compactMap { app in app.identity.bundleIdentifier.map { ($0, app) } },
            uniquingKeysWith: { first, _ in first }
        )
        byPath = Dictionary(
            ordered.map { ($0.identity.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func app(for identity: AppIdentity) -> CatalogApp? {
        identity.bundleIdentifier.flatMap { byBundleIdentifier[$0] } ?? byPath[identity.path]
    }
}

public enum LayoutEngine {
    public static func reconcile(
        layout: LayoutDocument,
        catalog: [CatalogApp],
        pageCapacity: Int
    ) -> ReconciledLayout {
        let resolver = CatalogResolver(catalog: catalog)
        let initial = resolve(layout, with: resolver)
        let unplaced = catalog.filter { !initial.placedKeys.contains($0.identity.stableKey) }
        guard !unplaced.isEmpty else {
            return ReconciledLayout(pages: initial.pages, document: layout, appendedApps: [])
        }
        let document = appending(unplaced.map(\.identity), to: layout, pageCapacity: pageCapacity)
        return ReconciledLayout(
            pages: resolve(document, with: resolver).pages,
            document: document,
            appendedApps: unplaced
        )
    }

    public static func appending(
        _ identities: [AppIdentity],
        to document: LayoutDocument,
        pageCapacity: Int
    ) -> LayoutDocument {
        var pages = document.pages.map(\.slots)
        for identity in identities {
            if let last = pages.indices.last, pages[last].count < pageCapacity {
                pages[last].append(.app(identity))
            } else {
                pages.append([.app(identity)])
            }
        }
        return LayoutDocument(
            schemaVersion: document.schemaVersion,
            pages: pages.map { LayoutPage(slots: $0) }
        )
    }

    public static func defaultDocument(catalog: [CatalogApp], pageCapacity: Int) -> LayoutDocument {
        appending(catalog.map(\.identity), to: LayoutDocument(), pageCapacity: pageCapacity)
    }

    private static func resolve(
        _ document: LayoutDocument,
        with resolver: CatalogResolver
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
                    return .app(app)
                case .folder(let folder):
                    let apps = folder.apps.compactMap { resolver.app(for: $0) }
                    placedKeys.formUnion(apps.map(\.identity.stableKey))
                    guard !apps.isEmpty else {
                        return nil
                    }
                    return .folder(ResolvedFolder(id: folder.id, name: folder.name, apps: apps))
                }
            }
            return items.contains { $0 != .empty } ? items : nil
        }
        return (pages, placedKeys)
    }
}
```

- [ ] **Step 7: 运行确认通过**

Run: `swift test --filter LaunchCoreTests 2>&1 | grep -E "error:|failed|Executed [1-9]" | sort -u | tail -3`
Expected: `LaunchCoreTests` 全部通过（原 13 个 − 2 个旧对齐测试 + 8 个新对齐测试 + 1 个编码测试 = 20 个）。

Run: `swift build 2>&1 | grep -E "error:|Build complete" | tail -1`
Expected: `Build complete!`（`LaunchApp` 尚未使用这些接口）。

- [ ] **Step 8: Commit**

```bash
git add Sources/LaunchCore/Models.swift Sources/LaunchCore/LayoutEngine.swift Tests/LaunchCoreTests/LayoutFixtures.swift Tests/LaunchCoreTests/LayoutEngineTests.swift Tests/LaunchCoreTests/ModelsTests.swift
git commit -m "feat(布局): 布局模型支持文件夹并按安装状态对齐"
```

---

### Task 2: 布局文件支持与备份互换

**Files:**
- Modify: `Sources/LaunchCore/LayoutStore.swift`
- Modify: `Tests/LaunchCoreTests/LayoutStoreTests.swift`

- [ ] **Step 1: `LayoutStoreTests` 类内新增失败测试**

```swift
    func testReplaceKeepsPreviousLayoutAsBackup() throws {
        let store = try temporaryStore()
        let original = LayoutDocument(pages: [LayoutPage(slots: [.empty])])
        let replacement = LayoutDocument(pages: [LayoutPage(slots: [.empty, .empty])])
        try store.save(original)

        try store.replace(with: replacement)

        XCTAssertEqual(try store.load(), replacement)
        XCTAssertTrue(store.hasBackup)
    }

    func testSwapWithBackupExchangesLayoutsBothWays() throws {
        let store = try temporaryStore()
        let original = LayoutDocument(pages: [LayoutPage(slots: [.empty])])
        let replacement = LayoutDocument(pages: [LayoutPage(slots: [.empty, .empty])])
        try store.save(original)
        try store.replace(with: replacement)

        try store.swapWithBackup()
        XCTAssertEqual(try store.load(), original)

        try store.swapWithBackup()
        XCTAssertEqual(try store.load(), replacement)
    }

    func testCorruptBackupIsRejectedWithoutTouchingLayout() throws {
        let store = try temporaryStore()
        let original = LayoutDocument(pages: [LayoutPage(slots: [.empty])])
        try store.save(original)
        try Data("not json".utf8).write(to: store.backupURL)

        XCTAssertThrowsError(try store.swapWithBackup())

        XCTAssertEqual(try store.load(), original)
    }

    func testMalformedLayoutFileFailsToLoad() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: store.fileURL)

        XCTAssertThrowsError(try store.load())
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchCoreTests.LayoutStoreTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `value of type 'LayoutStore' has no member 'replace'` 等。

- [ ] **Step 3: 修改 `Sources/LaunchCore/LayoutStore.swift`**

在 `LayoutStoreError` 之后追加：

```swift
extension LayoutStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "布局文件版本 \(version) 不受支持"
        }
    }
}
```

在 `LayoutStore` 的 `init` 之后插入：

```swift
    public var backupURL: URL {
        fileURL.appendingPathExtension("backup")
    }

    public var hasBackup: Bool {
        fileManager.fileExists(atPath: backupURL.path())
    }
```

在 `replaceFromImport` 之后插入：

```swift
    public func replace(with document: LayoutDocument) throws {
        try replaceFromImport(try JSONEncoder().encode(document))
    }

    public func swapWithBackup() throws {
        let backupData = try Data(contentsOf: backupURL)
        _ = try decode(backupData)
        let currentData = try? Data(contentsOf: fileURL)
        try backupData.write(to: fileURL, options: .atomic)
        if let currentData {
            try currentData.write(to: backupURL, options: .atomic)
        } else {
            try fileManager.removeItem(at: backupURL)
        }
    }
```

`writeValidatedData` 中 `let backupURL = fileURL.appendingPathExtension("backup")` 一行删除（改用同名计算属性）。

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter LaunchCoreTests.LayoutStoreTests 2>&1 | grep -E "error:|failed|Executed [1-9]" | sort -u | tail -2`
Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchCore/LayoutStore.swift Tests/LaunchCoreTests/LayoutStoreTests.swift
git commit -m "feat(存储): 布局文件支持与备份互换"
```

---

### Task 3: 只读读取旧 Launchpad 数据库

**Files:**
- Create: `Sources/LaunchCore/LaunchpadSnapshot.swift`
- Create: `Sources/LaunchCore/LaunchpadSnapshotReader.swift`
- Create: `Tests/LaunchCoreTests/LaunchpadSnapshotReaderTests.swift`

- [ ] **Step 1: 写失败测试 `Tests/LaunchCoreTests/LaunchpadSnapshotReaderTests.swift`**

```swift
import Foundation
import SQLite3
import XCTest
@testable import LaunchCore

final class LaunchpadSnapshotReaderTests: XCTestCase {
    private let schema = [
        "CREATE TABLE dbinfo (key VARCHAR, value VARCHAR)",
        "CREATE TABLE items (rowid INTEGER PRIMARY KEY ASC, uuid VARCHAR, flags INTEGER, type INTEGER, parent_id INTEGER NOT NULL, ordering INTEGER)",
        "CREATE TABLE apps (item_id INTEGER PRIMARY KEY, title VARCHAR, bundleid VARCHAR)",
        "CREATE TABLE groups (item_id INTEGER PRIMARY KEY, category_id INTEGER, title VARCHAR)",
    ]

    private var sampleRows: [String] {
        [
            "INSERT INTO dbinfo VALUES ('launchpad_root', '1'), ('launchpad_version_root', '5')",
            "INSERT INTO items (rowid, type, parent_id, ordering) VALUES (1, 1, 0, 0), (5, 1, 0, 0)",
            "INSERT INTO items (rowid, type, parent_id, ordering) VALUES (2, 3, 1, 0), (10, 3, 1, 1), (20, 3, 1, 2)",
            "INSERT INTO items (rowid, type, parent_id, ordering) VALUES (11, 4, 10, 1), (12, 2, 10, 0), (13, 4, 10, 2)",
            "INSERT INTO items (rowid, type, parent_id, ordering) VALUES (14, 3, 12, 0), (15, 4, 14, 0), (16, 4, 14, 1)",
            "INSERT INTO items (rowid, type, parent_id, ordering) VALUES (21, 4, 20, 0), (30, 3, 5, 0), (31, 4, 30, 0)",
            "INSERT INTO apps VALUES (11, '备忘录', 'com.apple.Notes'), (13, 'Safari', 'com.apple.Safari'), (15, '邮件', 'com.apple.mail'), (16, '日历', 'com.apple.iCal'), (21, '国际象棋', 'com.apple.Chess'), (31, '天气', 'com.apple.weather')",
            "INSERT INTO groups VALUES (12, 0, '效率')",
        ]
    }

    func testReadsPagesFoldersAndOrderFromLaunchpadRoot() throws {
        let url = try makeDatabase(schema + sampleRows)

        let snapshot = try LaunchpadSnapshotReader().read(databaseURL: url)

        XCTAssertEqual(snapshot, LaunchpadSnapshot(pages: [
            [],
            [
                .folder(id: 12, name: "效率", apps: [
                    LaunchpadApp(bundleIdentifier: "com.apple.mail", title: "邮件"),
                    LaunchpadApp(bundleIdentifier: "com.apple.iCal", title: "日历"),
                ]),
                .app(LaunchpadApp(bundleIdentifier: "com.apple.Notes", title: "备忘录")),
                .app(LaunchpadApp(bundleIdentifier: "com.apple.Safari", title: "Safari")),
            ],
            [.app(LaunchpadApp(bundleIdentifier: "com.apple.Chess", title: "国际象棋"))],
        ]))
    }

    func testReadingLeavesSourceDirectoryUntouched() throws {
        let url = try makeDatabase(schema + sampleRows)
        let directory = url.deletingLastPathComponent()
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let bytes = try Data(contentsOf: url)

        _ = try LaunchpadSnapshotReader().read(databaseURL: url)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testMissingDatabaseIsReported() throws {
        let url = try temporaryDirectory().appending(path: "db")

        XCTAssertThrowsError(try LaunchpadSnapshotReader().read(databaseURL: url)) { error in
            XCTAssertEqual(error as? LaunchpadReadError, .databaseNotFound)
        }
    }

    func testDatabaseWithoutRootIsReported() throws {
        let url = try makeDatabase(schema)

        XCTAssertThrowsError(try LaunchpadSnapshotReader().read(databaseURL: url)) { error in
            XCTAssertEqual(error as? LaunchpadReadError, .missingRoot)
        }
    }

    func testDatabaseWithoutItemsTableIsReported() throws {
        let url = try makeDatabase([
            "CREATE TABLE dbinfo (key VARCHAR, value VARCHAR)",
            "INSERT INTO dbinfo VALUES ('launchpad_root', '1')",
        ])

        XCTAssertThrowsError(try LaunchpadSnapshotReader().read(databaseURL: url)) { error in
            guard case .queryFailed = error as? LaunchpadReadError else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testDefaultDatabaseLivesInDockLaunchpadFolder() {
        XCTAssertEqual(
            LaunchpadSnapshotReader.defaultDatabaseURL()?.path.hasSuffix("com.apple.dock.launchpad/db/db"),
            true
        )
    }

    private func makeDatabase(_ statements: [String]) throws -> URL {
        let url = try temporaryDirectory().appending(path: "db")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        for sql in statements {
            XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, sql)
        }
        return url
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchCoreTests.LaunchpadSnapshotReaderTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `cannot find 'LaunchpadSnapshotReader' in scope`

- [ ] **Step 3: 创建 `Sources/LaunchCore/LaunchpadSnapshot.swift`**

```swift
public struct LaunchpadApp: Equatable, Sendable {
    public let bundleIdentifier: String
    public let title: String

    public init(bundleIdentifier: String, title: String) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
    }
}

public enum LaunchpadItem: Equatable, Sendable {
    case app(LaunchpadApp)
    case folder(id: Int64, name: String, apps: [LaunchpadApp])
}

public struct LaunchpadSnapshot: Equatable, Sendable {
    public let pages: [[LaunchpadItem]]

    public init(pages: [[LaunchpadItem]]) {
        self.pages = pages
    }
}
```

- [ ] **Step 4: 创建 `Sources/LaunchCore/LaunchpadSnapshotReader.swift`**

```swift
import Foundation
import SQLite3

public enum LaunchpadReadError: Error, Equatable, Sendable {
    case databaseNotFound
    case openFailed(String)
    case queryFailed(String)
    case missingRoot
}

extension LaunchpadReadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            "未找到旧 Launchpad 数据库"
        case .openFailed(let message):
            "无法打开旧 Launchpad 数据库：\(message)"
        case .queryFailed(let message):
            "读取旧 Launchpad 数据库失败：\(message)"
        case .missingRoot:
            "旧 Launchpad 数据库中没有布局根节点"
        }
    }
}

public struct LaunchpadSnapshotReader {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public static func defaultDatabaseURL() -> URL? {
        let length = confstr(_CS_DARWIN_USER_DIR, nil, 0)
        guard length > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_DIR, &buffer, length) > 0 else {
            return nil
        }
        let directory = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return URL(fileURLWithPath: directory, isDirectory: true)
            .appending(path: "com.apple.dock.launchpad/db/db")
    }

    public func read(databaseURL: URL) throws -> LaunchpadSnapshot {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LaunchpadReadError.databaseNotFound
        }
        let workDirectory = fileManager.temporaryDirectory
            .appending(path: "launch-launchpad-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        let copy = workDirectory.appending(path: "db")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: databaseURL.path + suffix)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }
        let database = try SQLiteDatabase(readOnlyAt: copy)
        return try LaunchpadSnapshotQuery(database: database).snapshot()
    }
}

final class SQLiteDatabase {
    private let handle: OpaquePointer

    init(readOnlyAt url: URL) throws {
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite \(status)"
            sqlite3_close(handle)
            throw LaunchpadReadError.openFailed(message)
        }
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }

    func rows(_ sql: String, _ parameter: Int64? = nil) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LaunchpadReadError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        if let parameter {
            sqlite3_bind_int64(statement, 1, parameter)
        }
        var result: [[String?]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                return result
            }
            guard step == SQLITE_ROW else {
                throw LaunchpadReadError.queryFailed(String(cString: sqlite3_errmsg(handle)))
            }
            result.append((0 ..< sqlite3_column_count(statement)).map { index in
                sqlite3_column_text(statement, index).map { String(cString: $0) }
            })
        }
    }
}

struct LaunchpadSnapshotQuery {
    let database: SQLiteDatabase

    func snapshot() throws -> LaunchpadSnapshot {
        let rootRows = try database.rows("SELECT value FROM dbinfo WHERE key = 'launchpad_root'")
        guard let rootText = rootRows.first?.first ?? nil, let root = Int64(rootText) else {
            throw LaunchpadReadError.missingRoot
        }
        return LaunchpadSnapshot(pages: try pageIDs(parent: root).map { try items(page: $0) })
    }

    private func pageIDs(parent: Int64) throws -> [Int64] {
        try database
            .rows("SELECT rowid FROM items WHERE parent_id = ? AND type = 3 ORDER BY ordering", parent)
            .compactMap { row in row.first.flatMap { $0 }.flatMap { Int64($0) } }
    }

    private func items(page: Int64) throws -> [LaunchpadItem] {
        let rows = try database.rows("""
            SELECT items.rowid, items.type, apps.bundleid, apps.title, groups.title
            FROM items
            LEFT JOIN apps ON apps.item_id = items.rowid
            LEFT JOIN groups ON groups.item_id = items.rowid
            WHERE items.parent_id = ?
            ORDER BY items.ordering
            """, page)
        return try rows.compactMap { row in
            guard let id = row[0].flatMap({ Int64($0) }) else {
                return nil
            }
            switch row[1] {
            case "4":
                guard let bundleIdentifier = row[2], !bundleIdentifier.isEmpty else {
                    return nil
                }
                return .app(LaunchpadApp(bundleIdentifier: bundleIdentifier, title: row[3] ?? bundleIdentifier))
            case "2":
                let apps = try pageIDs(parent: id).flatMap { try items(page: $0) }.compactMap { item in
                    if case .app(let app) = item {
                        return app
                    }
                    return nil
                }
                return .folder(id: id, name: row[4] ?? "", apps: apps)
            default:
                return nil
            }
        }
    }
}
```

- [ ] **Step 5: 运行确认通过**

Run: `swift test --filter LaunchCoreTests.LaunchpadSnapshotReaderTests 2>&1 | grep -E "error:|failed|Executed [1-9]" | sort -u | tail -2`
Expected: `Executed 6 tests, with 0 failures`

读取本机真实数据库的冒烟检查放在 Task 10 的离线渲染探针中进行。

- [ ] **Step 6: Commit**

```bash
git add Sources/LaunchCore/LaunchpadSnapshot.swift Sources/LaunchCore/LaunchpadSnapshotReader.swift Tests/LaunchCoreTests/LaunchpadSnapshotReaderTests.swift
git commit -m "feat(导入): 只读读取旧 Launchpad 数据库"
```

---

### Task 4: 将 Launchpad 快照转换为本地布局

**Files:**
- Create: `Sources/LaunchCore/LaunchpadImporter.swift`
- Create: `Tests/LaunchCoreTests/LaunchpadImporterTests.swift`

- [ ] **Step 1: 写失败测试 `Tests/LaunchCoreTests/LaunchpadImporterTests.swift`**

```swift
import XCTest
@testable import LaunchCore

final class LaunchpadImporterTests: XCTestCase {
    private let calendar = layoutApp("Calendar")
    private let chess = layoutApp("Chess")
    private let mail = layoutApp("Mail")
    private let notes = layoutApp("Notes")
    private let zoom = layoutApp("Zoom")

    private func launchpad(_ app: CatalogApp) -> LaunchpadApp {
        LaunchpadApp(bundleIdentifier: app.identity.bundleIdentifier!, title: app.displayName)
    }

    func testImportMapsFoldersMissingAppsAndNewApps() {
        let gone = LaunchpadApp(bundleIdentifier: "com.example.gone", title: "Gone")
        let snapshot = LaunchpadSnapshot(pages: [
            [],
            [
                .folder(id: 12, name: "效率", apps: [launchpad(mail), launchpad(calendar)]),
                .app(launchpad(notes)),
                .app(gone),
            ],
            [.app(launchpad(chess))],
        ])

        let result = LaunchpadImporter.makeImport(
            from: snapshot,
            catalog: [calendar, chess, mail, notes, zoom],
            pageCapacity: 35
        )

        XCTAssertEqual(result.document.pages, [
            LayoutPage(slots: [
                .folder(LayoutFolder(id: "launchpad-12", name: "效率", apps: [mail.identity, calendar.identity])),
                .app(notes.identity),
                .app(AppIdentity(bundleIdentifier: "com.example.gone", path: "")),
            ]),
            LayoutPage(slots: [.app(chess.identity), .app(zoom.identity)]),
        ])
        XCTAssertEqual(result.summary, LaunchpadImportSummary(
            pageCount: 2,
            folderCount: 1,
            appCount: 5,
            installedCount: 4,
            newAppCount: 1
        ))
        XCTAssertEqual(result.summary.missingCount, 1)
    }

    func testDuplicateBundleIdentifierKeepsFirstOccurrence() {
        let snapshot = LaunchpadSnapshot(pages: [[
            .folder(id: 1, name: "A", apps: [launchpad(notes)]),
            .app(launchpad(notes)),
            .folder(id: 2, name: "B", apps: [launchpad(notes)]),
        ]])

        let result = LaunchpadImporter.makeImport(from: snapshot, catalog: [notes], pageCapacity: 35)

        XCTAssertEqual(result.document.pages, [
            LayoutPage(slots: [.folder(LayoutFolder(id: "launchpad-1", name: "A", apps: [notes.identity]))]),
        ])
        XCTAssertEqual(result.summary.folderCount, 1)
        XCTAssertEqual(result.summary.appCount, 1)
    }

    func testOversizedPageIsSplit() {
        let snapshot = LaunchpadSnapshot(pages: [[
            .app(launchpad(calendar)), .app(launchpad(chess)), .app(launchpad(mail)),
        ]])

        let result = LaunchpadImporter.makeImport(
            from: snapshot,
            catalog: [calendar, chess, mail],
            pageCapacity: 2
        )

        XCTAssertEqual(result.document.pages, [
            LayoutPage(slots: [.app(calendar.identity), .app(chess.identity)]),
            LayoutPage(slots: [.app(mail.identity)]),
        ])
        XCTAssertEqual(result.summary.pageCount, 1)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchCoreTests.LaunchpadImporterTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `cannot find 'LaunchpadImporter' in scope`

- [ ] **Step 3: 创建 `Sources/LaunchCore/LaunchpadImporter.swift`**

```swift
public struct LaunchpadImportSummary: Equatable, Sendable {
    public let pageCount: Int
    public let folderCount: Int
    public let appCount: Int
    public let installedCount: Int
    public let newAppCount: Int

    public init(pageCount: Int, folderCount: Int, appCount: Int, installedCount: Int, newAppCount: Int) {
        self.pageCount = pageCount
        self.folderCount = folderCount
        self.appCount = appCount
        self.installedCount = installedCount
        self.newAppCount = newAppCount
    }

    public var missingCount: Int {
        appCount - installedCount
    }
}

public struct LaunchpadImport: Equatable, Sendable {
    public let document: LayoutDocument
    public let summary: LaunchpadImportSummary
}

public enum LaunchpadImporter {
    public static func makeImport(
        from snapshot: LaunchpadSnapshot,
        catalog: [CatalogApp],
        pageCapacity: Int
    ) -> LaunchpadImport {
        let resolver = CatalogResolver(catalog: catalog)
        var seen = Set<String>()
        var installedKeys = Set<String>()
        var folderCount = 0
        var pageCount = 0
        var pages: [[LayoutSlot]] = []

        func identity(for app: LaunchpadApp) -> AppIdentity? {
            guard seen.insert(app.bundleIdentifier).inserted else {
                return nil
            }
            let saved = AppIdentity(bundleIdentifier: app.bundleIdentifier, path: "")
            guard let installed = resolver.app(for: saved) else {
                return saved
            }
            installedKeys.insert(installed.identity.stableKey)
            return installed.identity
        }

        for page in snapshot.pages {
            var slots: [LayoutSlot] = []
            for item in page {
                switch item {
                case .app(let app):
                    if let identity = identity(for: app) {
                        slots.append(.app(identity))
                    }
                case .folder(let id, let name, let apps):
                    let members = apps.compactMap { identity(for: $0) }
                    if !members.isEmpty {
                        folderCount += 1
                        slots.append(.folder(LayoutFolder(id: "launchpad-\(id)", name: name, apps: members)))
                    }
                }
            }
            guard !slots.isEmpty else {
                continue
            }
            pageCount += 1
            pages += stride(from: 0, to: slots.count, by: pageCapacity).map {
                Array(slots[$0 ..< min($0 + pageCapacity, slots.count)])
            }
        }

        let imported = LayoutDocument(pages: pages.map { LayoutPage(slots: $0) })
        let reconciled = LayoutEngine.reconcile(layout: imported, catalog: catalog, pageCapacity: pageCapacity)
        return LaunchpadImport(
            document: reconciled.document,
            summary: LaunchpadImportSummary(
                pageCount: pageCount,
                folderCount: folderCount,
                appCount: seen.count,
                installedCount: installedKeys.count,
                newAppCount: reconciled.appendedApps.count
            )
        )
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter LaunchCoreTests.LaunchpadImporterTests 2>&1 | grep -E "error:|failed|Executed [1-9]" | sort -u | tail -2`
Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchCore/LaunchpadImporter.swift Tests/LaunchCoreTests/LaunchpadImporterTests.swift
git commit -m "feat(导入): 将 Launchpad 快照转换为本地布局"
```

---

### Task 5: 文件夹格子与展开面板尺寸

**Files:**
- Modify: `Sources/LaunchApp/LauncherHomeLayout.swift`
- Modify: `Tests/LaunchAppTests/LauncherHomeLayoutTests.swift`

- [ ] **Step 1: `LauncherHomeLayoutTests` 类内新增失败测试**

```swift
    func testFolderPreviewFitsInsideIcon() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen)

        XCTAssertLessThan(
            layout.folderPreviewIconSide * 3 + layout.folderPreviewSpacing * 2,
            layout.iconSide
        )
    }

    func testFolderRowCountCapsAtFiveRows() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen)

        XCTAssertEqual(layout.folderRowCount(memberCount: 0), 1)
        XCTAssertEqual(layout.folderRowCount(memberCount: 8), 2)
        XCTAssertEqual(layout.folderRowCount(memberCount: 29), 5)
        XCTAssertEqual(layout.folderRowCount(memberCount: 40), 5)
    }

    func testFullFolderPanelFitsOnEveryScreen() {
        for screen in [mainScreen, CGSize(width: 1920, height: 1080), CGSize(width: 1504, height: 846)] {
            let layout = LauncherHomeLayout(screenSize: screen, referenceSize: mainScreen)
            let usedHeight = layout.folderTitleHeight
                + layout.folderTitleSpacing
                + layout.folderGridHeight(memberCount: 35)
                + layout.folderPanelPadding * 2

            XCTAssertLessThanOrEqual(usedHeight, layout.contentSize.height, "\(screen)")
        }
    }

    func testFolderPanelExtendsBeyondGridColumns() {
        let layout = LauncherHomeLayout(screenSize: mainScreen, referenceSize: mainScreen)

        XCTAssertEqual(layout.horizontalInset - layout.folderPanelOutset, 94.08, accuracy: 0.01)
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchAppTests.LauncherHomeLayoutTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `has no member 'folderPreviewIconSide'`

- [ ] **Step 3: `LauncherHomeLayout` 末尾（`bottomInset` 之后）追加**

```swift
    var folderCornerRadius: CGFloat { iconSide * 0.225 }
    var folderPreviewIconSide: CGFloat { iconSide * 0.19 }
    var folderPreviewSpacing: CGFloat { iconSide * 0.065 }
    var folderPanelOutset: CGFloat { 42 * sizeScale }
    var folderPanelPadding: CGFloat { 30 * sizeScale }
    var folderPanelCornerRadius: CGFloat { 36 * sizeScale }
    var folderTitleFontSize: CGFloat { 22 * sizeScale }
    var folderTitleHeight: CGFloat { 28 * sizeScale }
    var folderTitleSpacing: CGFloat { 30 * sizeScale }

    func folderRowCount(memberCount: Int) -> Int {
        let rows = (memberCount + Self.columnCount - 1) / Self.columnCount
        return min(max(rows, 1), Self.rowCount)
    }

    func folderGridHeight(memberCount: Int) -> CGFloat {
        let rows = CGFloat(folderRowCount(memberCount: memberCount))
        return tileHeight * rows + rowSpacing * (rows - 1)
    }
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter LaunchAppTests.LauncherHomeLayoutTests 2>&1 | grep -E "error:|failed|Executed [1-9]" | sort -u | tail -2`
Expected: `Executed 10 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchApp/LauncherHomeLayout.swift Tests/LaunchAppTests/LauncherHomeLayoutTests.swift
git commit -m "feat(界面): 添加文件夹格子与展开面板尺寸"
```

---

### Task 6: 按布局显示应用与文件夹

**Files:**
- Modify: `Sources/LaunchApp/LauncherModel.swift`
- Modify: `Sources/LaunchApp/LauncherView.swift`
- Modify: `Tests/LaunchAppTests/TestFixtures.swift`
- Modify: `Tests/LaunchAppTests/LauncherModelTests.swift`

- [ ] **Step 1: `TestFixtures.swift` 追加**

```swift
func makeFolder(id: String, name: String, apps: [CatalogApp]) -> ResolvedItem {
    .folder(ResolvedFolder(id: id, name: name, apps: apps))
}
```

- [ ] **Step 2: 修改 `LauncherModelTests`（失败测试）**

`testSelectPageClampsToAvailablePages` 与 `testUpdateAppsClampsPage` 中的 `model.visibleApps.count` 改为 `model.visibleItems.count`。类内追加：

```swift
    @MainActor
    func testLayoutPagesDriveBrowsing() {
        let apps = makeApps(count: 2)
        let model = LauncherModel(apps: apps)

        model.updateLayout([[.app(apps[1])], [.app(apps[0])]])

        XCTAssertEqual(model.pages.count, 2)
        XCTAssertEqual(model.visibleItems, [.app(apps[1])])
    }

    @MainActor
    func testSearchFindsAppsInsideFolders() {
        let apps = makeApps(count: 2)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: [apps[1]])]])

        model.setQuery("App 1")

        XCTAssertEqual(model.visibleItems, [.app(apps[1])])
    }

    @MainActor
    func testOpenFolderResolvesFromLayout() {
        let apps = makeApps(count: 1)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])

        model.showFolder(id: "f")

        XCTAssertEqual(model.openFolder?.name, "效率")
    }

    @MainActor
    func testEscapeClosesFolderThenQueryThenLauncher() {
        let apps = makeApps(count: 1)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.showFolder(id: "f")

        XCTAssertEqual(model.handleEscape(), .closedFolder)
        XCTAssertNil(model.openFolderID)
        model.setQuery("App")
        XCTAssertEqual(model.handleEscape(), .clearedQuery)
        XCTAssertEqual(model.handleEscape(), .close)
    }

    @MainActor
    func testTypingPresentingAndPagingCloseFolder() {
        let apps = makeApps(count: 1)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])

        model.showFolder(id: "f")
        model.setQuery("A")
        XCTAssertNil(model.openFolderID)

        model.setQuery("")
        model.showFolder(id: "f")
        model.prepareForPresentation()
        XCTAssertNil(model.openFolderID)

        model.showFolder(id: "f")
        model.selectPage(0)
        XCTAssertNil(model.openFolderID)
    }

    @MainActor
    func testUpdateLayoutDropsVanishedFolder() {
        let apps = makeApps(count: 1)
        let model = LauncherModel(apps: apps)
        model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])
        model.showFolder(id: "f")

        model.updateLayout([[.app(apps[0])]])

        XCTAssertNil(model.openFolderID)
    }
```

- [ ] **Step 3: 运行确认失败**

Run: `swift test --filter LaunchAppTests.LauncherModelTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `has no member 'visibleItems'` 等。

- [ ] **Step 4: 重写 `Sources/LaunchApp/LauncherModel.swift`**

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
    private(set) var presentationCount = 0
    private(set) var openFolderID: String?

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

    func setQuery(_ newQuery: String) {
        guard newQuery != query else {
            return
        }
        query = newQuery
        currentPage = 0
        if !newQuery.isEmpty {
            openFolderID = nil
        }
    }

    func selectPage(_ index: Int) {
        openFolderID = nil
        currentPage = clampedPage(index)
    }

    func showFolder(id: String) {
        openFolderID = id
    }

    func closeFolder() {
        openFolderID = nil
    }

    func prepareForPresentation() {
        openFolderID = nil
        setQuery("")
        currentPage = clampedPage(currentPage)
        presentationCount += 1
    }

    func handleEscape() -> EscapeOutcome {
        if openFolderID != nil {
            openFolderID = nil
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
        currentPage = clampedPage(currentPage)
    }

    func updateLayout(_ pages: [[ResolvedItem]]) {
        layoutPages = pages
        currentPage = clampedPage(currentPage)
        if openFolderID != nil, openFolder == nil {
            openFolderID = nil
        }
    }

    private func clampedPage(_ index: Int) -> Int {
        LauncherPagination.normalizedPageIndex(index, pageCount: pages.count)
    }
}
```

- [ ] **Step 5: 修改 `LauncherView.swift` 的网格渲染**

`homeContent(layout:)` 开头的 `let columns = Array(...)`（4 行）替换为：

```swift
        let columns = gridColumns(layout)
```

`if model.visibleApps.isEmpty {` 改为 `if model.visibleItems.isEmpty {`；网格内

```swift
                    ForEach(model.visibleApps, id: \.identity) { app in
                        LauncherAppTile(app: app, layout: layout) {
                            onLaunch(app)
                        }
                    }
```

替换为：

```swift
                    ForEach(Array(model.visibleItems.enumerated()), id: \.offset) { _, item in
                        itemView(item, layout: layout)
                    }
```

在 `searchBar(layout:)` 之前插入：

```swift
    private func gridColumns(_ layout: LauncherHomeLayout) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(layout.tileWidth), spacing: layout.columnSpacing),
            count: LauncherHomeLayout.columnCount
        )
    }

    @ViewBuilder
    private func itemView(_ item: ResolvedItem, layout: LauncherHomeLayout) -> some View {
        switch item {
        case .app(let app):
            LauncherAppTile(app: app, layout: layout) {
                onLaunch(app)
            }
        case .folder(let folder):
            LauncherFolderTile(folder: folder, layout: layout) {
                model.showFolder(id: folder.id)
            }
        case .empty:
            Color.clear
                .frame(width: layout.tileWidth, height: layout.tileHeight)
        }
    }
```

文件末尾追加：

```swift
private struct LauncherFolderTile: View {
    let folder: ResolvedFolder
    let layout: LauncherHomeLayout
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: layout.iconLabelSpacing) {
                FolderPreview(apps: Array(folder.apps.prefix(9)), layout: layout)
                Text(folder.name)
                    .font(.system(size: layout.labelFontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
                    .lineLimit(1)
                    .frame(maxWidth: layout.tileWidth)
                    .frame(height: layout.labelHeight)
            }
            .padding(.vertical, layout.tilePadding)
            .frame(width: layout.tileWidth)
            .background {
                RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.15 : 0))
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .accessibilityLabel(folder.name)
    }
}

private struct FolderPreview: View {
    let apps: [CatalogApp]
    let layout: LauncherHomeLayout

    var body: some View {
        let side = layout.folderPreviewIconSide
        let spacing = layout.folderPreviewSpacing
        let gridSide = side * 3 + spacing * 2
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: 3),
            spacing: spacing
        ) {
            ForEach(apps, id: \.identity) { app in
                Image(nsImage: IconCache.shared.icon(for: app.identity.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
            }
        }
        .frame(width: gridSide, height: gridSide, alignment: .top)
        .frame(width: layout.iconSide, height: layout.iconSide)
        .background {
            RoundedRectangle(cornerRadius: layout.folderCornerRadius, style: .continuous)
                .fill(.white.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: layout.folderCornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
        }
    }
}
```

- [ ] **Step 6: 运行确认通过并全量测试**

Run: `swift build 2>&1 | grep -E "error:|Build complete" | tail -1 && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -3`
Expected: `Build complete!`；全部测试 0 failures。

- [ ] **Step 7: Commit**

```bash
git add Sources/LaunchApp/LauncherModel.swift Sources/LaunchApp/LauncherView.swift Tests/LaunchAppTests/TestFixtures.swift Tests/LaunchAppTests/LauncherModelTests.swift
git commit -m "feat(界面): 按布局显示应用与文件夹"
```

---

### Task 7: 展开文件夹并支持分层关闭

**Files:**
- Modify: `Sources/LaunchApp/LauncherController.swift`
- Modify: `Sources/LaunchApp/LauncherView.swift`
- Modify: `Sources/LaunchApp/LaunchApp.swift`
- Modify: `Tests/LaunchAppTests/LauncherControllerTests.swift`

- [ ] **Step 1: `LauncherControllerTests` 类内新增失败测试**

```swift
    @MainActor
    func testBackgroundClickClosesOpenFolderBeforeLauncher() {
        let apps = makeApps(count: 1)
        let (controller, presenter) = makeController(apps: apps)
        controller.model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])
        controller.show()
        controller.model.showFolder(id: "f")

        controller.handleBackgroundClick()
        XCTAssertTrue(presenter.isVisible)
        XCTAssertNil(controller.model.openFolderID)

        controller.handleBackgroundClick()
        XCTAssertEqual(presenter.dismissals, [true])
    }

    @MainActor
    func testEscapeClosesFolderBeforeHiding() {
        let apps = makeApps(count: 1)
        let (controller, presenter) = makeController(apps: apps)
        controller.model.updateLayout([[makeFolder(id: "f", name: "效率", apps: apps)]])
        controller.show()
        controller.model.showFolder(id: "f")

        controller.handleEscape()
        XCTAssertTrue(presenter.isVisible)

        controller.handleEscape()
        XCTAssertEqual(presenter.dismissals, [true])
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchAppTests.LauncherControllerTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `has no member 'handleBackgroundClick'`

- [ ] **Step 3: `LauncherController` 在 `handleEscape()` 之后插入**

```swift
    func handleBackgroundClick() {
        if model.openFolderID != nil {
            model.closeFolder()
        } else {
            hide(.backgroundClick)
        }
    }
```

- [ ] **Step 4: `LauncherView.body` 加入文件夹展开**

`body` 中的

```swift
                homeContent(layout: layout)
                    .frame(width: layout.contentSize.width, height: layout.contentSize.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
```

替换为：

```swift
                homeContent(layout: layout)
                    .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                    .opacity(model.openFolder == nil ? 1 : 0)
                    .allowsHitTesting(model.openFolder == nil)

                if let folder = model.openFolder {
                    FolderOverlay(
                        folder: folder,
                        layout: layout,
                        columns: gridColumns(layout),
                        onLaunch: onLaunch
                    )
                    .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.2), value: model.openFolderID)
```

文件末尾追加：

```swift
private struct FolderOverlay: View {
    let folder: ResolvedFolder
    let layout: LauncherHomeLayout
    let columns: [GridItem]
    let onLaunch: (CatalogApp) -> Void

    var body: some View {
        VStack(spacing: layout.folderTitleSpacing) {
            Text(folder.name)
                .font(.system(size: layout.folderTitleFontSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(height: layout.folderTitleHeight)
            members
                .frame(height: layout.folderGridHeight(memberCount: folder.apps.count), alignment: .top)
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
        }
    }

    @ViewBuilder
    private var members: some View {
        let grid = LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
            ForEach(folder.apps, id: \.identity) { app in
                LauncherAppTile(app: app, layout: layout) {
                    onLaunch(app)
                }
            }
        }
        .padding(.horizontal, layout.horizontalInset)

        if folder.apps.count > LauncherHomeLayout.pageCapacity {
            ScrollView(.vertical, showsIndicators: false) {
                grid
            }
        } else {
            grid
        }
    }
}
```

- [ ] **Step 5: `LaunchApp.swift` 中点击背景改走控制器**

```swift
                onBackgroundClick: { [weak self] in self?.controller.hide(.backgroundClick) },
```

改为：

```swift
                onBackgroundClick: { [weak self] in self?.controller.handleBackgroundClick() },
```

- [ ] **Step 6: 运行确认通过**

Run: `swift build 2>&1 | grep -E "error:|Build complete" | tail -1 && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -3`
Expected: `Build complete!`；全部测试 0 failures。

- [ ] **Step 7: Commit**

```bash
git add Sources/LaunchApp/LauncherController.swift Sources/LaunchApp/LauncherView.swift Sources/LaunchApp/LaunchApp.swift Tests/LaunchAppTests/LauncherControllerTests.swift
git commit -m "feat(界面): 展开文件夹并支持分层关闭"
```

---

### Task 8: 协调布局加载、首次导入与恢复

**Files:**
- Create: `Sources/LaunchApp/LayoutCoordinator.swift`
- Create: `Tests/LaunchAppTests/LayoutCoordinatorTests.swift`

- [ ] **Step 1: 写失败测试 `Tests/LaunchAppTests/LayoutCoordinatorTests.swift`**

```swift
import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
private final class FakePrompter: LayoutPrompting {
    var answer = true
    private(set) var firstImportSummaries: [LaunchpadImportSummary] = []
    private(set) var reimportSummaries: [LaunchpadImportSummary] = []
    private(set) var restoreRequests = 0
    private(set) var errors: [String] = []

    func confirmFirstImport(_ summary: LaunchpadImportSummary) -> Bool {
        firstImportSummaries.append(summary)
        return answer
    }

    func confirmReimport(_ summary: LaunchpadImportSummary) -> Bool {
        reimportSummaries.append(summary)
        return answer
    }

    func confirmRestore() -> Bool {
        restoreRequests += 1
        return answer
    }

    func showError(_ message: String) {
        errors.append(message)
    }
}

private struct FakeLaunchpad: LaunchpadSource {
    var isAvailable = true
    var snapshot = LaunchpadSnapshot(pages: [])
    var failure: LaunchpadReadError?

    func readSnapshot() async throws -> LaunchpadSnapshot {
        if let failure {
            throw failure
        }
        return snapshot
    }
}

final class LayoutCoordinatorTests: XCTestCase {
    private let apps = makeApps(count: 3)

    private func launchpadApp(_ app: CatalogApp) -> LaunchpadApp {
        LaunchpadApp(bundleIdentifier: app.identity.bundleIdentifier!, title: app.displayName)
    }

    @MainActor
    func testFirstLaunchImportsLaunchpadLayoutAfterConfirmation() async throws {
        let store = try temporaryStore()
        let prompter = FakePrompter()
        let snapshot = LaunchpadSnapshot(pages: [[
            .folder(id: 7, name: "效率", apps: [launchpadApp(apps[0])]),
            .app(launchpadApp(apps[1])),
        ]])
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad(snapshot: snapshot))

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertEqual(prompter.firstImportSummaries.count, 1)
        XCTAssertEqual(published.last, [[
            makeFolder(id: "launchpad-7", name: "效率", apps: [apps[0]]),
            .app(apps[1]),
            .app(apps[2]),
        ]])
        XCTAssertEqual(try store.load()?.pages.first?.slots.count, 3)
    }

    @MainActor
    func testDecliningFirstImportSavesDefaultLayout() async throws {
        let store = try temporaryStore()
        let prompter = FakePrompter()
        prompter.answer = false
        let snapshot = LaunchpadSnapshot(pages: [[.folder(id: 7, name: "效率", apps: [launchpadApp(apps[0])])]])
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad(snapshot: snapshot))

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertEqual(published.last, [apps.map(ResolvedItem.app)])
        XCTAssertEqual(try store.load(), LayoutEngine.defaultDocument(catalog: apps, pageCapacity: 35))
    }

    @MainActor
    func testFirstLaunchWithoutLaunchpadUsesDefaultSilently() async throws {
        let store = try temporaryStore()
        let prompter = FakePrompter()
        let (coordinator, _) = makeCoordinator(store, prompter, FakeLaunchpad(isAvailable: false))

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertTrue(prompter.firstImportSummaries.isEmpty)
        XCTAssertNotNil(try store.load())
    }

    @MainActor
    func testReadFailureDuringFirstLaunchFallsBackToDefault() async throws {
        let store = try temporaryStore()
        let prompter = FakePrompter()
        let (coordinator, _) = makeCoordinator(store, prompter, FakeLaunchpad(failure: .missingRoot))

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertEqual(prompter.errors.count, 1)
        XCTAssertEqual(try store.load(), LayoutEngine.defaultDocument(catalog: apps, pageCapacity: 35))
    }

    @MainActor
    func testExistingLayoutAppendsNewAppsAndSaves() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: [.app(apps[2].identity)])]))
        let prompter = FakePrompter()
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad())

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertTrue(prompter.firstImportSummaries.isEmpty)
        XCTAssertEqual(published.last, [[.app(apps[2]), .app(apps[0]), .app(apps[1])]])
        XCTAssertEqual(try store.load()?.pages.first?.slots.count, 3)
    }

    @MainActor
    func testCorruptLayoutIsLeftUntouched() async throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: store.fileURL)
        let prompter = FakePrompter()
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad())

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertEqual(prompter.errors.count, 1)
        XCTAssertTrue(prompter.firstImportSummaries.isEmpty)
        XCTAssertEqual(published.last, [apps.map(ResolvedItem.app)])
        XCTAssertEqual(try Data(contentsOf: store.fileURL), Data("not json".utf8))
    }

    @MainActor
    func testReimportBacksUpAndRestoreSwapsBack() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: [.app(apps[2].identity)])]))
        let prompter = FakePrompter()
        let snapshot = LaunchpadSnapshot(pages: [[.app(launchpadApp(apps[0]))]])
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad(snapshot: snapshot))
        coordinator.start()
        await coordinator.catalogDidChange(apps)

        await coordinator.importFromLaunchpad()

        XCTAssertEqual(prompter.reimportSummaries.count, 1)
        XCTAssertTrue(coordinator.canRestore)
        XCTAssertEqual(published.last, [[.app(apps[0]), .app(apps[1]), .app(apps[2])]])

        coordinator.restoreBackup()

        XCTAssertEqual(prompter.restoreRequests, 1)
        XCTAssertEqual(published.last, [[.app(apps[2]), .app(apps[0]), .app(apps[1])]])
    }

    @MainActor
    private func makeCoordinator(
        _ store: LayoutStore,
        _ prompter: FakePrompter,
        _ launchpad: FakeLaunchpad
    ) -> (LayoutCoordinator, PublishedPages) {
        let published = PublishedPages()
        let coordinator = LayoutCoordinator(store: store, launchpad: launchpad, prompter: prompter)
        coordinator.onLayoutChange = { published.values.append($0) }
        return (coordinator, published)
    }

    private func temporaryStore() throws -> LayoutStore {
        LayoutStore(fileURL: try makeTemporaryDirectory().appending(path: "Launch/layout.json"))
    }
}

@MainActor
private final class PublishedPages {
    var values: [[[ResolvedItem]]] = []
    var last: [[ResolvedItem]]? { values.last }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchAppTests.LayoutCoordinatorTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `cannot find type 'LayoutPrompting' in scope`

- [ ] **Step 3: 创建 `Sources/LaunchApp/LayoutCoordinator.swift`**

```swift
import Foundation
import LaunchCore

@MainActor
protocol LayoutPrompting: AnyObject {
    func confirmFirstImport(_ summary: LaunchpadImportSummary) -> Bool
    func confirmReimport(_ summary: LaunchpadImportSummary) -> Bool
    func confirmRestore() -> Bool
    func showError(_ message: String)
}

protocol LaunchpadSource: Sendable {
    var isAvailable: Bool { get }
    func readSnapshot() async throws -> LaunchpadSnapshot
}

@MainActor
final class LayoutCoordinator {
    static var defaultLayoutURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Launch/layout.json")
    }

    var onLayoutChange: (([[ResolvedItem]]) -> Void)?

    private let store: LayoutStore
    private let launchpad: LaunchpadSource
    private let prompter: LayoutPrompting
    private let pageCapacity: Int
    private var document: LayoutDocument?
    private var catalog: [CatalogApp] = []
    private var needsSetup = false
    private var isSettingUp = false
    private var isReadOnly = false
    private var hasReportedSaveError = false

    init(
        store: LayoutStore,
        launchpad: LaunchpadSource,
        prompter: LayoutPrompting,
        pageCapacity: Int = LauncherHomeLayout.pageCapacity
    ) {
        self.store = store
        self.launchpad = launchpad
        self.prompter = prompter
        self.pageCapacity = pageCapacity
    }

    var canImport: Bool {
        launchpad.isAvailable
    }

    var canRestore: Bool {
        store.hasBackup
    }

    func start() {
        do {
            document = try store.load()
            needsSetup = document == nil
        } catch {
            isReadOnly = true
            prompter.showError("布局文件无法读取，暂时按名称排列；文件保持原样。")
        }
    }

    func catalogDidChange(_ apps: [CatalogApp]) async {
        catalog = apps
        guard !isSettingUp else {
            return
        }
        if needsSetup {
            isSettingUp = true
            await runFirstSetup()
            needsSetup = false
            isSettingUp = false
        }
        publish()
    }

    func importFromLaunchpad() async {
        do {
            let snapshot = try await launchpad.readSnapshot()
            let result = LaunchpadImporter.makeImport(from: snapshot, catalog: catalog, pageCapacity: pageCapacity)
            guard prompter.confirmReimport(result.summary) else {
                return
            }
            try store.replace(with: result.document)
            document = result.document
            isReadOnly = false
            needsSetup = false
            publish()
        } catch {
            prompter.showError("导入失败：\(error.localizedDescription)")
        }
    }

    func restoreBackup() {
        guard prompter.confirmRestore() else {
            return
        }
        do {
            try store.swapWithBackup()
            document = try store.load()
            isReadOnly = false
            needsSetup = false
            publish()
        } catch {
            prompter.showError("恢复失败：\(error.localizedDescription)")
        }
    }

    private func runFirstSetup() async {
        var imported: LayoutDocument?
        if launchpad.isAvailable {
            do {
                let snapshot = try await launchpad.readSnapshot()
                let result = LaunchpadImporter.makeImport(from: snapshot, catalog: catalog, pageCapacity: pageCapacity)
                if prompter.confirmFirstImport(result.summary) {
                    imported = result.document
                }
            } catch {
                prompter.showError(error.localizedDescription)
            }
        }
        let document = imported ?? LayoutEngine.defaultDocument(catalog: catalog, pageCapacity: pageCapacity)
        self.document = document
        save(document)
    }

    private func publish() {
        guard let document else {
            let fallback = LayoutEngine.defaultDocument(catalog: catalog, pageCapacity: pageCapacity)
            onLayoutChange?(LayoutEngine.reconcile(layout: fallback, catalog: catalog, pageCapacity: pageCapacity).pages)
            return
        }
        let reconciled = LayoutEngine.reconcile(layout: document, catalog: catalog, pageCapacity: pageCapacity)
        if !reconciled.appendedApps.isEmpty {
            self.document = reconciled.document
            save(reconciled.document)
        }
        onLayoutChange?(reconciled.pages)
    }

    private func save(_ document: LayoutDocument) {
        guard !isReadOnly else {
            return
        }
        do {
            try store.save(document)
        } catch {
            guard !hasReportedSaveError else {
                return
            }
            hasReportedSaveError = true
            prompter.showError("保存布局失败：\(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter LaunchAppTests.LayoutCoordinatorTests 2>&1 | grep -E "error:|failed|Executed [1-9]" | sort -u | tail -2`
Expected: `Executed 7 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchApp/LayoutCoordinator.swift Tests/LaunchAppTests/LayoutCoordinatorTests.swift
git commit -m "feat(布局): 协调布局加载、首次导入与恢复"
```

---

### Task 9: 菜单入口、提示框与组装

**Files:**
- Create: `Sources/LaunchApp/LayoutPrompts.swift`
- Create: `Tests/LaunchAppTests/LayoutPromptTextTests.swift`
- Modify: `Sources/LaunchApp/StatusItemController.swift`
- Modify: `Sources/LaunchApp/LaunchApp.swift`

- [ ] **Step 1: 写失败测试 `Tests/LaunchAppTests/LayoutPromptTextTests.swift`**

```swift
import LaunchCore
import XCTest
@testable import LaunchApp

final class LayoutPromptTextTests: XCTestCase {
    func testSummaryMentionsMissingAndNewApps() {
        let summary = LaunchpadImportSummary(pageCount: 2, folderCount: 3, appCount: 96, installedCount: 81, newAppCount: 25)

        XCTAssertEqual(
            LayoutPromptText.summary(summary),
            "旧 Launchpad 布局：2 页、3 个文件夹、96 个应用。已安装 81 个；未安装 15 个，会保留位置，重新安装后回到原处。另有 25 个新应用会排在最后。"
        )
    }

    func testSummaryOmitsZeroCounts() {
        let summary = LaunchpadImportSummary(pageCount: 1, folderCount: 0, appCount: 4, installedCount: 4, newAppCount: 0)

        XCTAssertEqual(
            LayoutPromptText.summary(summary),
            "旧 Launchpad 布局：1 页、0 个文件夹、4 个应用。已安装 4 个。"
        )
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchAppTests.LayoutPromptTextTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `cannot find 'LayoutPromptText' in scope`

- [ ] **Step 3: 创建 `Sources/LaunchApp/LayoutPrompts.swift`**

```swift
import AppKit
import LaunchCore

enum LayoutPromptText {
    static func summary(_ summary: LaunchpadImportSummary) -> String {
        var text = "旧 Launchpad 布局：\(summary.pageCount) 页、\(summary.folderCount) 个文件夹、\(summary.appCount) 个应用。已安装 \(summary.installedCount) 个"
        if summary.missingCount > 0 {
            text += "；未安装 \(summary.missingCount) 个，会保留位置，重新安装后回到原处"
        }
        text += "。"
        if summary.newAppCount > 0 {
            text += "另有 \(summary.newAppCount) 个新应用会排在最后。"
        }
        return text
    }
}

@MainActor
final class AlertLayoutPrompter: LayoutPrompting {
    func confirmFirstImport(_ summary: LaunchpadImportSummary) -> Bool {
        ask(
            title: "导入旧 Launchpad 布局？",
            message: LayoutPromptText.summary(summary),
            confirm: "导入",
            cancel: "暂不"
        )
    }

    func confirmReimport(_ summary: LaunchpadImportSummary) -> Bool {
        ask(
            title: "从 Launchpad 重新导入布局？",
            message: LayoutPromptText.summary(summary) + "\n\n会覆盖当前布局，覆盖前自动备份。",
            confirm: "导入",
            cancel: "取消"
        )
    }

    func confirmRestore() -> Bool {
        ask(
            title: "恢复导入前的布局？",
            message: "当前布局会与备份互换，再次恢复即可换回。",
            confirm: "恢复",
            cancel: "取消"
        )
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "布局"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func ask(title: String, message: String, confirm: String, cancel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

struct LiveLaunchpadSource: LaunchpadSource {
    let databaseURL: URL?

    var isAvailable: Bool {
        databaseURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func readSnapshot() async throws -> LaunchpadSnapshot {
        guard let databaseURL else {
            throw LaunchpadReadError.databaseNotFound
        }
        return try LaunchpadSnapshotReader().read(databaseURL: databaseURL)
    }
}
```

- [ ] **Step 4: 修改 `StatusItemController.swift`**

文件开头（`StatusItemController` 之前）插入：

```swift
struct LayoutMenuActions {
    let canImport: () -> Bool
    let importLayout: () -> Void
    let canRestore: () -> Bool
    let restoreLayout: () -> Void
}
```

属性区 `quitItem` 之前插入：

```swift
    private let importItem = NSMenuItem(title: "从 Launchpad 导入布局…", action: nil, keyEquivalent: "")
    private let restoreItem = NSMenuItem(title: "恢复导入前的布局", action: nil, keyEquivalent: "")
    private let layoutMenu: LayoutMenuActions
```

`init` 签名增加参数并赋值：

```swift
    init(
        loginItemService: LoginItemService,
        layoutMenu: LayoutMenuActions,
        hasHotKeyConflict: @escaping () -> Bool,
        onOpen: @escaping () -> Void
    ) {
        self.loginItemService = loginItemService
        self.layoutMenu = layoutMenu
```

`quitItem.action = #selector(quit)` 之前插入：

```swift
        importItem.action = #selector(importLayout)
        importItem.target = self
        restoreItem.action = #selector(restoreLayout)
        restoreItem.target = self
```

菜单项数组改为：

```swift
        menu.items = [openItem, conflictItem, .separator(), loginItem, importItem, restoreItem, .separator(), quitItem]
```

`menuNeedsUpdate` 末尾追加：

```swift
        importItem.isEnabled = layoutMenu.canImport()
        restoreItem.isEnabled = layoutMenu.canRestore()
```

`quit()` 之前插入：

```swift
    @objc private func importLayout() {
        layoutMenu.importLayout()
    }

    @objc private func restoreLayout() {
        layoutMenu.restoreLayout()
    }
```

- [ ] **Step 5: 修改 `LaunchApp.swift` 组装协调器**

`private var statusItemController` 之前插入：

```swift
    private lazy var layoutCoordinator = LayoutCoordinator(
        store: LayoutStore(fileURL: LayoutCoordinator.defaultLayoutURL),
        launchpad: LiveLaunchpadSource(databaseURL: LaunchpadSnapshotReader.defaultDatabaseURL()),
        prompter: AlertLayoutPrompter()
    )
```

`HotKeyService.register` 之前插入：

```swift
        layoutCoordinator.onLayoutChange = { [weak self] pages in
            self?.controller.model.updateLayout(pages)
        }
        layoutCoordinator.start()
```

`StatusItemController(` 调用改为：

```swift
        statusItemController = StatusItemController(
            loginItemService: loginItemService,
            layoutMenu: LayoutMenuActions(
                canImport: { [weak self] in self?.layoutCoordinator.canImport ?? false },
                importLayout: { [weak self] in
                    Task { await self?.layoutCoordinator.importFromLaunchpad() }
                },
                canRestore: { [weak self] in self?.layoutCoordinator.canRestore ?? false },
                restoreLayout: { [weak self] in self?.layoutCoordinator.restoreBackup() }
            ),
            hasHotKeyConflict: { [weak self] in self?.hasHotKeyConflict() ?? false },
            onOpen: { [weak self] in self?.controller.show() }
        )
```

`CatalogWatcher` 回调改为：

```swift
        let watcher = CatalogWatcher(roots: ApplicationSources.defaultRoots()) { [weak self] apps in
            self?.controller.updateCatalog(apps)
            Task { await self?.layoutCoordinator.catalogDidChange(apps) }
        }
```

- [ ] **Step 6: 运行确认通过**

Run: `swift build 2>&1 | grep -E "error:|warning:|Build complete" | tail -3 && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -3`
Expected: `Build complete!`，无新警告；全部测试 0 failures。

- [ ] **Step 7: Commit**

```bash
git add Sources/LaunchApp/LayoutPrompts.swift Sources/LaunchApp/StatusItemController.swift Sources/LaunchApp/LaunchApp.swift Tests/LaunchAppTests/LayoutPromptTextTests.swift
git commit -m "feat(菜单栏): 添加布局导入与恢复入口"
```

---

### Task 10: 离线渲染、安装与端到端验证

**Files:**
- Create（临时，不提交）: `Tests/LaunchAppTests/LayoutSnapshotProbe.swift`
- Modify: `docs/manual-verification.md`、`README.md`、`docs/architecture.md`

- [ ] **Step 1: 临时探针：读取本机真实库并渲染**

```swift
import AppKit
import LaunchCore
import SwiftUI
import XCTest
@testable import LaunchApp

final class LayoutSnapshotProbe: XCTestCase {
    @MainActor
    func testRenderImportedLayout() throws {
        let apps = try AppCatalog().scan(roots: ApplicationSources.defaultRoots())
        let url = try XCTUnwrap(LaunchpadSnapshotReader.defaultDatabaseURL())
        let snapshot = try LaunchpadSnapshotReader().read(databaseURL: url)
        let imported = LaunchpadImporter.makeImport(from: snapshot, catalog: apps, pageCapacity: 35)
        print("PROBE summary=\(LayoutPromptText.summary(imported.summary))")
        let reconciled = LayoutEngine.reconcile(layout: imported.document, catalog: apps, pageCapacity: 35)
        let model = LauncherModel(apps: apps)
        model.updateLayout(reconciled.pages)
        print("PROBE pages=\(model.pages.map(\.count))")

        let folders = reconciled.pages.joined().compactMap { item -> ResolvedFolder? in
            if case .folder(let folder) = item { return folder }
            return nil
        }
        let states: [(String, String?)] = [("grid", nil)] + folders.map { ($0.name, $0.id) }
        for size in [CGSize(width: 1512, height: 982), CGSize(width: 1920, height: 1080), CGSize(width: 1504, height: 846)] {
            for (name, folderID) in states {
                if let folderID { model.showFolder(id: folderID) } else { model.closeFolder() }
                let view = LauncherView(model: model, onEscape: {}, onBackgroundClick: {}, onLaunch: { _ in })
                    .frame(width: size.width, height: size.height)
                    .background(Color(white: 0.25))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: "/tmp/launch-folder-\(Int(size.width))x\(Int(size.height))-\(name).png"))
            }
        }
    }
}
```

Run: `swift test --filter LaunchAppTests.LayoutSnapshotProbe 2>&1 | grep -E "PROBE|error:|failed"`
Expected: 摘要为「2 页、3 个文件夹、96 个应用。已安装 81 个；未安装 15 个……」（新应用数以本机为准）；三种屏幕各生成网格与 3 个文件夹展开图。逐张查看，确认：格子 3×3 缩略图、展开时网格隐藏、面板与主网格列对齐、标题位置、「其他」5 行完整。完成后删除探针文件。

- [ ] **Step 2: 安装**

Run: `LAUNCH_SIGN_IDENTITY="Apple Development: zhaoyingkun@163.com" ./scripts/build-app.sh --install`
Expected: 安装成功。本机尚无 `layout.json`，启动后出现首次导入预览（若 LaunchOS 仍占用 ⌥Space，会先出现冲突提示）。

- [ ] **Step 3: 端到端（辅助功能接口 + 鼠标事件，按键前确认焦点）**

1. 读取首次导入对话框文字与按钮，确认摘要文案后点「导入」。
2. 确认 `~/Library/Application Support/Launch/layout.json` 存在，含 3 个文件夹（`plutil -p` 或 `python3 -I -c` 统计 `folder` 键）。
3. 再次打开应用包唤起；确认第 1 页按钮顺序以 App Store、Safari浏览器、效率 开头。
4. 点击「效率」：确认出现成员按钮（如「邮件」）；点面板外空白：文件夹关闭、启动器仍显示；再点「效率」后按 Esc（焦点在本应用时）：文件夹关闭；再按 Esc：启动器关闭。
5. 点开「其他」，点击成员「计算器」以外的无害应用（如「字体册」）：应用启动、启动器关闭；测试前未运行则测试后退出。
6. 菜单「从 Launchpad 导入布局…」：确认对话框含覆盖说明，点「导入」后 `layout.json.backup` 存在；菜单「恢复导入前的布局」：确认后两文件互换（比较内容哈希）。

- [ ] **Step 4: 文档**

- `docs/manual-verification.md`：追加第 2 期验证结果（含离线渲染结论与端到端各项），更新待验证。
- `README.md` 当前状态：第 2 期完成内容；旧 Launchpad 导入不再是「属于第 2 期」。
- `docs/architecture.md` 第 6 节：补充导入已实现、规则见第 2 期设计文档。

- [ ] **Step 5: Commit**

```bash
git add docs/manual-verification.md README.md docs/architecture.md
git commit -m "chore(文档): 同步第 2 期状态与验证结果"
```

---

## Self-Review

**Spec 覆盖：**

| Spec | 任务 |
| --- | --- |
| §4 模型（文件夹、移除 `.missing`、解析结果） | Task 1 |
| §6.2 对齐规则、默认布局 | Task 1 |
| §7 备份互换、损坏备份 | Task 2 |
| §3/§5 只读复制、查询、错误分类 | Task 3 |
| §6.1 导入规则与摘要 | Task 4 |
| §8.1/§8.2 尺寸 | Task 5 |
| §8.1 格子、§8.3 搜索/Esc/打字/唤起/翻页 | Task 6 |
| §8.2 展开面板、§8.3 点击面板外 | Task 7 |
| §7 启动流程、首次导入、只读模式、保存失败、重新导入、恢复 | Task 8 |
| §7 菜单、提示文案、数据库来源 | Task 9 |
| §9 离线渲染、端到端、文档 | Task 10 |

**类型一致性：** `LayoutFolder(id:name:apps:)`、`ResolvedFolder`、`ResolvedItem` 在 Task 1 定义并贯穿 4/6/7/8；`reconcile(layout:catalog:pageCapacity:)`、`defaultDocument(catalog:pageCapacity:)`、`appending(_:to:pageCapacity:)` 在 Task 1/4/8 一致；`LaunchpadItem.folder(id:name:apps:)` 在 Task 3/4/8 一致；`LaunchpadImportSummary` 五参数构造在 Task 4/9 一致；`LayoutStore.replace(with:)`、`swapWithBackup()`、`hasBackup`、`backupURL` 在 Task 2/8 一致；`LauncherModel.showFolder(id:)`、`closeFolder()`、`openFolderID`、`openFolder`、`updateLayout(_:)`、`visibleItems` 在 Task 6/7/8/10 一致；`LayoutMenuActions` 四个闭包在 Task 9 定义与使用一致。
