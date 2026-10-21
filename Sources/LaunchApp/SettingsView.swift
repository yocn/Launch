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
        }
        .frame(width: 520, height: 440)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: LauncherSettings
    let loginItemService: LoginItemService
    let hasHotKeyConflict: () -> Bool

    @State private var startsAtLogin = false
    @State private var hasConflict = false

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
            Toggle("显示菜单栏图标", isOn: $settings.showsMenuBarIcon)
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
        }
        .formStyle(.grouped)
        .onAppear {
            startsAtLogin = loginItemService.isEnabled
            hasConflict = hasHotKeyConflict()
        }
    }

    private func setStartsAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
        } catch {
            NSAlert(error: error).runModal()
        }
        startsAtLogin = loginItemService.isEnabled
    }
}

private struct AppearanceSettingsView: View {
    @Bindable var settings: LauncherSettings

    var body: some View {
        Form {
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
            Section("网格") {
                Stepper("列数：\(settings.gridColumns)", value: $settings.gridColumns, in: GridSize.columnRange)
                Stepper("行数：\(settings.gridRows)", value: $settings.gridRows, in: GridSize.rowRange)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HiddenAppsSettingsView: View {
    @Bindable var settings: LauncherSettings
    let model: LauncherModel
    let onUnhide: (CatalogApp) -> Void
    let onUnhideAll: () -> Void

    var body: some View {
        Form {
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
}
