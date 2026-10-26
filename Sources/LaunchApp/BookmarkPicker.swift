import AppKit
import LaunchCore
import SwiftUI

@MainActor @Observable
private final class BookmarkPickerModel {
    var browser: BookmarkBrowser = .chrome { didSet { load() } }
    var query = "" { didSet { rebuildRows() } }
    private(set) var tree: [BookmarkNode] = []
    private(set) var rows: [BookmarkRow] = []
    private(set) var error: String?
    private(set) var isLoading = false
    var selected: Set<UUID> = []
    // 文件夹默认折叠
    private(set) var expanded: Set<UUID> = []
    let existing: Set<URL>
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(existing: Set<URL>) {
        self.existing = existing
        load()
    }

    // 读文件和解析放到后台，切换浏览器时作废上一次
    func load() {
        loadTask?.cancel()
        selected = []
        expanded = []
        isLoading = true
        let browser = browser
        loadTask = Task {
            let result = await Task.detached { Result { try BrowserBookmarks.load(browser) } }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let nodes): tree = nodes; error = nil
            case .failure(let failure): tree = []; error = failure.localizedDescription
            }
            rebuildRows()
            isLoading = false
        }
    }

    private func rebuildRows() {
        if !query.isEmpty {
            rows = BrowserBookmarks.links(in: tree, matching: query).map { BookmarkRow(node: $0, depth: 0) }
            return
        }
        func flatten(_ nodes: [BookmarkNode], _ depth: Int) -> [BookmarkRow] {
            nodes.flatMap { node in
                [BookmarkRow(node: node, depth: depth)] + (expanded.contains(node.id) ? flatten(node.children, depth + 1) : [])
            }
        }
        rows = flatten(tree, 0)
    }

    func toggle(_ folder: BookmarkNode) {
        if !expanded.insert(folder.id).inserted { expanded.remove(folder.id) }
        rebuildRows()
    }

    var needsFullDiskAccess: Bool { browser == .safari && error?.contains("完全磁盘访问") == true }

    func links(for ids: Set<UUID>) -> [(name: String, url: URL, icon: Data?)] {
        BrowserBookmarks.links(in: tree, matching: "").compactMap { node in
            ids.contains(node.id) ? node.url.map { (node.name, $0, node.icon) } : nil
        }
    }
}

struct BookmarkRow: Identifiable {
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
            if model.isLoading {
                ProgressView("正在读取书签…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error {
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
                List(model.rows) { row in
                    if row.node.isFolder {
                        Button { model.toggle(row.node) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: model.expanded.contains(row.node.id) ? "chevron.down" : "chevron.right")
                                    .font(.caption2.weight(.bold)).frame(width: 10)
                                Label(row.node.name.isEmpty ? "未命名文件夹" : row.node.name, systemImage: "folder")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(row.node.children.count)").font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

    private func bookmark(_ node: BookmarkNode, depth: Int) -> some View {
        let url = node.url!
        let added = model.existing.contains(url)
        let icon = node.icon.flatMap(NSImage.init(data:))
        let isOn = model.selected.contains(node.id)
        return Button {
            if isOn { model.selected.remove(node.id) } else { model.selected.insert(node.id) }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Group {
                    if let icon { Image(nsImage: icon).resizable().interpolation(.high) }
                    else { Image(systemName: "globe").foregroundStyle(.secondary) }
                }
                .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name).lineLimit(1)
                    Text(added ? "已添加" : url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
        .opacity(added ? 0.5 : 1)
        .padding(.leading, CGFloat(depth) * 14)
    }
}

@MainActor enum BookmarkPicker {
    private static var panel: NSPanel?
    private static var closing: NSObjectProtocol?

    // 非模态：模态循环里后台任务的结果回不到界面，加载会一直转圈
    static func show(controller: ExtraItemsController, toPage page: Int?) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let existing = Set(controller.definitions.compactMap { entry -> URL? in
            if case .website(let url) = entry.target { url } else { nil }
        })
        let model = BookmarkPickerModel(existing: existing)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "书签"
        panel.level = .aboveLauncher
        panel.contentView = NSHostingView(rootView: BookmarkPickerView(model: model) { ok in
            if ok, !model.selected.isEmpty {
                controller.addWebsites(model.links(for: model.selected), toPage: page)
            }
            panel.close()
        })
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { finish() }
        }
        self.panel = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private static func finish() {
        if let closing { NotificationCenter.default.removeObserver(closing) }
        closing = nil
        panel = nil
    }
}
