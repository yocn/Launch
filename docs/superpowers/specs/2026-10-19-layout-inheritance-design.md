# 第 2 期：布局继承 设计

日期：2026-10-19。状态：设计已确认，待编写实施计划。需求背景见 `docs/architecture.md`，第 1 期见 `2026-10-19-resident-launcher-design.md`。

## 1. 目标

只读导入旧 Launchpad 布局（页面、顺序、文件夹），以独立布局文件持久化，启动器按布局显示并支持打开文件夹。

### 范围

- 只读读取旧 Launchpad 数据库并转换为本地布局。
- 布局模型支持文件夹；布局文件持久化、备份与恢复。
- 首次启动导入预览、菜单栏重新导入与恢复入口。
- 按布局分页显示；文件夹格子与基础版文件夹展开（打开、启动成员、关闭）。
- 布局与已安装应用对齐：未安装隐藏、新应用追加。

### 不在本期

文件夹内方向键与分页、从格子位置放大的展开动画（第 3 期）；拖拽、重命名、隐藏应用（第 4 期）；背景改为模糊壁纸（第 5 期设置项）。

## 2. 已确认决策

| 项目 | 决定 |
| --- | --- |
| 数据库读取 | 系统 SQLite3 C 接口，复制 `db`、`db-wal`、`db-shm` 到临时目录后只读打开 |
| 未安装应用 | 布局中保留，不显示、不占格，后续项前移；重新安装后回到原位 |
| 新应用 | 按名称追加到最后一页末尾，满 35 项开新页，并保存 |
| 文件夹 | 本期做基础版展开 |
| 导入入口 | 首次启动预览提示 + 菜单栏「从 Launchpad 导入布局…」「恢复导入前的布局」 |
| 恢复方式 | 当前布局与备份互换，可再次互换撤销 |

## 3. 旧 Launchpad 数据

位置：`confstr(_CS_DARWIN_USER_DIR)` + `com.apple.dock.launchpad/db/db`。

结构（2026-10-19 本机只读查询）：

- `dbinfo` 的 `launchpad_root` 为可见布局根（本机为 1）；另一根 `launchpad_version_root` 下有重复条目，不读取。
- `items(rowid, type, parent_id, ordering)`：type 3 页面、2 文件夹、4 应用；同一父节点下按 `ordering` 排序。
- `apps(item_id, title, bundleid)`、`groups(item_id, title)`：应用与文件夹名称。
- 根 → 页面 → 应用或文件夹；文件夹 → 页面 → 应用。本机文件夹各只有 1 页。
- 本机：2 个有内容的页面（另有 1 个空页）、3 个文件夹、96 个应用，81 个已安装；无缺少 Bundle ID 的条目。

LaunchOS 2.4.0 录屏佐证：其第 1 页显示 30 项，即数据库该页 33 项去掉 3 个未安装应用后前移，与本期规则一致。

## 4. 数据模型（LaunchCore）

```swift
public struct LayoutFolder: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let apps: [AppIdentity]
}

public enum LayoutSlot: Codable, Equatable, Sendable {
    case app(AppIdentity)
    case folder(LayoutFolder)
    case empty
}
```

- 布局文件只记录应用身份，不记录安装状态；原 `.missing` 用例移除，安装状态在对齐时计算。
- 未安装应用的 `AppIdentity` 路径为空字符串，靠 Bundle ID 匹配。
- 导入文件夹的 `id` 为 `launchpad-<rowid>`，保证确定性。
- `LayoutDocument` 格式版本仍为 1：此前从未写入磁盘，无需迁移。

显示用的解析结果：

```swift
public enum ResolvedItem: Equatable, Sendable {
    case app(CatalogApp)
    case folder(ResolvedFolder)
    case empty
}

public struct ResolvedFolder: Equatable, Sendable {
    public let id: String
    public let name: String
    public let apps: [CatalogApp]
}
```

## 5. 组件

| 组件 | 位置 | 职责 |
| --- | --- | --- |
| `LaunchpadSnapshot` | LaunchCore | 读出的原始结构：页 → 应用（Bundle ID、标题）或文件夹（rowid、名称、成员） |
| `LaunchpadSnapshotReader` | LaunchCore | 定位数据库、复制到临时目录、只读查询、删除临时目录；错误分类为未找到、打开失败、查询失败、缺少根 |
| `LaunchpadImporter` | LaunchCore | 快照 + 应用目录 → `LayoutDocument` 与导入摘要；生成按名称排序的默认布局 |
| `LayoutEngine.reconcile` | LaunchCore | 布局 + 应用目录 → 每页 `ResolvedItem`、追加新应用后的文档、追加了哪些应用 |
| `LayoutStore` | LaunchCore | 新增「是否有备份」「与备份互换」；沿用原子写入与导入前备份 |
| `LayoutCoordinator` | LaunchApp | 启动加载、首次导入、目录变化对齐与保存、菜单导入与恢复；通过协议依赖提示框与数据库来源，便于测试 |
| `LayoutPrompting` / `AlertLayoutPrompter` | LaunchApp | 预览确认、恢复确认、错误提示；实现用 `NSAlert` |
| `LaunchpadSource` / `LiveLaunchpadSource` | LaunchApp | 数据库是否存在；后台线程读取快照 |
| `LauncherModel` | LaunchApp | 新增布局页、打开的文件夹、Esc 三层 |
| `LauncherController` | LaunchApp | 新增点击背景：文件夹打开时只关文件夹，否则关闭启动器 |
| `LauncherHomeLayout` | LaunchApp | 新增文件夹格子与展开面板的尺寸，随缩放系数等比变化 |
| `LauncherView` | LaunchApp | 渲染应用、文件夹、空位；文件夹展开视图 |
| `StatusItemController` | LaunchApp | 新增导入与恢复两个菜单项 |

## 6. 导入与对齐规则

### 6.1 快照 → 布局（`LaunchpadImporter`）

1. 只遍历 `launchpad_root` 下的页面，按 `ordering`。
2. 跳过空页；同一 Bundle ID 只保留第一次出现（文件夹内成员同样参与去重）。
3. 文件夹成员去重后为空则不生成该文件夹。
4. 应用按 Bundle ID 对应本机应用目录，对应上则用目录中的身份（含路径），否则路径为空。
5. 单页超过 35 项则依次拆页。
6. 本机已安装但布局中没有的应用，按名称追加到最后一页末尾，满 35 项开新页。
7. 摘要：Launchpad 页数（非空）、文件夹数、应用数（去重后）、已安装数、未安装数、新应用数。

默认布局：应用目录按名称排序，每页 35 项。

### 6.2 运行时对齐（`LayoutEngine.reconcile`）

- 匹配顺序：Bundle ID，再路径；应用目录按路径排序后先到先得（与现有规则一致）。
- 未安装应用：不输出，不占格。
- 文件夹：只保留已安装成员；没有已安装成员则不输出。
- 输出后为空的页面去掉。
- 布局中任何位置（含文件夹内）都没有的已安装应用，按 6.1 第 6 条追加到文档，并返回追加列表供调用方保存。
- 显示时若某页超过 35 项（手工改过文件），按 35 拆分显示。

## 7. 启动、菜单与持久化（`LayoutCoordinator`）

文件：`~/Library/Application Support/Launch/layout.json`，备份 `layout.json.backup`。

启动：

1. 读取布局文件。存在且可解析 → 使用；不存在 → 待首次设置；解析失败或版本不支持 → 只读模式：文件不动，提示一次「布局文件无法读取，暂时按名称排列」，本次运行不写入。
2. 首次收到应用目录后：
   - 待首次设置且数据库存在 → 后台读取快照 → 预览提示（「导入」「暂不」）。导入 → 保存导入布局；暂不 → 保存默认布局。
   - 待首次设置且数据库不存在 → 保存默认布局，不提示。
   - 读取失败 → 提示原因，保存默认布局。
3. 之后每次应用目录变化 → 对齐；有追加则保存（只读模式不保存）；写入失败本次运行只提示一次。
4. 首次设置进行中又收到目录变化 → 记下最新目录，设置完成后用最新目录对齐。

预览文案示例：「旧 Launchpad 布局：2 页、3 个文件夹、96 个应用。已安装 81 个；未安装 15 个，会保留位置，重新安装后回到原处。另有 25 个新应用会排在最后。」

菜单（位于「开机启动」之后）：

- 「从 Launchpad 导入布局…」：数据库存在时可用。读取快照 → 预览并注明「会覆盖当前布局，覆盖前自动备份」（「导入」「取消」）→ `replaceFromImport` 写入并备份旧布局。只读模式下同样可用，损坏的旧文件进入备份。
- 「恢复导入前的布局」：备份存在时可用。确认后与备份互换；备份解析失败则提示且不改动。

出错处理：

| 情况 | 处理 |
| --- | --- |
| 数据库不存在 | 菜单项置灰；首次启动静默使用默认布局 |
| 复制、打开、查询失败或缺少根 | 提示原因，不修改布局 |
| 写入布局失败 | 提示原因，继续使用内存中的布局 |
| 备份损坏 | 提示，不覆盖当前布局 |

## 8. 界面（参考 LaunchOS 录屏）

### 8.1 文件夹格子

- 与应用图标同尺寸；圆角 = 0.225 × 图标边长；底色白色 14% 不透明度，1pt 白色 22% 描边。
- 内含 3×3 缩略图，显示前 9 个已安装成员；缩略图边长 0.19 × 图标边长，间距 0.065 × 图标边长。
- 名称、悬停高亮与应用格子一致。

### 8.2 文件夹展开

- 主网格、搜索框、分页圆点淡出（不可点击）；文件夹名称与成员面板淡入，面板从 0.92 倍缩放至 1，时长约 0.2 秒。
- 成员网格与主网格同列位置、同图标尺寸与行距；面板左右各比网格外扩 42pt（参考屏下距屏幕边缘 94pt），上下内边距 30pt，圆角 36pt，白色 8% 底色与 1pt 白色 15% 描边。
- 名称在面板上方居中，22pt，白色，与面板间距 30pt；名称与面板整体在内容区垂直居中。
- 行数 = ceil(成员数 / 7)，最多 5 行；超过 35 个成员时面板内纵向滚动。
- 以上尺寸均乘缩放系数。

### 8.3 交互

- 点击面板外任意处：只关闭文件夹。点击面板空白处无反应。
- 点击成员：启动应用并关闭启动器。
- Esc：先关文件夹，再清空搜索词，最后关闭启动器。
- 文件夹打开时打字：搜索框仍持有焦点，输入使文件夹关闭并显示搜索结果。
- 每次唤起回到网格；切换页面会关闭文件夹。
- 搜索结果仍为平铺应用（含文件夹内应用），不显示文件夹。

## 9. 测试与验证

### 自动化

- LaunchCore：测试中用 SQLite 建同结构数据库，验证读取的页面、顺序、文件夹、跳过另一根；数据库缺失与表缺失的错误；导入规则（对应、去重、空页、拆页、追加、摘要计数）；对齐规则（隐藏未安装、空文件夹、空页、追加）；布局存储（备份互换、损坏备份、含文件夹编码往返）。
- LaunchApp：模型（布局分页、打开/关闭文件夹、Esc 三层、打字关闭文件夹、唤起回到网格、搜索不受影响）；控制器（点击背景的两种结果）；`LayoutCoordinator` 用假提示框与假数据库来源验证首次导入、暂不、无数据库、已有布局追加、损坏文件只读、重新导入备份、恢复互换；布局尺寸（5 行面板放得下）。

### 离线渲染

三种屏幕尺寸下渲染：带文件夹的网格、「效率」展开、「其他」展开，交用户确认样式。

### 端到端（安装版）

首次启动预览出现并导入；生成布局文件；点开文件夹、启动成员；Esc 三层；重新导入生成备份；恢复互换。结果记入 `docs/manual-verification.md`。
