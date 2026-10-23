# 网址与快捷指令 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让网址、快捷指令可搜索、打开、手动加入网格并参与现有布局交互，按确认稿显示左下角类型角标。

**Architecture:** 引入有类型的 `ItemIdentity` / `LaunchItem`，不把非应用内容塞进真实 `.app` 路径。搜索目录和固定网格分离；旧应用扫描保持 `[CatalogApp]`，由适配器转成启动条目。布局 v2 保存条目定义及图标，兼容只读载入 v1，首次保存前独立保留 v1 原文件。

**Tech Stack:** Swift 6、AppKit、SwiftUI、Foundation、URLSession、ImageIO；沿用 macOS 26 最低版本，不增加依赖。

**Spec:** `docs/superpowers/specs/2026-10-23-extra-items-design.md`。用户已确认网址与快捷指令优先、左下角角标及预览大小，并通过“按计划直接实现”批准本计划。

## Global Constraints

- 用户要求在 `/Users/yocn/launch` 原目录开发；保留当前设计文档与预览图的未提交改动，不另建工作树。
- 本阶段覆盖网址、快捷指令；访达文件夹与系统设置面板留给后续阶段，不从最终范围删除。
- 四类条目不自动铺入网格；应用新增自动追加的现有行为保留。
- 左下角圆形角标：网址地球、快捷指令叠层，含圆底外径约主图标 1/3，浅深色适配，以已确认预览为视觉依据。
- 删除入口不删除真实内容；非应用条目不能传进卸载、残留扫描、退出进程或真实应用简介逻辑。
- 不修改系统设置、不覆盖系统 Launchpad、不试运行用户真实快捷指令；快捷指令运行通过受控假执行器测试。
- 布局迁移、导入、恢复均保留可恢复文件；损坏、未知版本、重复标识等输入不覆盖现有布局。
- 生成或建议 commit message 使用 `<feat|fix|refactor|chore>(<中文scope>): <中文描述>`。

## 本阶段默认选择（实施判断，不冒充用户已确认）

- 技术路线采用 A：明确的条目类型与布局 v2；不使用 `launch-item:` 假应用路径。
- 搜索按现有匹配程度混排；网址额外匹配主机名。类型用图形角标，不增加类型文字行。
- 网址新增/编辑支持名称、HTTP(S) 网址与自定义图标。空白处右键添加会固定到对应页；设置页添加只进搜索目录，另有明确「添加到网格」。
- 快捷指令只读发现全部可用项；可搜索运行，右键手动固定到当前页。保留系统 UUID 作为身份，别名和图标只作用于 Launch，不修改系统快捷指令。
- 快捷指令通过 `shortcuts run <UUID>` 后台运行；不经 shell、不自动重试、同一 UUID 运行中禁止重复发起，失败显示简短原因。
- 已固定但失效的快捷指令保留并置灰，提供原因和移除入口；不执行已失效目标。
- 左下角角标应用于网格、搜索、文件夹缩略图、拖动预览；系统应用图标不加角标。
- 自定义图片与网站缓存图标以有上限的图像数据纳入布局备份，不依赖本机绝对路径。更换/恢复默认图标适用于网址与快捷指令。
- 网站图标仅在用户添加、修改网址或手动刷新时获取；使用无持久 Cookie/凭证的会话。只请求同源页面/图标，不调用第三方 favicon 服务；失败立即回退首字图标，不阻塞保存。
- 新布局导出为 v2；旧版本 Launch 拒绝新版本布局是正常边界，恢复旧版应使用独立 v1 迁移备份。

## Review Focus

1. 图标页面的跨站重定向、超大图片、异常 MIME、恶意 URL：不得读取本地文件或凭证，不发生无界下载与图像分配（Task 2）。
2. 新旧布局导入、损坏图标、重复 ID、未知版本：验证失败时原布局与已有备份保持原样（Task 1 / 3）。
3. 指令删除、重命名、iPhone 专用指令、连续点击：稳定身份、不静默丢位置、不重复运行、不自动重试（Task 2 / 5）。
4. 网页编辑期间图标请求结束、导入/撤销同时发生：旧请求不能覆盖新条目、 resurrect 删除内容或误改别名（Task 3 / 5）。
5. 非应用参与多选、分组、抖动、隐藏、排序：不能进入卸载；从目录发现的条目不能自动占网格（Task 1 / 3 / 4）。

## 文件职责

- `Sources/LaunchCore/LaunchItem.swift`：身份、类型、打开目标、自定义条目定义、可用性与能力边界。
- `Sources/LaunchCore/Models.swift`：布局 v2、分组成员及隐藏条目，v1 解码适配。
- `LayoutEngine.swift` / `LayoutEditor.swift` / `SearchService.swift` / `DisplaySorter.swift`：转为类型化启动条目；与应用扫描解耦。
- `LayoutBackup.swift` / `LayoutStore.swift`：验证、v1 迁移备份、完整导出/导入。
- `Sources/LaunchApp/WebsiteIconFetcher.swift`：有界同源网站图标获取与图像规范化。
- `Sources/LaunchApp/ShortcutService.swift`：只读发现、UUID 解析、后台受控进程执行。
- `Sources/LaunchApp/ExtraItemsController.swift`：条目目录、刷新、图标任务、保存与运行状态。
- `Sources/LaunchApp/LaunchItemIcon.swift`：首字/自定义图标和统一左下角类型角标。
- `Sources/LaunchApp/ExtraItemEditor.swift`：网址与自定义图标原生编辑对话框。
- `SettingsView.swift` / `ItemMenu.swift` / `LauncherView.swift`：条目设置页、按能力生成菜单、图标接入。
- `LaunchApp.swift` / `LauncherController.swift` / `LauncherModel.swift` / `LayoutCoordinator.swift`：接线、搜索与固定布局分离、打开分派。
- 对应 `Tests/LaunchCoreTests/*` / `Tests/LaunchAppTests/*`：核心回归、受控服务测试；真实 UI 验证另记手动记录。

### Task 1: 有类型条目、布局兼容与核心算法

**Interfaces:**
- Consumes: 现有 `AppIdentity` / `CatalogApp`（只代表真实应用）、v1 布局 JSON。
- Produces: `ItemIdentity`（application / website / shortcut）；`LaunchItem`（identity、displayName、target、availability、iconData）；`ExtraItemDefinition`；`LayoutDocument` v2。
- `LaunchItem.init(application: CatalogApp)` 负责应用适配；`ItemIdentity.applicationIdentity: AppIdentity?` 是唯一取得应用专属能力的入口。
- `LayoutEngine.reconcile(layout:catalog:pageCapacity:)` 消费 `[LaunchItem]`，只自动追加 application；`LayoutFolder.items` 存 `[ItemIdentity]`。

- [ ] 写失败测试：`ExtraItemModelsTests` 覆盖不同类型同名不冲突、URL 标识不伪装成文件路径、混合文件夹编解码。
- [ ] 写失败测试：`LayoutMigrationTests` 覆盖 v1 页序/空位/文件夹/隐藏完整保留、首次保存原文件备份一次、v2 roundtrip、未知版本与重复 ID 拒绝。
- [ ] 运行 `swift test --filter 'ExtraItemModelsTests|LayoutMigrationTests'`，Expected: 新接口缺失或明确断言失败。
- [ ] 实现类型与迁移；调整布局、排序、搜索和调用端使用明确身份，保留应用目录扫描类型。
- [ ] 添加只搜索不固定、手动固定、多选/跨页/隐藏/分组/撤销的混合条目测试；非应用不能按 App Store 类别误分组。
- [ ] 运行 `swift test`，Expected: 所有核心与现有交互测试通过。
- [ ] 提交 `feat(条目模型): 引入类型化启动条目并兼容旧布局`。

### Task 2: 网址验证、网站图标与快捷指令服务

**Interfaces:**
- Consumes: `ExtraItemDefinition` / `ItemIdentity`，Task 1 的目标类型。
- Produces: `WebsiteAddress.normalized(_ text: String) throws -> URL`；`WebsiteIconFetcher.fetch(for: URL) async -> Data?`；`ShortcutService.list() async throws -> [ShortcutRecord]`；`ShortcutService.run(id: UUID) async throws`。
- `ShortcutRecord` 提供 UUID 与名称；进程执行边界允许测试注入假执行器，不运行真实用户指令。

- [ ] 写失败测试 `WebsiteAddressTests`：裸域补 HTTPS、拒绝 file/javascript/带凭证/无主机 URL、HTTP(S) 合法地址。
- [ ] 写失败测试 `WebsiteIconFetcherTests`：相对 apple-touch-icon 优先、favicon 回退、拒绝跨源重定向、超限页面/图片、网络失败返回 nil。
- [ ] 写失败测试 `ShortcutServiceTests`：名称含空格/括号、UUID、非零退出、空清单、超时、输出限额，运行参数必须为 UUID 且无 shell。
- [ ] 运行对应筛选测试，Expected: 新服务缺失或明确断言失败。
- [ ] 实现服务：页面最大 512 KiB、图片最大 1 MiB、最多尝试 3 张图片、每次请求最多 5 秒；解码前检查尺寸上限 8192×8192，规范为最长边 256px 的 PNG。无 cookie 存储、无第三方图标服务。
- [ ] 运行 `swift test`，Expected: 服务与全部现有测试通过；本机只执行只读 `shortcuts list --show-identifiers` 核对解析。
- [ ] 提交 `feat(条目服务): 添加网站图标与快捷指令服务`。

### Task 3: 条目目录、固定布局和持久化协调

**Interfaces:**
- Consumes: Task 1 的类型/布局与 Task 2 的服务。
- Produces: `ExtraItemsController` 的只读可观察目录、刷新/运行状态；`LayoutCoordinator` 的新增、编辑、移除条目与 `pin(_:toPage:)` / `unpin(_:)` 操作。
- 所有条目定义、图标与布局引用在同一份文档变更中保存；撤销恢复完整文档；网站图标异步结果按条目 ID 与请求版本复核。

- [ ] 写失败测试 `ExtraItemsControllerTests`：发现快捷指令只进搜索；网站新增、编辑、删除；固定到指定页；刷新不丢用户图标/别名；失效固定项置灰；旧异步图标结果不能覆盖新网址或复活删除项。
- [ ] 写失败测试 `ExtraItemsBackupTests`：定义与图标跟随导出、跨目录导入及恢复；损坏数据不覆盖；导入系统 Launchpad 时不得意外删除条目定义。
- [ ] 运行筛选测试，Expected: 新协调接口缺失或明确断言失败。
- [ ] 实现控制器与布局协调，搜索目录和固定引用分离，持久化错误对用户可见而非静默丢失。
- [ ] 运行 `swift test`，Expected: 全部通过。
- [ ] 提交 `feat(条目管理): 保存网址并协调快捷指令与固定布局`。

### Task 4: 图标、编辑器、菜单和设置页

**Interfaces:**
- Consumes: Task 3 的状态和操作；Task 1 的类型能力。
- Produces: `LaunchItemIcon(item:side:)`、网址编辑器、快捷指令别名/图标编辑入口、设置「条目」页、搜索菜单固定入口。
- 菜单按类型分派：应用保留原菜单；网址打开/编辑/更换图标/隐藏/删除；快捷指令运行/固定或移除/更换图标；没有卸载/应用简介。

- [ ] 写失败测试 `ExtraItemMenuTests`：非应用无卸载/简介动作、搜索可固定、已固定可移除、失效项不能执行。
- [ ] 写失败测试 `ExtraItemIconTests`：两种左下角标记、浅深色对比、自定义图片有界解码、未知图片回退；应用不加标记。
- [ ] 运行筛选测试，Expected: 新 UI 支持接口缺失或明确断言失败。
- [ ] 实现原生对话框与设置列表、菜单，名称/URL 校验在保存前显示。删除确认明确只移除入口。
- [ ] 网格、搜索、文件夹缩略图、拖动预览接同一图标绘制规则；失败/运行中有轻量状态，避免增加多余说明行。
- [ ] 运行 `swift test`，Expected: 全部通过。
- [ ] 提交 `feat(条目界面): 添加编辑入口与左下角类型标记`。

### Task 5: 打开分派、运行保护与应用集成

**Interfaces:**
- Consumes: Task 1–4 的目标、目录、布局和 UI。
- Produces: 按目标类型分派的打开行为；网站交默认浏览器；快捷指令同 UUID 不并发启动；真实应用维持现有异步打开流程。
- `AppUninstaller` / `ResidualScanner` / `AppDatesProvider` 只接受真实 application；UI 限制之外保留底层类型边界。

- [ ] 写失败测试 `LaunchItemActivationTests`：网站只派发 URL；快捷指令只派发 UUID；重复点击不重复执行；失效项不执行；失败不重试；非应用绝不调用应用卸载或退出进程。
- [ ] 运行筛选测试，Expected: 目标分派缺失或明确断言失败。
- [ ] 接入启动生命周期、后台刷新、排序元数据、现有唤起/关闭行为；运行失败保留条目并给出错误。
- [ ] 运行 `swift test`，Expected: 全部通过。
- [ ] 提交 `feat(条目启动): 接入网址打开与快捷指令运行保护`。

### Task 6: 真机验收、交接与整体复核

- [ ] 运行 `swift test`、`./scripts/build-app.sh`，Expected: 全部通过、应用包资源完整。
- [ ] 通过独立临时数据/测试 fixture 验证迁移、固定/跨页/分组/隐藏/撤销、导出恢复；不覆盖用户当前布局进行实验。
- [ ] 安装并实际打开：添加一个测试网址、编辑、固定到右键所在页、搜索、浅深色角标、删除入口；删除不影响浏览器和文件。涉及实际打开外站时明确测试目标。
- [ ] 只读核对本机快捷指令发现与搜索、固定/移除、图标设置；不运行现有真实指令。运行路径由假执行器证明，真实执行待用户选定无副作用指令授权。
- [ ] 记录仍未验证项，更新 README、architecture、manual-verification 与使用指南，不把未来两类条目标为已实现。
- [ ] 根据 requesting-code-review 技能做一次整体独立复核，修复重要问题，补失败用例并重跑全套。
- [ ] 提交 `feat(扩展条目): 完成网址与快捷指令首批接入及验证记录`，不擅自推送或合并其他分支。
