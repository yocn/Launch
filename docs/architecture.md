# Launch 技术架构与交接说明

更新日期：2026-10-19。本文记录已讨论的产品目标与修订后架构，供其他 Codex 会话、Claude 或开发者接手。本文不是实现完成报告，也不是已逐项批准的执行计划。

## 1. 目标与确认记录

用户希望复刻电脑上的 LaunchOS，制作可长期日常使用的 macOS 应用启动器。

| 项目 | 已确认内容 |
| --- | --- |
| 工作位置 | `/Users/yocn/launch` |
| 目标环境 | macOS 26.6.1（25G76） |
| 开发工具 | 本机已核实 Xcode 27.0（27A266a） |
| 布局来源 | 读取并尽量继承系统 Launchpad 的应用顺序、页面和文件夹 |
| 唤起位置 | 鼠标当前所在的显示器 |
| 交互基准 | 具体参考本机 LaunchOS，包含键盘和鼠标操作 |
| 产品范围 | LaunchOS 的全部本地功能；不复刻会员购买、激活、Pro 限制 |
| 技术方向 | Swift + AppKit 主界面和系统集成 + SwiftUI 设置页 |

技术路线已提出，用户随后指定目录并要求复核结构，对修订后的方向回应“嗯”，要求保存以便接手。具体框架细节、数据格式和实施任务仍需结合验证落实。

## 2. 已观察到的 LaunchOS 能力

参考应用位于 `/Applications/LaunchOS.app`。已通过本机界面观察到：

- 主界面：覆盖屏幕的应用图标网格、名称、文件夹、顶部搜索框、底部分页指示器；当时设置为 7 列 × 5 行。第一页最多 35 个位置，页码圆点可点击切换到剩余应用页；空白处点击会关闭启动器。
- 搜索：输入 `safari` 可即时筛选应用，搜索条会显示清除按钮，清空后恢复网格。2026-10-19 的自动化按 Escape 未改变当前搜索界面；尚未验证拼音、模糊匹配及完整键盘行为。
- 菜单：自定义/名称/添加日期/上次使用排序；全屏/窗口模式；分页/滚动浏览；整理布局。
- 通用设置：开机自启动、可录制快捷键（当时为 Option + Space）、系统 F4、触控板、触发角、多选、菜单栏图标及应用图标选择。
- 界面设置：隐藏 Dock、行列布局、隐藏名称、系统壁纸/毛玻璃背景及材质调节。
- 应用管理：应用来源目录、隐藏应用、搜索结果是否显示隐藏应用。
- 高级设置：显示器选择、返回首页时机、按住 Option 进入卸载模式、恢复系统 Launchpad 数据、布局导入/导出、整理布局、自动检查更新、日志导出。

部分能力仅在菜单或设置中看到了入口，因参考应用试用过期而不可操作。不能据此声称已验证其效果。文件夹、拖拽、跨页、多选、手势、右键和卸载细节仍需补充观察。

行为参考不要求复制品牌或素材。应用图标从用户本机应用获取；自身品牌素材独立制作。更新检查是本地设置配套能力，但发布渠道、服务器和签名分发尚未确定，不应虚构可用更新源。

## 3. 核心架构

原则：应用目录、用户布局、临时交互状态、文件存储各自独立；界面不直接读写系统布局数据库。

| 模块 | 职责 | 边界 |
| --- | --- | --- |
| `LauncherController` | 协调唤起、关闭、启动应用及设置入口 | 不承担布局算法、数据库解析或所有系统事件处理 |
| `ScreenPresenter` | 按鼠标位置选择屏幕，管理覆盖窗口、焦点、空间切换和关闭后的焦点恢复 | 不决定应用排序和搜索结果 |
| `LauncherSession` | 当前页、打开的文件夹、搜索词、键盘选中项、编辑/拖拽/多选状态 | 会话状态与持久布局分离；需保留的浏览位置通过明确策略保存 |
| `LauncherUI` | 网格、文件夹、搜索、分页或滚动展示、交互反馈和无障碍信息 | 将操作交给会话和布局引擎，避免在视图中散布规则 |
| `LayoutEngine` | 移动、排序、跨页、文件夹创建/拆分、多选移动、整理空位和布局约束 | 根据操作生成有效的新布局，不直接写文件或操作窗口 |
| `AppCatalog` | 扫描应用来源，解析名称、路径及标识，协调应用新增/移除/移动后的更新 | 当前默认来源为 `/Applications`、`/System/Applications`、`/System/Library/CoreServices/Applications` 和 `~/Applications`；目录变化不能直接重置用户布局；避免把运行中应用列表当作已安装应用列表 |
| `SearchService` | 根据应用目录、隐藏规则和查询生成稳定结果 | 与持久布局独立；排序及匹配策略需定义并验证 |
| `IconProvider` | 按需读取和缓存本机应用图标，处理失效与占位图 | 后台读取，控制内存，避免启动时同步加载所有大图 |
| `LayoutImporter` | 探测来源、只读解析、应用映射、生成导入预览及缺失报告 | 首个适配器为旧 Launchpad；不持续同步或回写系统数据库 |
| `LayoutStore` | 独立布局持久化、格式版本、校验、原子保存、备份与恢复 | 不执行拖拽/分页算法；导入文件必须先校验 |
| `PreferencesStore` | 保存显示、搜索、入口和应用来源等偏好 | 与应用位置布局分离，定义默认值及迁移规则 |
| 系统入口服务 | 各自实现快捷键、F4、触控板、触发角、菜单栏及登录启动 | 分别评估 API、权限、冲突和系统兼容性 |
| `ApplicationLauncher` | 发起应用启动，返回结果或明确错误 | 对失败保持可恢复状态；退出启动器和恢复焦点需与启动结果协调 |
| 设置界面 | 以 SwiftUI 编辑偏好、来源与数据管理配置 | 通过上述模块执行操作 |

这些是职责边界，不要求为每个名字建立独立 Package 或复杂接口层。初期可在同一应用 target 内按目录组织，必要时才拆模块。

主界面先沿用 SwiftUI 网格（LaunchOS 2.4.0 同样以 SwiftUI + `NSPanel` 实现，未使用 `NSCollectionView`），拖拽、文件夹动画或性能遇到瓶颈时再评估 AppKit 集合视图；设置用 SwiftUI。多屏时以主显示器为参考布局，其他屏幕整体等比缩放（见 `LauncherHomeLayout`）。LaunchOS 技术栈的只读观察见 `docs/superpowers/specs/2026-10-19-resident-launcher-design.md` 第 8.2 节。

## 4. 数据模型与流转

需要分别维护三类数据：

1. **应用目录**：本机实际发现的应用、Bundle ID、定位信息、名称、来源、元数据与可用状态。
2. **用户布局**：稳定的应用引用、页面、位置、文件夹、隐藏状态及布局格式版本。
3. **会话状态**：当前查询、页面、焦点、文件夹和交互状态。

Bundle ID 是主要匹配依据，但不能假设始终存在或全局唯一。需要明确无 Bundle ID、重复安装、多版本应用和移动路径时的身份规则。应用暂时离线或无法访问时，应保留布局引用并标记状态；不能仅因一次扫描没找到就永久删除用户位置。

布局应能表达固定位置与空位，支持文件夹成员顺序，并有稳定节点 ID。分页网格与滚动模式共享一份逻辑顺序；行列变化后的重排策略及空位保留规则需先定义，避免调整外观意外破坏布局。

常见数据流：

- 启动：读取偏好和已有布局 → 扫描/复核应用目录 → 对齐应用引用 → 展示。
- 编辑：界面操作 → `LauncherSession`/`LayoutEngine` → 校验后的新布局 → `LayoutStore` 保存 → 界面更新。
- 搜索：查询 + 目录 + 隐藏规则 → 搜索结果 → 会话选中项更新；不改写布局。
- 系统导入：只读探测 → 解析 → 匹配目录 → 预览恢复数量与缺失项 → 用户选择应用 → 备份并保存独立布局。

持久化可先采用带版本的 JSON；实际内部格式在导入探测和模型验证后确定。导出应包含足够的标识与版本信息，跨设备导入不能依赖原机器的绝对路径。保存采用原子替换并保留可恢复副本，解析错误时不覆盖旧数据。

## 5. 窗口与交互约定

默认“全屏”指在鼠标所在显示器覆盖显示启动器，不默认进入会创建独立 Space 的系统全屏模式。窗口外框覆盖屏幕，图标、搜索框和分页控件按安全区域布局；覆盖范围、Dock 显隐和菜单栏处理应分别设计。

需验证其他应用处于全屏时的唤起、台前调度、Mission Control、多显示器不同缩放、显示器拔插及睡眠恢复。窗口层级与 collection behavior 的最终组合要以目标机测试为准。

快捷键唤起后应可直接输入搜索。方向键、Return、Esc、点击空白处、文件夹退出、搜索清空和跨页行为，以进一步观察到的 LaunchOS 行为定稿。不要把 Esc 简单绑定成所有状态下直接关闭，应先明确搜索、文件夹和编辑状态的退出层次。

默认快捷键已定为 ⌥Space（KeyboardShortcuts 库，底层 Carbon），由用户自行关闭 LaunchOS 的同名快捷键。Carbon 不报告跨进程的同组合键注册，因此 Launch 主动检测 LaunchOS 是否运行且占用相同组合并提示；快捷键录制属于设置页。F4 和触控板手势的可行性、权限和冲突处理尚未验证；不能提前宣称与普通快捷键同等可靠。

应用卸载、恢复系统数据、覆盖布局属于有明确影响的操作，必须单独设计确认与恢复流程。用户要求功能等价，并不意味着开发时可以直接执行这些操作。特别是“恢复系统 Launchpad 数据”的真实含义及写入目标尚未核实，不得直接实现成回写系统数据库。

## 6. 布局继承：优先验证的风险

当前已提供 `LaunchpadProbe`，它只报告调用方提供的候选路径是否存在、可读和文件类型，不会创建、修改或重置任何系统数据。2026-10-19 确认旧 Launchpad 数据库位于 `$(getconf DARWIN_USER_DIR)/com.apple.dock.launchpad/db/db`（SQLite，同目录有 `db-wal`、`db-shm`；`dbinfo` 记录 build 24F74，即 macOS 15.5 时期写入）。复制到临时目录只读查询：`items` 表以 `parent_id`、`ordering` 组织树，type 1 为根、3 为页面、2 为文件夹、4 为应用；`launchpad_root` 下有 2 个有内容的页面（另有 1 个空页）、3 个命名文件夹，共 96 个应用，其中 81 个可按 Bundle ID 对应本机应用。LaunchOS 2.4.0 读取同一路径。macOS 26 的 Spotlight 应用入口不等同于旧 Launchpad 布局。第 2 期已实现只读导入（`LaunchpadSnapshotReader`、`LaunchpadImporter`），对齐与持久化规则见 `docs/superpowers/specs/2026-10-19-layout-inheritance-design.md`。

第一阶段需记录：

- 来源文件是否存在、路径、可读性和数据格式；遇到权限拒绝应明确报告。
- 是否包含页面顺序、应用顺序、文件夹名称及成员。
- 能按 Bundle ID 或其他证据映射到本机应用的数量，缺失与冲突的具体原因。
- 是否需要处理 SQLite 的 WAL/一致性快照，以及不同系统格式的适配。
- 整个过程保持源数据只读，不重置 Dock 或系统布局。

导入失败或部分成功时给出明确结果，并提供手动布局与之后重新导入的入口。重新导入不能静默覆盖已经编辑的独立布局。导入 LaunchOS 自身导出文件可作为后续候选能力，但用户尚未确认，且文件格式还未检查，不能擅自替代系统来源。

## 7. 建议实施顺序

下列是接手路线，尚未执行：

1. **补齐证据**：核实系统布局来源；观察 LaunchOS 的文件夹、拖拽、右键、多选、分页与键盘细节，形成行为清单和兼容性结论。
2. **验证核心系统交互**：建立最小 macOS 原生工程，验证鼠标所在屏幕唤起、焦点、关闭、普通/全屏 Space 及快捷键冲突；必要原型结果记录清楚。
3. **完成可日用的主流程**：应用目录、图标、启动、搜索、网格、键盘选择、分页、文件夹、布局保存和旧布局导入。
4. **完善编辑与设置**：拖拽跨页、多选、隐藏、来源管理、排序、行列、滚动/窗口模式、背景、返回首页策略和备份恢复。2026-10-20 拆为 4a 拖拽重排与文件夹编辑（已完成，见 `docs/superpowers/specs/2026-10-20-drag-edit-design.md`）、4b 多选与批量操作（已完成，见 `docs/superpowers/specs/2026-10-20-multi-select-design.md`）、4c 右键菜单与隐藏（已完成，见 `docs/superpowers/specs/2026-10-20-context-menu-hide-design.md`）；设置类内容归入第 5 期，2026-10-20 拆为 5a 设置窗口与显示（已完成，见 `docs/superpowers/specs/2026-10-20-settings-window-design.md`）、行列数（已完成，见 `docs/superpowers/specs/2026-10-21-grid-size-design.md`）、5b 排序与整理（5b-1 整理布局与全选已完成，见 `docs/superpowers/specs/2026-10-21-arrange-layout-design.md`；5b-2 排序方式已完成，见 `docs/superpowers/specs/2026-10-21-sort-order-design.md`；5b-3 按类型分组已完成，见 `docs/superpowers/specs/2026-10-21-group-by-category-design.md`）、5c 浏览模式（5c-1 滚动浏览已完成，见 `docs/superpowers/specs/2026-10-21-scroll-browsing-design.md`；5c-2 窗口模式已完成，见 `docs/superpowers/specs/2026-10-21-window-mode-design.md`）、5d 数据（5d-1 布局备份已完成，见 `docs/superpowers/specs/2026-10-21-layout-backup-design.md`；5d-2 应用来源已完成，见 `docs/superpowers/specs/2026-10-21-app-sources-design.md`；5d-3 日志与诊断已完成，见 `docs/superpowers/specs/2026-10-21-diagnostics-design.md`）。
5. **补齐系统入口与配套**（2026-10-21：触发角、F4 键与触控板捏合已实现，见 `docs/superpowers/specs/2026-10-21-system-entries-design.md`；F4 与捏合待用户授权后核对）：按验证结果实现 F4、手势、触发角、登录启动、菜单栏、卸载流程、诊断；定义签名、分发和更新渠道。
6. **实际日用验收**：在目标系统持续使用，修正唤起、焦点、数据保留和性能问题，再考虑替换现有启动器。

顺序安排不代表缩减“全部本地功能”的最终范围。若系统能力受限，应记录具体不可达行为及替代方案，而非悄悄省略。

## 8. 验证与验收

- 工程建立后补充明确的构建命令及运行入口；目前没有可执行命令。
- 对布局引擎、格式迁移和导入映射采用有意义的自动化验证，覆盖空位、跨页、文件夹、重复应用、缺失应用和无效导入。
- 窗口焦点、鼠标所在屏幕、全屏应用、台前调度、快捷键冲突、中文输入法和拖拽采用目标机手动/UI 验证。
- 验证应用安装/移除/移动、来源暂不可用、重启及睡眠恢复后，布局不会被意外重置。
- 导出再导入应保留页面、文件夹、排序和隐藏设置；损坏文件不覆盖当前布局，失败可从备份恢复。
- 应用启动失败提供可理解的提示；扫描和图标读取不阻塞主要交互；缓存有失效与容量策略。
- 记录唤起耗时、搜索响应和内存占用的实测结果，再确定性能预算，不在未测量前承诺数字。
- 明确签名与本机运行方式，避免每次重新构建导致系统权限或登录启动配置失效后无提示。

## 9. 尚未确定的事项

- 产品名、Bundle ID、签名身份、最低支持 macOS 版本及分发方式。
- 系统布局是否可读取，以及实际恢复范围。
- 中文/拼音/模糊搜索规则、排序细节、使用记录的采集范围和存储策略。
- F4、触控板及触发角的目标行为、API 可行性与权限条件。
- “恢复系统 Launchpad 数据”、卸载及自动更新的准确行为和实现范围。

上述事项优先通过本机观察与小范围验证推进。已有确认不需重新逐项询问；涉及用户数据覆盖、系统写入、分发服务或不可兼容的产品选择时，再提出具体问题。

## 10. 技术参考

- [NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)：Spaces、全屏及台前调度相关窗口行为，部分选项互斥。
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)：应用启动与工作区集成；运行中应用列表不等于已安装应用目录。
- [Apple：在 Mac 上查看和打开 App](https://support.apple.com/guide/mac-help/open-apps-in-spotlight-mh35840/mac)：当前系统的 Spotlight 应用浏览入口背景。

官方 API 文档用于核实能力边界；旧布局格式和本机权限情况仍须实际验证。

## 应用图标选择（2026-10-22）

通用设置新增 `showsInAppSwitcher`，默认 false，运行时切换 `NSApplication` 的 regular / accessory 策略，同时控制 ⌘Tab 与程序坞；不能把两者拆为独立选项。状态栏沿用 `showsMenuBarIcon` 的存储键，默认 true；两者独立，可同时关闭，不影响快捷键或访达重开入口。应用从 ⌘Tab 重新激活时打开启动器；设置窗口可见时不抢焦点。启动包继续保留 LSUIElement=true，启动后按偏好应用策略，不修改程序坞的全局配置。

用户最终确认三套：四瓣开合、黑白九宫格、蓝紫四格（2×2，右上格倾斜），每套浅/深色；折光 L 不接入。概念稿与生产提示词保留在 `design/icon-concepts-2026-10-22`。

`AppIconController` 使用公开 `NSApplication.applicationIconImage` 更新运行中图标，监听应用有效外观；偏好 `appIconStyle` / `appIconTheme` 由 `LauncherSettings` 保存。设置 → 外观 → 应用图标中选三套之一，并选择跟随系统、浅色或深色。`IconCache` 对 Launch 自身应用路径提供可观察覆盖，目录刷新和旧异步图标结果不能覆盖当前选择。

六张透明 PNG 通过 SwiftPM 复制到 `Launch_LaunchApp.bundle/AppIcons`；打包脚本复制资源 bundle，并从 `grid-light.png` 生成多尺寸 AppIcon.icns。安装包默认图标为浅色九宫格；设置切换仅影响运行中的 Dock 图标与启动器内 Launch 图标，访达的静态图标不随偏好切换。禁止用 NSWorkspace.setIcon 修改本体：临时假应用探测发现它添加 FinderInfo，导致严格签名校验失败。切换不改写安装包，不影响布局数据。

## 11. 卸载关联文件清理（2026-10-22）

用户确认采用保守方案，设计与局限见 [卸载关联文件清理](superpowers/specs/2026-10-22-residual-cleanup-design.md)。`ResidualScanner` 后台只读检查固定目录与精确标识、验证签名并单独枚举应用来源（保留重复安装信息）；`UninstallReview` 显示路径/大小/依据与禁选原因，残留默认全不选；`UninstallCleanup` 执行固定计划、每项移动前复核并原子写入 JSON 记录。`UninstallCoordinator` 串行协调扫描、确认、正常退出全部匹配实例及执行，取消不退出应用、不移动文件。

移动只走系统废纸篓接口；本体失败就停止，残留变化或失败逐项保留。签名无法核对、其他安装副本（含大小写相同及子标识的独立应用）、共享组、名称匹配、链接/硬链接、读取不完整或超限项均禁选。不提权，不处理系统 Library、钥匙串、服务或扩展，不宣称全盘或彻底清理。记录在 `~/Library/Application Support/Launch/UninstallRecords`，完成后可在访达显示。记录提供原路径与实际废纸篓路径，手动移回；不保证访达有「放回原处」菜单或恢复应用运行状态。

卸载目标的实际文件移动前仍保留原权限限制；不卸载系统应用及 Launch 自身。扫描与 trashItem 之间存在非原子窗口，不能抵御同一用户恶意进程制造的精确竞态。测试覆盖失败/替换/共享保护；真机仅使用自制空应用和假残留。`scripts/make-cleanup-fixture.sh` 可重建测试材料，需明确运行授权及 Apple Development 签名，拒绝覆盖现有目标。

## 12. 网址与快捷指令（2026-10-23）

首批按 [设计](superpowers/specs/2026-10-23-extra-items-design.md) 与 [执行计划](superpowers/plans/2026-10-23-extra-items-phase-one.md) 实现；访达文件夹和系统设置面板尚未实现。

- `CatalogApp` / `AppIdentity` 仍仅代表磁盘上的真实应用。`ItemIdentity`、`LaunchTarget`、`LaunchItem` 承载 application / website / shortcut，禁止伪造应用路径；卸载、简介、退出进程和日期元数据仅接受真实应用。
- `ExtraItemsController` 合并真实应用、网站定义、只读发现的快捷指令目录；目录可搜索，只有用户固定的非应用引用进入网格。快捷指令 UUID 为稳定身份；系统改名默认跟随，用户别名和图标仅保存在 Launch，已固定的失效项置灰保留。
- `LayoutDocument` v2 保存 typed slots、folder.items、hiddenItems、extraItems 及有上限的图标数据。v1 解码保留页序/空位/文件夹；首次写入前保留独立 `layout.json.v1-backup`，绝不覆盖原快照，导入备份仍使用 `.backup`。旧版本需用 v1 快照回退。
- `LayoutBackup` 在写入前拒绝未知版本、重复定义/布局身份/文件夹 ID、缺失定义及损坏/超限图像。图像先检查头部尺寸，再有界解码缩略图；错误不能覆盖现有布局或导入备份。
- `LayoutCoordinator` 原子保存完整文档并维护 20 步撤销；导入、恢复、撤销有 `replacementGeneration`，异步图标回写须复核请求版本、文档代次与 URL，不能覆盖恢复结果。满页固定将旧末项顺延，保留新入口在指定页。重新导入 Launchpad 时，已固定非应用按原序附在末尾，原分组/位置可能改变。
- `WebsiteAddress` 仅允许无凭证 HTTP(S)。`WebsiteIconFetcher` 用临时无 Cookie/凭证会话、只请求同源资源，每请求 5 秒、页面 512 KiB、图片 1 MiB，最多 3 张，解码前像素上限 8192²，转最长边 256px PNG。只在新增、改网址或手动刷新时访问网站；失败用首字图标，不使用第三方 favicon 服务。
- `ShortcutService` 后台执行 `/usr/bin/shortcuts list --show-identifiers`；运行用 `run <UUID>`，不经 shell，最长等待 300 秒，输出限额 1 MiB，同 UUID 运行中拒绝重复发起，错误不重试。超时停止的是 CLI 等待，不保证系统中已经开始的工作流已终止；不要立即重试有副作用的指令。
- `LaunchItemIcon` 为网格/搜索/文件夹预览/拖动共用绘制入口。非应用左下角圆形角标约图标 1/3；`ExtraItemEditor` 提供网址与图片编辑，`ExtraItemsSettingsView` 是设置「应用」页「网址与快捷指令 → 管理…」打开的面板（2026-10-26 起不再单独占页签）。`LauncherModel.catalog` / `hiddenItems` 装的是 `LaunchItem`，含网址与快捷指令，真实应用用 `.application` 取出。
- 回归用临时布局与注入执行器；交互夹具：`LAUNCH_EXTRA_ITEMS_PREVIEW=1 swift test --filter ExtraItemsUIPreviewTests`，只用临时数据和假指令，不执行真实系统工作流。真实执行需要用户自行选择无副作用指令验证；实际验收证据见 manual-verification。
