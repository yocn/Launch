import AppKit
import KeyboardShortcuts
import LaunchCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: LauncherSettings
    let model: LauncherModel
    let loginItemService: LoginItemService
    let hasHotKeyConflict: () -> Bool
    let onUnhide: (CatalogApp) -> Void
    let onUnhideAll: () -> Void
    let data: DataSettingsActions

    var body: some View {
        TabView {
            GeneralSettingsView(
                settings: settings,
                loginItemService: loginItemService,
                hasHotKeyConflict: hasHotKeyConflict
            )
            .tabItem { Label("通用", systemImage: "gearshape") }
            AppearanceSettingsView(settings: settings)
                .tabItem { Label("外观", systemImage: "paintpalette") }
            HiddenAppsSettingsView(settings: settings, model: model, onUnhide: onUnhide, onUnhideAll: onUnhideAll)
                .tabItem { Label("应用", systemImage: "eye.slash") }
            DataSettingsView(actions: data)
                .tabItem { Label("数据", systemImage: "externaldrive") }
        }
        // 表单不画自己的底，透出窗口的玻璃
        .scrollContentBackground(.hidden)
        .buttonStyle(.glass)
        .frame(width: 520, height: 440)
    }
}

struct DataSettingsActions {
    // 返回显示在页面上的结果文字；取消或失败时为空
    let exportLayout: () -> String?
    let exportDiagnostics: () async -> String?
    let importLayout: () -> String?
    let canImportLaunchpad: () -> Bool
    let importLaunchpad: () -> Void
    let canRestore: () -> Bool
    let restoreLayout: () -> Void
}

private struct DataSettingsView: View {
    let actions: DataSettingsActions

    @State private var status: String?
    @State private var refresh = 0

    var body: some View {
        Form {
            Section("布局备份") {
                HStack {
                    Button("导出布局…") {
                        status = actions.exportLayout() ?? status
                    }
                    Button("导入布局…") {
                        status = actions.importLayout() ?? status
                        refresh += 1
                    }
                }
                if let status {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Section {
                Button("导出诊断信息…") {
                    Task {
                        if let result = await actions.exportDiagnostics() {
                            status = result
                        }
                    }
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("包含日志、崩溃报告、设置、布局和系统信息，只保存到你选的位置")
            }
            Section("Launchpad") {
                Button("从 Launchpad 导入布局…") {
                    actions.importLaunchpad()
                    refresh += 1
                }
                .disabled(!actions.canImportLaunchpad())
                Button("恢复导入前的布局") {
                    actions.restoreLayout()
                    refresh += 1
                }
                .disabled(!actions.canRestore())
            }
            .id(refresh)
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: LauncherSettings
    let loginItemService: LoginItemService
    let hasHotKeyConflict: () -> Bool

    @State private var startsAtLogin = false
    @State private var hasConflict = false
    @State private var isTrusted = SystemInputTap.isTrusted

    var body: some View {
        Form {
            Toggle("开机启动", isOn: Binding(get: { startsAtLogin }, set: setStartsAtLogin))
                .disabled(!loginItemService.isAvailable)
            if !loginItemService.isAvailable {
                Text("需安装到 ~/Applications 后才能开机启动")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("唤起快捷键") {
                KeyboardShortcuts.Recorder(for: .toggleLauncher) { _ in
                    hasConflict = hasHotKeyConflict()
                }
            }
            if hasConflict {
                Text("⚠︎ 与 LaunchOS 的快捷键冲突")
                    .foregroundStyle(.orange)
            }
            Picker("显示在", selection: $settings.screenChoice) {
                Text("鼠标所在屏幕").tag(LauncherScreenChoice.mouse)
                Text("当前激活屏幕").tag(LauncherScreenChoice.active)
                Text("程序坞所在屏幕").tag(LauncherScreenChoice.dock)
                Text("主屏幕").tag(LauncherScreenChoice.main)
            }
            Picker("回到第一页", selection: $settings.returnToFirstPage) {
                Text("从不").tag(ReturnToFirstPage.never)
                Text("5 秒后").tag(ReturnToFirstPage.after5Seconds)
                Text("15 秒后").tag(ReturnToFirstPage.after15Seconds)
                Text("30 秒后").tag(ReturnToFirstPage.after30Seconds)
                Text("1 分钟后").tag(ReturnToFirstPage.after1Minute)
                Text("5 分钟后").tag(ReturnToFirstPage.after5Minutes)
                Text("始终").tag(ReturnToFirstPage.always)
            }
            Toggle("按住 Option 进入卸载模式", isOn: $settings.optionEntersUninstallMode)
            Picker("触发角", selection: $settings.hotCorner) {
                Text("关").tag(HotCorner.off)
                Text("左上角").tag(HotCorner.topLeft)
                Text("右上角").tag(HotCorner.topRight)
                Text("左下角").tag(HotCorner.bottomLeft)
                Text("右下角").tag(HotCorner.bottomRight)
            }
            if HotCornerConflicts.system(settings.hotCorner, value: { UserDefaults(suiteName: "com.apple.dock")?.object(forKey: $0) as? Int }) {
                Text("⚠︎ 与系统触发角冲突，可在「系统设置 → 桌面与程序坞 → 触发角」中调整")
                    .foregroundStyle(.orange)
            }
            if settings.hotCorner != .off, isLaunchOSUsing(settings.hotCorner) {
                Text("⚠︎ 可能与 LaunchOS 的触发角冲突")
                    .foregroundStyle(.orange)
            }
            Toggle("系统 F4 键", isOn: $settings.f4Launches)
            if settings.f4Launches {
                Text("按 F4 打开启动器，F4 原来的功能（本机为 Spotlight）不再响应，Spotlight 仍可用 ⌘空格")
                    .foregroundStyle(.secondary)
            }
            Picker("触控板", selection: $settings.pinchGesture) {
                Text("关").tag(PinchGesture.off)
                Text("三指捏合").tag(PinchGesture.threeFingers)
                Text("四指或五指捏合").tag(PinchGesture.fourOrFiveFingers)
                Text("五指捏合").tag(PinchGesture.fiveFingers)
            }
            if settings.pinchGesture == .fourOrFiveFingers, isSystemPinchEnabled {
                Text("⚠︎ 可能同时触发系统的「拇指加三指捏合」，可在「系统设置 → 触控板 → 更多手势」中关闭")
                    .foregroundStyle(.orange)
            }
            if settings.f4Launches || settings.pinchGesture != .off, !isTrusted {
                HStack {
                    Text("需要允许 Launch 使用辅助功能，才能接管 F4 键与触控板手势")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("授予权限…") {
                        SystemInputTap.requestPermission()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            startsAtLogin = loginItemService.isEnabled
            hasConflict = hasHotKeyConflict()
        }
        .task {
            // 授权在系统设置里完成，这里定时刷新状态
            while !Task.isCancelled {
                isTrusted = SystemInputTap.isTrusted
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // 系统「拇指加三指捏合」：2 为开启
    private var isSystemPinchEnabled: Bool {
        UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad")?.object(forKey: "TrackpadFourFingerPinchGesture") as? Int == 2
    }

    // 只读 LaunchOS 的设置，取值含义按其界面推测
    private func isLaunchOSUsing(_ corner: HotCorner) -> Bool {
        let id = "app.remixdesign.LaunchOS"
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty else {
            return false
        }
        let value = UserDefaults(suiteName: id)?.object(forKey: "HotCorner") as? Int
        return HotCornerConflicts.launchOSCorner(value) == corner
    }

    private func setStartsAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
        } catch {
            _ = NSAlert(error: error).runAboveLauncher()
        }
        startsAtLogin = loginItemService.isEnabled
    }
}

private struct AppearanceSettingsView: View {
    @Bindable var settings: LauncherSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section("应用图标") {
                HStack(spacing: 8) {
                    ForEach(AppIconStyle.allCases) { style in
                        iconChoice(style)
                    }
                }
                Picker("图标外观", selection: $settings.appIconTheme) {
                    ForEach(AppIconTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("显示在 ⌘Tab／程序坞", isOn: $settings.showsInAppSwitcher)
                Toggle("显示在状态栏", isOn: $settings.showsMenuBarIcon)
            }
            Picker("背景", selection: $settings.background) {
                Text("玻璃材质").tag(LauncherBackgroundStyle.glass)
                Text("模糊壁纸").tag(LauncherBackgroundStyle.blurredWallpaper)
                Text("系统壁纸").tag(LauncherBackgroundStyle.wallpaper)
            }
            .pickerStyle(.radioGroup)
            LabeledContent("暗度") {
                HStack {
                    Slider(value: $settings.dimming, in: 0 ... 0.8)
                    Text("\(Int((settings.dimming * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Toggle("隐藏图标名称", isOn: $settings.hidesNames)
            Toggle("显示程序坞", isOn: $settings.showsDock)
            LabeledContent("网格") {
                HStack(spacing: 6) {
                    Picker("列数", selection: $settings.gridColumns) {
                        ForEach(GridSize.columnRange, id: \.self) { Text("\($0) 列").tag($0) }
                    }
                    Text("×")
                        .foregroundStyle(.secondary)
                    Picker("行数", selection: $settings.gridRows) {
                        ForEach(GridSize.rowRange, id: \.self) { Text("\($0) 行").tag($0) }
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Picker("图标排列", selection: $settings.gridPlacement) {
                Text("铺满屏幕").tag(GridPlacement.spread)
                Text("集中在中央").tag(GridPlacement.centered)
            }
            .pickerStyle(.segmented)
            Section("设置窗口") {
                Picker("样式", selection: $settings.settingsWindowStyle) {
                    Text("玻璃").tag(SettingsWindowStyle.glass)
                    Text("普通").tag(SettingsWindowStyle.standard)
                }
                .pickerStyle(.segmented)
                if settings.settingsWindowStyle == .glass {
                    LabeledContent("不透明度") {
                        HStack {
                            Slider(value: $settings.settingsGlassOpacity, in: 0 ... 0.9)
                            Text("\(Int((settings.settingsGlassOpacity * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func iconChoice(_ style: AppIconStyle) -> some View {
        let selected = settings.appIconStyle == style
        let dark = settings.appIconTheme.isDark(systemIsDark: colorScheme == .dark)
        return Button {
            settings.appIconStyle = style
        } label: {
            VStack(spacing: 4) {
                if let image = AppIconAssets.image(style: style, dark: dark) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.15), lineWidth: 1)
        }
        .accessibilityLabel("应用图标：\(style.title)")
        .accessibilityValue(selected ? "已选择" : "未选择")
    }
}

private struct HiddenAppsSettingsView: View {
    @Bindable var settings: LauncherSettings
    let model: LauncherModel
    let onUnhide: (CatalogApp) -> Void
    let onUnhideAll: () -> Void

    @State private var skippedSources: [String] = []

    var body: some View {
        Form {
            Section {
                ForEach(ApplicationSources.defaultRoots(), id: \.path) { root in
                    SourceRow(path: root.path, onRemove: nil)
                }
                ForEach(settings.customSourcePaths, id: \.self) { path in
                    SourceRow(path: path) {
                        settings.customSourcePaths.removeAll { $0 == path }
                    }
                }
                Button("添加目录…", action: addSources)
                if !skippedSources.isEmpty {
                    Text("已在扫描范围内，跳过：\(skippedSources.map(SourceRow.displayPath).joined(separator: "、"))")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("应用来源")
            } footer: {
                Text("子文件夹一并扫描")
            }
            Toggle("在搜索结果中显示隐藏应用", isOn: $settings.showsHiddenAppsInSearch)
            Section("隐藏的应用") {
                if model.hiddenApps.isEmpty {
                    Text("没有隐藏的应用")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.hiddenApps, id: \.identity) { app in
                        HStack {
                            AppIconImage(path: app.identity.path, side: 24)
                            Text(app.displayName)
                            Spacer()
                            Button("取消隐藏") {
                                onUnhide(app)
                            }
                        }
                    }
                }
            }
            Button("全部取消隐藏", action: onUnhideAll)
                .disabled(model.hiddenApps.isEmpty)
        }
        .formStyle(.grouped)
    }

    private func addSources() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        guard panel.runAboveLauncher() == .OK else {
            return
        }
        let result = ApplicationSources.adding(panel.urls, to: settings.customSourcePaths)
        settings.customSourcePaths = result.custom
        skippedSources = result.skipped
    }
}

private struct SourceRow: View {
    let path: String
    var onRemove: (() -> Void)?

    static func displayPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(Self.displayPath(path))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let onRemove {
                if !FileManager.default.fileExists(atPath: path) {
                    Text("不存在")
                        .foregroundStyle(.secondary)
                }
                Button("移除", action: onRemove)
            } else {
                Text("默认路径")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
