import AppKit
import LaunchCore
import SwiftUI

struct ExtraItemsSettingsView: View {
    @Bindable var controller: ExtraItemsController
    let currentPage: () -> Int

    var body: some View {
        Form {
            Section("网址") {
                Button("添加网址…") { ExtraItemEditor.showWebsite(controller: controller) }
                    .disabled(!controller.canEdit)
                if websites.isEmpty { Text("还没有网址").foregroundStyle(.secondary) }
                ForEach(websites) { item in row(item) }
            }
            Section {
                HStack {
                    Button("刷新快捷指令") { Task { await controller.refreshShortcuts() } }
                        .disabled(controller.isRefreshing)
                    if controller.isRefreshing { ProgressView().controlSize(.small) }
                }
                if let error = controller.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
                if shortcuts.isEmpty && !controller.isRefreshing { Text("没有找到快捷指令").foregroundStyle(.secondary) }
                ForEach(shortcuts) { item in row(item) }
            } header: { Text("快捷指令") }
        }
        .formStyle(.grouped)
    }

    private var websites: [LaunchItem] { controller.items.filter { if case .website = $0.target { true } else { false } } }
    private var shortcuts: [LaunchItem] { controller.items.filter { if case .shortcut = $0.target { true } else { false } } }

    private func row(_ item: LaunchItem) -> some View {
        HStack(spacing: 10) {
            LaunchItemIcon(item: item, side: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).lineLimit(1)
                if case .website(let url) = item.target {
                    Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let reason = item.unavailableReason { Text(reason).font(.caption).foregroundStyle(.orange).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if controller.fetchingIcons.contains(item.identity) { ProgressView().controlSize(.mini) }
            Menu {
                if controller.isPinned(item.identity) {
                    Button("从网格移除") { controller.unpin(item.identity) }
                } else {
                    Button("添加到网格") { controller.pin(item.identity, toPage: currentPage()) }
                }
                if case .website = item.target {
                    Button("编辑网址…") {
                        ExtraItemEditor.showWebsite(controller: controller, existing: controller.definitions.first { $0.identity == item.identity })
                    }
                    Button("刷新网站图标") { controller.refreshWebsiteIcon(item.identity) }
                }
                Button("更换图标…") { ExtraItemEditor.showAppearance(item: item, controller: controller) }
                Button("恢复默认图标") {
                    do { try controller.updateAppearance(of: item.identity, name: nil, customIconData: nil) }
                    catch { _ = NSAlert(error: error).runAboveLauncher() }
                }
                if case .website = item.target {
                    Divider()
                    Button("删除网址入口…", role: .destructive) { ExtraItemEditor.confirmDelete(item, controller: controller) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!controller.canEdit)
            .accessibilityLabel("\(item.displayName) 的操作")
        }
        .padding(.vertical, 3)
    }
}
