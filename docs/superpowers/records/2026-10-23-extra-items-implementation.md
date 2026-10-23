# 网址与快捷指令首批实施记录

原目录 main 按用户明确选择保留，不额外建分支、不推送或合并；本记录归档执行账本，便于后续会话接手。自动测试统计以 XCTest 的 120 Core + 380 App（1 个交互默认跳过）为准，不采用工具尾行的 Swift Testing 空套件数字。真实 UI 与限制详见 [验收记录](../../manual-verification.md)。

# SDD ledger — plan: docs/superpowers/plans/2026-10-23-extra-items-phase-one.md

用户已确认计划，明确在 /Users/yocn/launch 原目录实现；main 分支原地开发获授权。Baseline: swift test → LaunchCore 110 + LaunchApp 353 passed。

Pre-flight: Task 1 产生类型化 ItemIdentity/LaunchItem 与 v2 文档；Task 2 服务消费这些目标；Task 3 组合两者；Task 4 只调用 Task 3 操作；Task 5 接线，Task 6 验证。接口依赖顺序一致。
Ruling: 本阶段仅网址和快捷指令，目录与面板留待后续 — 用户已确认优先级与首批计划 — 代价：后续仍需实现另外两类。
Task 1: in_progress；先测试核心数据与迁移。
Task 1: Ruling: 部分 LauncherModel 内部 apps/hiddenApps 属性暂保留旧名，但元素均为 LaunchItem；真实应用入口用 application 显式提取 — 降低无行为价值的大面积重命名 — 代价：后续读代码需区分遗留命名与实际类型。
Task 1: 核心 RED 已观察：ExtraItemDefinition/LaunchItem 不存在导致筛选测试失败。主程序 swift build 成功。初次全套仍有 1 项旧断言：LaunchCoreTests.testPackageExposesVersionedLayoutSchema 固定期待版本 1；新模型/迁移用例通过，App 353 项通过。先前误把 App 子套件通过当成整套通过，已纠正，不以此完成 Task 1。没有安装开发中的 v2 版本，用户当前安装包仍未改。
Task 1: Ruling: 版本常量断言由 1 更新为 2 — 本计划明确升级布局格式，旧版兼容由独立 v1 字节夹具证明而非降低新版本号 — 代价：旧版本程序需使用迁移备份恢复。
Task 1: complete (commits db9b05b..f7ac514, tests: swift test → ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.)
Task 2: complete (commits f7ac514..426a53a, tests: swift test → ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.)
Task 2: 实际 XCTest 计数为 117 Core + 361 App = 478 通过；task-done 尾行取到 Swift Testing 的空套件，不将“0 tests”误解为未运行 XCTest。只读 shortcuts list 发现 26 项，未运行真实指令。
Task 3: Ruling: 重新导入系统 Launchpad 时，将已固定非应用入口按原顺序保留在导入布局末尾 — 防止自定义入口消失，定义与图标仍完整保留 — 代价：重新导入后其分组/位置可能变化，与覆盖应用布局的动作一起发生。
Task 3: Ruling: 新增满页固定时先插入末项之前，再按现有规则顺延旧末项 — 满足“放到右键所在页”，不让新入口被挤走 — 代价：末项会移动到下一页。
Task 3: 全套 swift test 118 Core + 369 App = 487 通过；额外 RED→GREEN 覆盖误拆无关单成员文件夹、系统重命名与用户别名、旧图标响应、满页插入、导入/恢复元数据。还未安装半成品。
Task 3: complete (commits 426a53a..8a9e0ec, tests: swift test → ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.)
Task 4: RED 已观察：新增菜单命令/图标展示接口缺失；修正测试临时菜单构造器生命周期后，全套 118 Core + 374 App = 492 通过。两处旧主菜单断言同步明确新增 canAddWebsite=true；不是移除原有断言。浅深色实际视觉检查留 Task 6。
Task 4: complete (commits 8a9e0ec..8a7175d, tests: swift test → ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.)
Task 5: onOpenWebsite/onRunShortcut 缺失的 RED 后接线；受控后台运行证明同 UUID 重复点击只启动一次、失败不重试、状态释放、未知/失效 UUID 不执行。swift test 118 Core + 376 App = 494 通过；真实应用能力仍由 application 类型提取隔离；未执行真实用户快捷指令。
Task 5: complete (commits 8a7175d..43b4c6e, tests: swift test → ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.)
Final review: independent read-only reviewer /root/feature_review；3 Important、1 Minor。Declined to judge 为空。
Final: Ruling: 将仅换图标导致隐式名称别名由 Minor 提升 Important — 用户没有改名，不该失去系统名称同步，纳入本轮修复 — 代价：未改文本不再隐式锁定当前名称。
Final: fixed 损坏图标/重复布局标识导入 — ExtraItemValidationTests RED→GREEN，验证错误时当前与既有备份字节不变；合法测试图片换为真实 PNG。
Final: fixed 同 URL 导入/恢复/撤销的旧图标请求 — testImportRestoreAndUndoInvalidateSameURLIconResponses RED→GREEN，replacementGeneration 使旧请求失效。
Final: fixed 只换图片意外固定名称 — testChangingOnlyShortcutArtworkDoesNotFreezeTheSystemName RED→GREEN。
Task 6: 真机临时 UI 发现搜索编辑后标题不更新；testSearchObservesCatalogChangesEvenWhenQueryAndIdentityStayTheSame RED→GREEN，显式跟踪搜索索引的可观察目录来源。
Task 6: Ruling: 添加/编辑/删除/固定的 UI 实验使用 XCTest 独立临时布局与临时偏好域，安装版只做发现/搜索只读检查 — 遵守不覆盖用户布局做实验 — 代价：真实系统工作流、真实网站网络与复杂拖动手感仍不宣称实测。
Final: fixed 搜索观察来源 — 新增 Observation 失败用例后显式跟踪 apps，当前查询中编辑后标题即时更新，临时 UI 复验通过。
Final: 全套 swift test 120 Core + 380 App = 500 项，499 通过、1 交互默认跳过、0 失败；交互另显式运行通过。全部 Important 已修复；无 deferred minor，名称同步项已按用户效果升级并修复。预览初始化 geometry warning 记录到 manual-verification，不冒充无警告。
Task 6: ./scripts/build-app.sh 与使用既有 Apple Development 签名的 --install 成功，安装版严格签名校验通过。26 个真实指令只读发现，搜索/菜单实查未运行；布局 SHA-256 安装与检查前后相同。独立临时 UI 新增、域名搜索、固定、编辑即时刷新、删除与浅深色通过；真实网络/真实工作流未验证。
Task 6: complete (commits 43b4c6e..0d0c1f6, tests: swift test → ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.)
