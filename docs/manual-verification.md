# 手动验证记录

每次在目标 Mac 上验证交互后，在对应条目下补充日期、显示器配置、系统状态、执行结果和已知限制。

## 基础命令

    swift build
    swift test
    swift run LaunchApp
    ./scripts/build-app.sh

## 当前结果

- 2026-10-19：开发用应用包可启动，覆盖窗口显示本机 /Applications 中的应用网格；搜索值设为 chat 时筛选出 ChatGPT 与 WeChat。
- 2026-10-19：自动化的键盘文本注入和 Escape 未能到达 SwiftUI 搜索框，尽管搜索数据绑定本身已验证。搜索框会在出现时请求焦点，仍需由真人在目标机验证实际键盘输入与 Escape 关闭。
- 2026-10-19：以只读方式检查 `/Users/yocn/Library/Application Support` 和 `/Users/yocn/Library/Containers` 的常见候选名，未确认旧 Launchpad 布局来源；未读取、修改或重置系统数据。
- 2026-10-19：确认原生无边框 `NSPanel.canBecomeKey` 为 `false`，这会阻断搜索框的真实键盘焦点。开发包已改用覆写该能力的 `LauncherPanel`；对应自动化测试通过。后续界面回归因自动化环境的 ScreenCaptureKit 取屏失败而未能完成，仍需真人验证文本输入与 Escape。

## 待验证

- 鼠标所在显示器的覆盖窗口。
- 空格、全屏应用和台前调度场景。
- 搜索、Esc 关闭和应用启动。
- 旧 Launchpad 数据来源的可读性与布局映射范围。
