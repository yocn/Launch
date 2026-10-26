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

private struct BookmarkPickerView: View {
    @Bindable var model: BookmarkPickerModel

    var body: some View {
        VStack(spacing: 8) {
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
            } else if model.query.isEmpty {
                List { OutlineGroup(model.tree, children: \.optionalChildren) { row($0) } }
            } else {
                List(model.searchResults) { row($0) }
            }
            Text("已选 \(model.selected.count) 个").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 440, height: 380)
    }

    @ViewBuilder private func row(_ node: BookmarkNode) -> some View {
        if let url = node.url {
            let added = model.existing.contains(url)
            Toggle(isOn: Binding(
                get: { model.selected.contains(node.id) },
                set: { if $0 { model.selected.insert(node.id) } else { model.selected.remove(node.id) } }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name).lineLimit(1)
                    Text(added ? "已添加" : url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .disabled(added)
        } else {
            Label(node.name, systemImage: "folder")
        }
    }
}

private extension BookmarkNode {
    var optionalChildren: [BookmarkNode]? { isFolder ? children : nil }
}

@MainActor enum BookmarkPicker {
    static func show(controller: ExtraItemsController, toPage page: Int?) {
        let existing = Set(controller.definitions.compactMap { entry -> URL? in
            if case .website(let url) = entry.target { url } else { nil }
        })
        let model = BookmarkPickerModel(existing: existing)
        let alert = NSAlert()
        alert.messageText = "从浏览器书签添加网址"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        let host = NSHostingView(rootView: BookmarkPickerView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 380)
        alert.accessoryView = host
        guard alert.runAboveLauncher() == .alertFirstButtonReturn, !model.selected.isEmpty else { return }
        controller.addWebsites(model.links(for: model.selected), toPage: page)
    }
}
