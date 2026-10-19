# 第 1 期：常驻唤起 设计

日期：2026-10-19。状态：设计已确认，待编写实施计划。需求背景见 `docs/architecture.md`。

## 1. 目标

当前原型启动后只展示一次启动器，关闭后进程仍在但无法再次打开。本期让 Launch 成为可日常使用的常驻应用：后台常驻、⌥Space 唤起/关闭、菜单栏入口、开机启动，并安装到固定位置。

### 范围

- 常驻进程、全局快捷键、菜单栏图标、开机启动开关。
- 复用单个启动器面板，按鼠标所在屏幕显示，关闭后归还焦点。
- 应用目录变化自动刷新、图标缓存。
- 构建脚本支持安装到 `~/Applications/Launch.app` 并签名。

### 不在本期

布局导入与持久化、文件夹、方向键选中、设置页、快捷键录制、F4/手势/触发角。分别属于后续各期（见第 11 节）。

## 2. 已确认决策

| 项目 | 决定 |
| --- | --- |
| 默认快捷键 | ⌥Space。用户自行关闭 LaunchOS 的同名快捷键；本期不提供修改入口 |
| 快捷键实现 | 第三方库 KeyboardShortcuts，锁定 `exact: "3.1.0"`，提交 `Package.resolved` |
| 开机启动 | 本期提供，`SMAppService.mainApp`，默认关闭，由用户在菜单栏开启 |
| 安装位置 | `~/Applications/Launch.app` |
| 应用目录刷新 | FSEvents 触发，唤起时不扫描 |

## 3. 组件

| 组件 | 新增/修改 | 职责 |
| --- | --- | --- |
| `LaunchAppDelegate` | 修改 | 只负责组装各组件，处理 reopen 事件 |
| `LauncherController` | 新增 | 显示/隐藏/切换的唯一入口；持有应用目录缓存；接收目录刷新结果 |
| `LauncherModel` | 新增 | `@Observable`，保存应用列表、搜索词、当前页；提供显示前重置、Esc 分层、页码夹取 |
| `ScreenPresenter` | 修改 | 只创建一个面板并复用；每次显示移到鼠标所在屏幕；按关闭原因决定是否归还焦点；监听失去激活 |
| `LauncherView` | 修改 | 状态改由 `LauncherModel` 驱动；Esc 交给模型判断 |
| `HotKeyService` | 新增 | 定义 `KeyboardShortcuts.Name.toggleLauncher`，初始值 ⌥Space，按下时调用 `LauncherController.toggle()` |
| `HotKeyConflictDetector` | 新增 | 判断 LaunchOS 是否在运行且其快捷键与我们相同 |
| `StatusItemController` | 新增 | 菜单栏图标与菜单 |
| `LoginItemService` | 新增 | 封装 `SMAppService.mainApp` 的状态、注册、注销及可用性判断 |
| `CatalogWatcher` | 新增 | FSEvents 监听应用来源目录，变化后后台重扫并回调 |
| `IconCache` | 新增 | `NSCache` 包装 `ApplicationIconResolver`，按路径缓存 |
| `Resources/Info.plist` | 修改 | 增加 `LSUIElement`、`CFBundleShortVersionString`、`CFBundleVersion` |
| `scripts/build-app.sh` | 修改 | 增加 `--install` |
| `Package.swift` | 修改 | 增加 KeyboardShortcuts 依赖，仅 `LaunchApp` target 使用 |

`LaunchCore` 不依赖 AppKit 和第三方库，本期不改动其公开接口。`LauncherController` 通过协议依赖 presenter，便于用假实现测试。

## 4. 交互行为

### 4.1 启动

- 启动时不显示启动器，只出现菜单栏图标；注册快捷键；首次扫描应用目录并开始监听。
- 检测到快捷键冲突时弹出一次提示（见 4.4）。

### 4.2 唤起

入口：⌥Space、菜单栏「打开启动器」、启动器隐藏时在访达或 Spotlight 再次打开 Launch.app（`applicationShouldHandleReopen`）。

每次显示：

1. 选择鼠标所在屏幕，找不到时用第一块屏幕；面板 frame 设为该屏幕 frame。
2. 清空搜索词。上次关闭时处于浏览状态则保持当前页，超出页数时夹到最后一页；处于搜索状态则回到第一页（输入搜索词本来就会重置页码）。
3. 激活应用、面板成为 key window，搜索框获得焦点。

面板沿用现有配置：`LauncherPanel`（可成为 key）、`.statusBar` 层级、`[.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]`。全屏应用上方能否正常显示需目标机验证。

### 4.3 关闭

| 触发 | 关闭原因 | 焦点处理 |
| --- | --- | --- |
| 显示时再按 ⌥Space | `toggle` | `NSApp.hide(nil)`，交还给之前的应用 |
| 搜索词为空时按 Esc | `escape` | 同上 |
| 点击空白处 | `backgroundClick` | 同上 |
| 成功启动应用 | `launchedApp` | 只 `orderOut`，由被启动的应用获得焦点 |
| 应用失去激活（⌘Tab、点击其他屏幕等） | `resignedActive` | 只 `orderOut`，焦点已在别处 |

Esc 分层：搜索词非空时清空搜索词并保持显示；为空时关闭。

启动应用沿用 `NSWorkspace.shared.open(URL)`；返回失败时保持显示，不关闭。

### 4.4 快捷键冲突

Carbon 不报告跨进程的同组合键注册（见 8.1），因此主动检测：

- 条件：`NSRunningApplication` 中存在 `app.remixdesign.LaunchOS`，且其偏好 `KeyboardShortcuts_launchApp`（JSON 字符串，含 `carbonKeyCode`、`carbonModifiers`）与我们当前快捷键相同。偏好只读。
- 启动时检测一次，冲突则弹出提示，说明需在 LaunchOS 中关闭其快捷键或退出 LaunchOS。
- 每次打开菜单栏菜单时重新检测，冲突时显示禁用的提示项。
- 偏好读取失败或格式无法解析时视为无冲突，不报错。

## 5. 应用目录与图标

- 应用列表缓存在 `LauncherController` 中，唤起时直接使用。
- `CatalogWatcher` 用 FSEvents 监听 `ApplicationSources.defaultRoots()` 中存在的目录，latency 1 秒合并连续事件；收到事件后在后台执行 `AppCatalog.scan`，结果与当前列表不同时在主线程更新模型。
- 启动时不存在的来源目录不监听；之后创建需重启应用才生效（已知限制）。
- `IconCache` 以应用路径为 key；应用列表变化时清空全部缓存，图标按需重新读取。

## 6. 菜单栏与开机启动

菜单栏图标使用 SF Symbol `square.grid.3x3.fill`，模板图像。菜单项依次为：

1. 打开启动器（以菜单快捷键形式显示 ⌥Space）
2. ⚠︎ 快捷键与 LaunchOS 冲突（仅冲突时出现，禁用）
3. 开机启动（勾选状态反映 `SMAppService.mainApp.status == .enabled`）
4. 退出 Launch（⌘Q）

开机启动：

- 可用条件：`Bundle.main.bundleIdentifier` 非空，且应用包位于 `/Applications` 或 `~/Applications` 下。不满足时菜单项禁用，标题注明需先安装；避免把 `.build` 下的开发包登记为登录项。
- 切换时调用 `register()` / `unregister()`。状态为 `.requiresApproval` 时调用 `SMAppService.openSystemSettingsLoginItems()`；其他错误用弹窗显示系统错误描述。

## 7. 构建与安装

`./scripts/build-app.sh` 默认行为不变：debug 构建，输出 `.build/Launch.app`。

`./scripts/build-app.sh --install`：

1. `swift build -c release --product LaunchApp`。
2. 组装应用包：可执行文件、`Info.plist`、KeyboardShortcuts 的资源 bundle。
3. 签名：环境变量 `LAUNCH_SIGN_IDENTITY` 有值时用该证书，否则 ad-hoc（`-`）。建议使用 `Apple Development: zhaoyingkun@163.com`。
4. 若 Launch 正在运行，结束进程并等待退出。
5. 先复制到 `~/Applications` 下的隐藏临时名，再替换 `~/Applications/Launch.app`。
6. 打开新安装的应用。

debug 构建同样把资源 bundle 放入 `Contents/Resources`。

### 资源 bundle

SwiftPM 6.4 生成的 `Bundle.module` 依次查找 `Bundle.main.resourceURL`、所在 framework 的 resourceURL、`Bundle.main.bundleURL`，找不到直接 `fatalError`，没有构建目录回退（2026-10-19 用临时包实测生成代码）。因此 KeyboardShortcuts 的资源 bundle 放在 `Contents/Resources` 即可，不影响签名。库中 `Shortcut.description` 格式化 Space 键时会读取该资源；菜单显示快捷键改用 `NSMenuItem.keyEquivalent`。

### 待验证风险

- **签名稳定性**：ad-hoc 签名每次构建都会变化，可能导致系统不再识别已登记的登录项。需验证重新安装后开机启动是否仍然有效，并据此决定是否要求设置 `LAUNCH_SIGN_IDENTITY`。

## 8. 调研记录

### 8.1 Carbon 跨进程注册实测

2026-10-19 用两个独立进程注册同一组合键（⌃⌥⌘F12），`RegisterEventHotKey` 均返回 `noErr`。结论：无法通过注册结果发现其他应用占用的快捷键。KeyboardShortcuts 3.1.0 源码中注册失败也只在内部移除记录，不通知调用方。

### 8.2 LaunchOS 2.4.0 技术栈（只读查看包元数据与导入符号）

KeyboardShortcuts 快捷键（偏好键 `KeyboardShortcuts_launchApp`）、`CGEventTap` + 辅助功能权限、FSEvents、SwiftUI + `NSPanel` + `NSVisualEffectView`（未使用 `NSCollectionView`）、CoreData、`SMAppService`、Sparkle、私有 API `CoreDock*` 与 `CGSSetMenuBarInsetAndAlpha`、读取 Dock `wvous-*` 偏好实现触发角、读取 `DARWIN_USER_DIR/com.apple.dock.launchpad/db/db` 导入旧布局。

### 8.3 旧 Launchpad 数据

`$(getconf DARWIN_USER_DIR)/com.apple.dock.launchpad/db/db` 存在（macOS 15.5 时期写入）。复制到临时目录只读查询：2 个有内容的页面、3 个命名文件夹、96 个应用，其中 81 个可按 Bundle ID 对应本机应用。供第 2 期使用。

## 9. 测试与验证

### 自动化（XCTest）

- `LauncherModel`：显示前清空搜索词；Esc 在有/无搜索词时的结果；应用列表变少后页码夹取。
- `LauncherController`：用假 presenter 验证 toggle、各关闭原因与焦点处理的对应、启动失败不关闭。
- `HotKeyConflictDetector`：注入运行中应用列表与偏好读取，覆盖冲突、未运行、快捷键不同、偏好缺失、格式错误。
- 开机启动可用性：不同 Bundle ID 与路径组合。
- `IconCache`：同一路径命中缓存；清空后重新读取。
- 目录刷新：扫描结果相同时不更新模型。

### 目标机手动验证（记入 `docs/manual-verification.md`）

- ⌥Space 唤起与关闭，多次往返后搜索框焦点正常。
- 多显示器下在鼠标所在屏幕显示。
- 在全屏应用、台前调度下唤起。
- ⌘Tab 后自动关闭；未启动应用时焦点回到之前的应用。
- 安装或删除一个应用后，下次唤起时列表已更新。
- 开启开机启动后重启生效；重新执行 `--install` 后仍然有效。
- LaunchOS 运行且占用 ⌥Space 时出现冲突提示。

## 10. 文档同步

- `README.md`：更新当前状态与安装命令。
- `docs/architecture.md`：第 6 节记录旧 Launchpad 数据库的位置与可读性；第 3 节将主网格组件倾向调整为先沿用 SwiftUI，遇到拖拽或性能瓶颈再评估 `NSCollectionView`；补充 LaunchOS 技术栈观察。
- `docs/manual-verification.md`：补充本期手动验证结果。

## 11. 后续各期

1. 常驻唤起（本期）
2. 布局继承：只读导入旧 Launchpad、文件夹模型、按布局展示、持久化
3. 文件夹与键盘：文件夹浮层、方向键选中、Return 启动、Esc 层级、翻页手势
4. 编辑：拖拽排序、跨页、建文件夹、重命名、隐藏
5. 设置页：快捷键录制、行列、来源目录、隐藏应用、布局导入导出与备份恢复
6. 系统入口：F4、触控板手势、触发角、卸载模式、签名分发与更新
