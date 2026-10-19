# Launch Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable native macOS launcher foundation that scans installed apps, persists an independent layout, searches it, and presents a mouse-screen overlay.

**Architecture:** A Swift package provides a pure `LaunchCore` library for catalog, search, layout and storage. An AppKit executable owns the overlay panel and uses a small SwiftUI view for the initial grid. Legacy layout sources are only probed read-only.

**Tech Stack:** Swift 6.4, macOS 26, AppKit, SwiftUI, Foundation, XCTest, Swift Package Manager.

**Spec:** `docs/architecture.md`

## Global Constraints

- Target macOS 26.6.1 with Xcode 27.0 / Swift 6.4.
- Use Swift, AppKit for presentation, and SwiftUI for the initial grid.
- Present on the display currently containing the mouse pointer.
- Discover installed apps independently of the running-app list.
- Do not mutate system Launchpad data; persist an independent layout.
- Do not reproduce LaunchOS code, branding, proprietary assets, subscriptions, activation or Pro gates.
- Commit messages use `<type>(<中文scope>): <中文描述>` with only `feat`, `fix`, `refactor`, or `chore`.

## Review Focus

- A moved or missing app keeps its layout reference; Task 2 covers reconciliation.
- A malformed import never replaces the active layout; Task 3 covers safe replacement.
- Duplicate Bundle IDs resolve deterministically; Task 4 covers this.
- The overlay chooses the pointer display and does not create a separate Space; Task 5 covers this.
- Legacy layout probing remains read-only; Task 6 covers this.

---

## File Structure

- `Package.swift`: package targets and macOS floor.
- `Sources/LaunchCore/Models.swift`: value types shared by layout and catalog.
- `Sources/LaunchCore/LayoutEngine.swift`: pure reconciliation.
- `Sources/LaunchCore/LayoutStore.swift`: versioned independent JSON storage.
- `Sources/LaunchCore/AppCatalog.swift` and `SearchService.swift`: local app discovery and search.
- `Sources/LaunchCore/LaunchpadProbe.swift`: read-only source inspection.
- `Sources/LaunchApp/`: AppKit presentation and SwiftUI launcher UI.
- `Tests/`: XCTest tests for each production behavior.

### Task 1: Establish a compilable package baseline

**Files:**
- Create: `Package.swift`, `Sources/LaunchCore/LaunchCore.swift`, `Sources/LaunchApp/LaunchApp.swift`
- Create: `Tests/LaunchCoreTests/LaunchCoreTests.swift`, `Tests/LaunchAppTests/LaunchAppTests.swift`
- Modify: `README.md`, `docs/manual-verification.md`

**Interfaces:** produces a `LaunchCore` library and a `LaunchApp` executable.

- [ ] **Step 1: Write failing baseline tests**

```swift
func testPackageExposesVersionedLayoutSchema() {
    XCTAssertEqual(LayoutDocument.currentVersion, 1)
}

func testLauncherDefaultsToMouseScreenPlacement() {
    XCTAssertEqual(LauncherPlacement.defaultTarget, .mouseScreen)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test`

Expected: FAIL because package targets and symbols do not exist.

- [ ] **Step 3: Add the smallest package and placeholders**

```swift
let package = Package(
    name: "Launch",
    platforms: [.macOS(.v26)],
    products: [.library(name: "LaunchCore", targets: ["LaunchCore"]), .executable(name: "LaunchApp", targets: ["LaunchApp"])],
    targets: [.target(name: "LaunchCore"), .executableTarget(name: "LaunchApp", dependencies: ["LaunchCore"]), .testTarget(name: "LaunchCoreTests", dependencies: ["LaunchCore"]), .testTarget(name: "LaunchAppTests", dependencies: ["LaunchApp"])]
)
```

Define `LayoutDocument.currentVersion` and `LauncherPlacement.defaultTarget`; make the executable compile without opening a panel.

- [ ] **Step 4: Verify GREEN and document commands**

Run: `swift test && swift build`

Expected: PASS. Document `swift build`, `swift test`, and `swift run LaunchApp`.

- [ ] **Step 5: Commit**

```bash
git add .gitignore Package.swift Sources Tests README.md docs
git commit -m "feat(工程): 初始化原生启动器基础工程"
```

### Task 2: Define the domain and reconciliation engine

**Files:**
- Create: `Sources/LaunchCore/Models.swift`, `Sources/LaunchCore/LayoutEngine.swift`
- Create: `Tests/LaunchCoreTests/ModelsTests.swift`, `Tests/LaunchCoreTests/LayoutEngineTests.swift`

**Interfaces:** produces `AppIdentity`, `CatalogApp`, `LayoutSlot`, `LayoutDocument`, and `LayoutEngine.reconcile(layout:catalog:)`.

- [ ] **Step 1: Write failing tests**

```swift
func testAppIdentityUsesBundleIdentifierBeforePath() {
    let identity = AppIdentity(bundleIdentifier: "com.example.Reader", path: "/Applications/Reader.app")
    XCTAssertEqual(identity.stableKey, "bundle:com.example.Reader")
}

func testReconcileKeepsMissingLayoutReference() {
    let saved = document(with: .app(AppIdentity(bundleIdentifier: "com.example.Reader", path: "/Applications/Reader.app")))
    XCTAssertEqual(LayoutEngine.reconcile(layout: saved, catalog: []).pages[0].slots[0], .missing(AppIdentity(bundleIdentifier: "com.example.Reader", path: "/Applications/Reader.app")))
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter 'ModelsTests|LayoutEngineTests'`

Expected: FAIL with missing model and engine symbols.

- [ ] **Step 3: Implement pure values and reconciliation**

Use `Codable`, `Equatable`, `Hashable`, and `Sendable` values. Model intentional empty slots and missing references. Match Bundle ID first, then path; preserve page order and empty slots; return unplaced discovered apps separately.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter 'ModelsTests|LayoutEngineTests' && swift test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchCore Tests/LaunchCoreTests
git commit -m "feat(布局): 定义布局模型与对齐规则"
```

### Task 3: Persist layouts without destructive imports

**Files:**
- Create: `Sources/LaunchCore/LayoutStore.swift`, `Tests/LaunchCoreTests/LayoutStoreTests.swift`

**Interfaces:** produces `LayoutStore.load() throws -> LayoutDocument?`, `save(_:)`, and `replaceFromImport(_:)`.

- [ ] **Step 1: Write failing tests**

```swift
func testSaveThenLoadPreservesEmptySlots() throws {
    let store = temporaryStore()
    let document = document(with: .empty)
    try store.save(document)
    XCTAssertEqual(try store.load(), document)
}

func testMalformedImportDoesNotReplaceSavedLayout() throws {
    let store = temporaryStore()
    let original = document(with: .empty)
    try store.save(original)
    XCTAssertThrowsError(try store.replaceFromImport(Data("not json".utf8)))
    XCTAssertEqual(try store.load(), original)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter LayoutStoreTests`

Expected: FAIL with a missing `LayoutStore`.

- [ ] **Step 3: Implement versioned JSON storage**

Inject the destination URL. Decode and validate the schema before atomic replacement. Preserve a `.backup` only after new data decodes successfully.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter LayoutStoreTests && swift test`

Expected: PASS.

```bash
git add Sources/LaunchCore/LayoutStore.swift Tests/LaunchCoreTests/LayoutStoreTests.swift
git commit -m "feat(存储): 添加安全的布局读写"
```

### Task 4: Scan local app bundles and search results

**Files:**
- Create: `Sources/LaunchCore/AppCatalog.swift`, `Sources/LaunchCore/SearchService.swift`
- Create: `Tests/LaunchCoreTests/AppCatalogTests.swift`, `Tests/LaunchCoreTests/SearchServiceTests.swift`

**Interfaces:** produces `AppCatalog.scan(roots:) throws -> [CatalogApp]` and `SearchService.results(for:in:hidden:)`.

- [ ] **Step 1: Write failing fixture tests**

```swift
func testScanSelectsLexicallyFirstPathForDuplicateBundleIdentifier() throws {
    let root = try fixtureApps([("Zulu.app", "com.example.Reader"), ("Alpha.app", "com.example.Reader")])
    XCTAssertEqual(try AppCatalog().scan(roots: [root]).map(\.displayName), ["Alpha"])
}

func testSearchExcludesHiddenApps() {
    let reader = catalogApp(name: "Reader", bundleID: "com.example.Reader", path: "/Applications/Reader.app")
    XCTAssertTrue(SearchService.results(for: "read", in: [reader], hidden: [reader.identity]).isEmpty)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter 'AppCatalogTests|SearchServiceTests'`

Expected: FAIL with missing scanner and search symbols.

- [ ] **Step 3: Implement bounded local discovery**

Recursively enumerate only caller-provided roots for `.app` packages; read display name and Bundle ID; deduplicate Bundle IDs by lexical standardized path; preserve no-ID apps by path. Search display name and Bundle ID case- and diacritic-insensitively.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter 'AppCatalogTests|SearchServiceTests' && swift test`

Expected: PASS.

```bash
git add Sources/LaunchCore/AppCatalog.swift Sources/LaunchCore/SearchService.swift Tests/LaunchCoreTests/AppCatalogTests.swift Tests/LaunchCoreTests/SearchServiceTests.swift
git commit -m "feat(应用): 扫描本机应用并提供搜索"
```

### Task 5: Present an AppKit mouse-screen overlay

**Files:**
- Create: `Sources/LaunchApp/ScreenPresenter.swift`, `Sources/LaunchApp/LauncherView.swift`
- Modify: `Sources/LaunchApp/LaunchApp.swift`, `docs/manual-verification.md`
- Create: `Tests/LaunchAppTests/ScreenPresenterTests.swift`

**Interfaces:** produces `ScreenSelectionPolicy.screenIndex(containing:in:) -> Int?` and `ScreenPresenter.show(catalog:)` / `hide()`.

- [ ] **Step 1: Write failing policy tests**

```swift
func testScreenSelectionChoosesScreenContainingPointer() {
    let screens = [Rect(x: 0, y: 0, width: 1440, height: 900), Rect(x: 1440, y: 0, width: 1920, height: 1080)]
    XCTAssertEqual(ScreenSelectionPolicy.screenIndex(containing: Point(x: 2000, y: 400), in: screens), 1)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter ScreenPresenterTests`

Expected: FAIL with missing geometry and screen-policy symbols.

- [ ] **Step 3: Implement panel and initial grid**

Select from `NSScreen.screens` using `NSEvent.mouseLocation`. Use a borderless `NSPanel` covering the selected screen without invoking system full screen. Host a SwiftUI searchable grid from `/Applications`; Escape and background click hide it.

- [ ] **Step 4: Verify GREEN and manual behavior**

Run: `swift test && swift run LaunchApp`

Expected: tests PASS; app shows the grid on the pointer screen, accepts search text, and closes with Escape. Record display arrangement and Space/Stage Manager result in manual verification notes.

- [ ] **Step 5: Commit**

```bash
git add Sources/LaunchApp Tests/LaunchAppTests docs/manual-verification.md
git commit -m "feat(界面): 展示鼠标屏幕上的应用启动器"
```

### Task 6: Probe legacy layout sources read-only

**Files:**
- Create: `Sources/LaunchCore/LaunchpadProbe.swift`, `Tests/LaunchCoreTests/LaunchpadProbeTests.swift`
- Modify: `docs/architecture.md`, `docs/manual-verification.md`

**Interfaces:** produces `LaunchpadProbe.inspect(candidateURLs:) -> [LayoutSourceReport]`.

- [ ] **Step 1: Write failing probe tests**

```swift
func testProbeReportsMissingCandidateWithoutCreatingIt() throws {
    let missing = temporaryDirectory.appending(path: "missing.db")
    let report = LaunchpadProbe().inspect(candidateURLs: [missing])
    XCTAssertEqual(report.single?.status, .missing)
    XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path()))
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter LaunchpadProbeTests`

Expected: FAIL with missing probe symbols.

- [ ] **Step 3: Implement the inspect-only probe**

Use file metadata and readability checks only. It may not create, modify, reset, copy, delete, or write to candidate sources. Report candidate path, existence, type, size, readability and a non-sensitive format hint.

- [ ] **Step 4: Verify GREEN, inspect real candidates, and commit**

Run: `swift test --filter LaunchpadProbeTests && swift test`

Expected: PASS. Record only confirmed local findings in architecture and manual verification docs.

```bash
git add Sources/LaunchCore/LaunchpadProbe.swift Tests/LaunchCoreTests/LaunchpadProbeTests.swift docs
git commit -m "feat(导入): 探测旧启动台布局来源"
```

## Self-Review

- Coverage: this plan implements the first usable foundation and evidence collection. Editing features, folders, pagination moves, multi-select, settings, login launch, F4, gesture, trigger corners, uninstall flow, distribution and update service are separate follow-on plans.
- Type consistency: Tasks 2–4 share `AppIdentity`, `CatalogApp`, and `LayoutDocument`; Task 5 consumes catalog/search; Task 6 reports source status only.
- Review focus: every listed failure mode maps to Tasks 2–6 and a named test or manual check.
