# Launch：macOS 应用启动器

目标是制作可日常使用的 LaunchOS 替代品。项目工作目录：`/Users/yocn/launch`。

## 接手入口

1. 阅读 [技术架构与产品约定](docs/architecture.md)，了解已确认需求、职责边界与待验证事项。
2. 阅读 [协作约定](AGENTS.md)。Claude 同时可以从 [CLAUDE.md](CLAUDE.md) 进入。
3. 从架构文档的“建议实施顺序”开始，先检查实际项目状态再继续工作。

## 当前状态（2026-10-19）

- 已观察本机 LaunchOS 主界面、搜索、菜单及部分设置页面，并完成初步架构讨论。
- 已核实开发机为 macOS 26.6.1（25G76），安装 Xcode 27.0（27A266a）。
- 已建立可运行的 Swift Package 原型：扫描用户与系统应用目录，展示分页网格并即时筛选。第 1 期常驻唤起已完成：后台常驻、⌥Space 与菜单栏唤起、多屏按主显示器布局等比缩放、目录变化自动刷新、开机启动开关、LaunchOS 快捷键冲突提示。布局编辑、旧布局导入和 F4/手势等系统入口仍未实现。验证结果与未验证项见 [手动验证记录](docs/manual-verification.md)。
- `./scripts/build-app.sh` 在 `.build/Launch.app` 生成开发用应用包；`./scripts/build-app.sh --install` 以 release 构建并安装到 `~/Applications/Launch.app`，可用环境变量 `LAUNCH_SIGN_IDENTITY` 指定签名证书（固定证书可让开机启动在重装后保持）。
- 旧 Launchpad 数据库位于 `$(getconf DARWIN_USER_DIR)/com.apple.dock.launchpad/db/db`，只读检查确认含 2 个有内容的页面、3 个文件夹、96 个应用（81 个可对应本机应用）；导入功能属于第 2 期。
- `Launch` 是暂用项目名，正式产品名和 Bundle ID 尚未确定。

请勿将架构方案、建议实施顺序或文档中的验收要求视为已经实现或验证的能力。
