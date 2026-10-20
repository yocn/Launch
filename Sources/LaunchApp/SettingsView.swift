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
            Picker("重新打开时", selection: $settings.reopenBehavior) {
                Text("停在上次的位置").tag(ReopenBehavior.resume)
                Text("回到第一页").tag(ReopenBehavior.firstPage)
            }
            .pickerStyle(.radioGroup)
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
                            Image(nsImage: IconCache.shared.icon(for: app.identity.path))
                                .resizable()
                                .frame(width: 24, height: 24)
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
