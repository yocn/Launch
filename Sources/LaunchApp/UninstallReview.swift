import AppKit

private final class UninstallListDocument: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class UninstallReview: NSObject {
    private let plan: ResidualPlan
    private let isRunning: Bool
    private var boxes: [(ResidualItem, NSButton)] = []
    private let summary = NSTextField(labelWithString: "")

    init(plan: ResidualPlan, isRunning: Bool) {
        self.plan = plan
        self.isRunning = isRunning
    }

    func run() -> Set<String>? {
        let alert = NSAlert()
        alert.messageText = "卸载“\(plan.app.displayName)”"
        alert.informativeText = "只默认选择应用本体。关联文件可能包含账号、历史记录和个人数据，请逐项检查。\(isRunning ? "应用正在运行，确认后先请求正常退出。" : "")"
        alert.addButton(withTitle: isRunning ? "退出并移到废纸篓" : "移到废纸篓")
        alert.addButton(withTitle: "取消")
        alert.icon = NSWorkspace.shared.icon(forFile: plan.app.identity.path)
        alert.accessoryView = makeContent()
        guard alert.runAboveLauncher() == .alertFirstButtonReturn else { return nil }
        return Set(boxes.filter { $0.0.isSelectable && $0.1.state == .on }.map { $0.0.id })
    }

    // 不操作文件系统，供视图验收使用。
    func makeContent() -> NSView {
        boxes = []
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        let application = NSButton(checkboxWithTitle: "\(plan.app.displayName) — 应用本体", target: nil, action: nil)
        application.state = .on
        application.isEnabled = false
        stack.addArrangedSubview(application)
        stack.addArrangedSubview(label(plan.app.identity.path, secondary: true))
        for item in plan.items {
            let bytes = item.snapshot.map { ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file) } ?? "大小未知"
            let box = NSButton(checkboxWithTitle: "\(item.category) — \(bytes)", target: self, action: #selector(changed))
            box.state = .off
            box.isEnabled = item.isSelectable
            box.setAccessibilityLabel("\(item.category)：\(item.url.lastPathComponent)")
            boxes.append((item, box))
            let row = NSStackView(views: [box, label(item.url.path, secondary: true), label(item.blockedReason ?? item.evidence, secondary: true)])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 4
            row.setAccessibilityLabel(item.url.path)
            stack.addArrangedSubview(row)
        }
        if plan.items.isEmpty { stack.addArrangedSubview(label("未找到可列出的关联文件；扫描范围有限。", secondary: true)) }
        for notice in plan.notices { stack.addArrangedSubview(label(notice, secondary: true)) }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        // 清单放得下时不显示滚动条
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        // 翻转文档坐标，让短清单从顶部显示；不把文档顶边绑到非翻转的 clipView。
        let height = stack.fittingSize.height
        let document = UninstallListDocument(frame: NSRect(x: 0, y: 0, width: 544, height: height + 16))
        stack.frame = NSRect(x: 8, y: 8, width: 528, height: height)
        stack.autoresizingMask = [.width]
        document.addSubview(stack)
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // 高度随清单内容，超过上限才滚动
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: 560),
            scroll.heightAnchor.constraint(equalToConstant: min(document.frame.height, 330)),
        ])
        summary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let content = NSStackView(views: [scroll, summary,
            label("只移到废纸篓。完成后可查看记录，按原路径找回文件。", secondary: true)])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        changed()
        // NSAlert 按 accessoryView.frame 留空间，不会按 Auto Layout 的 intrinsic size 自动扩展。
        content.setFrameSize(NSSize(width: 560, height: content.fittingSize.height))
        content.layoutSubtreeIfNeeded()
        return content
    }

    private func label(_ text: String, secondary: Bool) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.isSelectable = true
        field.preferredMaxLayoutWidth = 530
        field.widthAnchor.constraint(lessThanOrEqualToConstant: 530).isActive = true
        return field
    }

    @objc private func changed() {
        let selected = boxes.filter { $0.0.isSelectable && $0.1.state == .on }
        let bytes = selected.reduce(Int64(0)) { $0 + ($1.0.snapshot?.bytes ?? 0) }
        summary.stringValue = "应用本体 + \(selected.count) 项关联文件（\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))）"
    }
}
