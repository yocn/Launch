# Launch：macOS 应用启动器

目标是制作可日常使用的 LaunchOS 替代品。项目工作目录：`/Users/yocn/launch`。

## 接手入口

1. 阅读 [技术架构与产品约定](docs/architecture.md)，了解已确认需求、职责边界与待验证事项。
2. 阅读 [协作约定](AGENTS.md)。Claude 同时可以从 [CLAUDE.md](CLAUDE.md) 进入。
3. 从架构文档的“建议实施顺序”开始，先检查实际项目状态再继续工作。

## 当前状态（2026-10-19）

- 已观察本机 LaunchOS 主界面、搜索、菜单及部分设置页面，并完成初步架构讨论。
- 已核实开发机为 macOS 26.6.1（25G76），安装 Xcode 27.0（27A266a）。
- 已建立可运行的 Swift Package 原型：扫描用户与系统应用目录，展示分页网格并即时筛选。第 1 期常驻唤起已完成：后台常驻、⌥Space 与菜单栏唤起、多屏按主显示器布局等比缩放、目录变化自动刷新、开机启动开关、LaunchOS 快捷键冲突提示。第 2 期布局继承已完成：首次启动预览并只读导入旧 Launchpad 布局（页面、顺序、文件夹），布局保存在 `~/Library/Application Support/Launch/layout.json`，可从菜单栏重新导入或与备份互换恢复；未安装应用保留位置不显示，新应用追加到末尾；文件夹可展开、启动成员、点面板外或 Esc 分层关闭。第 3 期键盘与翻页已完成：方向键选中、Return 启动或打开文件夹、搜索时自动选中第一个结果、⌘←/⌘→ 与滚轮翻页并横向滑动、鼠标拖动与触控板横扫跟手翻页（越界阻尼回弹）、文件夹内键盘导航与分页、文件夹从格子放大展开，拼音组字时按键交给输入法。第 4a 期拖拽重排与文件夹编辑已完成：在图标上直接拖动即可页内或跨页移动（指针停在边缘自动翻页，满页时挤到下一页），拖到应用上合并为「未命名」文件夹，拖入、拖出文件夹及文件夹内排序，点击文件夹标题改名，⌘Z 撤销最近 20 步编辑；从图标上拖动不再翻页，只有空白处拖动翻页。多选、右键菜单、隐藏应用（4b/4c）和 F4/手势等系统入口仍未实现。验证结果与未验证项见 [手动验证记录](docs/manual-verification.md)。
- `./scripts/build-app.sh` 在 `.build/Launch.app` 生成开发用应用包；`./scripts/build-app.sh --install` 以 release 构建并安装到 `~/Applications/Launch.app`，可用环境变量 `LAUNCH_SIGN_IDENTITY` 指定签名证书（固定证书可让开机启动在重装后保持）。
- 旧 Launchpad 数据库位于 `$(getconf DARWIN_USER_DIR)/com.apple.dock.launchpad/db/db`，含 2 个有内容的页面、3 个文件夹、96 个应用；导入规则见 [布局继承设计](docs/superpowers/specs/2026-10-19-layout-inheritance-design.md)。
- `Launch` 是暂用项目名，正式产品名和 Bundle ID 尚未确定。

请勿将架构方案、建议实施顺序或文档中的验收要求视为已经实现或验证的能力。
