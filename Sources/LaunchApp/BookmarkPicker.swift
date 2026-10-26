import AppKit
import LaunchCore
import SwiftUI

@MainActor @Observable
private final class BookmarkPickerModel {
    var browser: BookmarkBrowser = .chrome { didSet { load() } }
    var query = ""
    private(set) var tree: [BookmarkNode] = []
    private(set) var error: String?
    var selected: Set<UUID> = []
    let existing: Set<URL>

    init(existing: Set<URL>) {
        self.existing = existing
        load()
    }

    func load() {
        selected = []
        do { tree = try BrowserBookmarks.load(browser); error = nil }
        catch { tree = []; self.error = error.localizedDescription }
    }

    var searchResults: [BookmarkNode] { BrowserBookmarks.links(in: tree, matching: query) }
    var needsFullDiskAccess: Bool { browser == .safari && error?.contains("完全磁盘访问") == true }

    func links(for ids: Set<UUID>) -> [(name: String, url: URL)] {
        BrowserBookmarks.links(in: tree, matching: "").compactMap { node in
            ids.contains(node.id) ? node.url.map { (node.name, $0) } : nil
        }
    }
}

private struct BookmarkRow: Identifiable {
    let id = UUID()
    let node: BookmarkNode
    let depth: Int
}

private struct BookmarkPickerView: View {
    @Bindable var model: BookmarkPickerModel
    let onFinish: (Bool) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("从浏览器书签添加网址").font(.headline)
            Picker("", selection: $model.browser) {
                ForEach(BookmarkBrowser.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("搜索名称或网址", text: $model.query).textFieldStyle(.roundedBorder)
            if let error = model.error {
                VStack(spacing: 8) {
                    Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if model.needsFullDiskAccess {
                        Button("打开系统设置") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { row in
                    if row.node.isFolder {
                        Label(row.node.name.isEmpty ? "未命名文件夹" : row.node.name, systemImage: "folder")
                            .font(.subheadline.weight(.semibold))
                            .padding(.leading, CGFloat(row.depth) * 14)
                    } else {
                        bookmark(row.node, depth: row.depth)
                    }
                }
                .listStyle(.inset)
            }
            HStack {
                Text("已选 \(model.selected.count) 个").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { onFinish(false) }.keyboardShortcut(.cancelAction)
                Button("添加") { onFinish(true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selected.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460, height: 460)
    }

    // 搜索时平铺结果，否则按文件夹层级平铺显示
    private var rows: [BookmarkRow] {
        if !model.query.isEmpty { return model.searchResults.map { BookmarkRow(node: $0, depth: 0) } }
        func flatten(_ nodes: [BookmarkNode], _ depth: Int) -> [BookmarkRow] {
            nodes.flatMap { [BookmarkRow(node: $0, depth: depth)] + flatten($0.children, depth + 1) }
        }
        return flatten(model.tree, 0)
    }

    private func bookmark(_ node: BookmarkNode, depth: Int) -> some View {
        let url = node.url!
        let added = model.existing.contains(url)
        return Toggle(isOn: Binding(
            get: { model.selected.contains(node.id) },
            set: { if $0 { model.selected.insert(node.id) } else { model.selected.remove(node.id) } }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).lineLimit(1)
                Text(added ? "已添加" : url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(added)
        .padding(.leading, CGFloat(depth) * 14)
    }
}

@MainActor enum BookmarkPicker {
    static func show(controller: ExtraItemsController, toPage page: Int?) {
        let existing = Set(controller.definitions.compactMap { entry -> URL? in
            if case .website(let url) = entry.target { url } else { nil }
        })
        let model = BookmarkPickerModel(existing: existing)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "书签"
        var confirmed = false
        panel.contentView = NSHostingView(rootView: BookmarkPickerView(model: model) { ok in
            confirmed = ok
            NSApp.stopModal()
        })
        panel.center()
        // 与警告框相同：模态循环里再把层级抬到启动器之上
        RunLoop.main.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated { panel.level = .aboveLauncher }
        }
        let closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
            NSApp.stopModal()
        }
        NSApp.runModal(for: panel)
        NotificationCenter.default.removeObserver(closing)
        panel.orderOut(nil)
        guard confirmed, !model.selected.isEmpty else { return }
        controller.addWebsites(model.links(for: model.selected), toPage: page)
    }
}
