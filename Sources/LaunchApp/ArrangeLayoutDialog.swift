import AppKit
import LaunchCore

@MainActor
final class ArrangeLayoutDialog: NSObject {
    private let pageCount: Int
    private let currentPage: Int
    private var options = ArrangeOptions()
    private let alert = NSAlert()
    private let fillBox = NSButton(checkboxWithTitle: "填满空位", target: nil, action: nil)
    private let ungroupBox = NSButton(checkboxWithTitle: "取消所有分组", target: nil, action: nil)
    private let categoryBox = NSButton(checkboxWithTitle: "按类型分组", target: nil, action: nil)
    private var scopeButtons: [(ArrangeOptions.Scope, NSButton)] = []
    private var pageBoxes: [NSButton] = []
    private let selectAllPages = NSButton(title: "全选", target: nil, action: nil)

    static func run(pageCount: Int, currentPage: Int) -> LayoutArrangement? {
        ArrangeLayoutDialog(pageCount: pageCount, currentPage: currentPage).run()
    }

    private init(pageCount: Int, currentPage: Int) {
        self.pageCount = pageCount
        self.currentPage = currentPage
    }

    private func run() -> LayoutArrangement? {
        alert.messageText = "整理布局"
        alert.informativeText = "整理后可按 ⌘Z 撤销。"
        alert.addButton(withTitle: "整理")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = makeAccessoryView()
        refresh()
        guard alert.runAboveLauncher() == .alertFirstButtonReturn else {
            return nil
        }
        return options.arrangement(currentPage: currentPage, pageCount: pageCount)
    }

    private func makeAccessoryView() -> NSView {
        for box in [fillBox, ungroupBox, categoryBox] {
            box.target = self
            box.action = #selector(controlChanged)
        }
        fillBox.state = options.fillsGaps ? .on : .off
        ungroupBox.state = options.ungroupsFolders ? .on : .off
        categoryBox.state = options.groupsByCategory ? .on : .off
        scopeButtons = [
            (.currentPage, "当前页（第 \(currentPage + 1) 页）"),
            (.chosenPages, "选择页面"),
            (.allPages, "全部页面"),
        ].map { scope, title in
            let button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(controlChanged))
            button.state = scope == options.scope ? .on : .off
            return (scope, button)
        }
        pageBoxes = (0 ..< pageCount).map { page in
            NSButton(checkboxWithTitle: "第 \(page + 1) 页", target: self, action: #selector(controlChanged))
        }
        selectAllPages.target = self
        selectAllPages.action = #selector(chooseAllPages)
        selectAllPages.bezelStyle = .rounded
        selectAllPages.controlSize = .small

        let pageRows = stride(from: 0, to: pageBoxes.count, by: 5).map { start in
            NSStackView(views: Array(pageBoxes[start ..< min(start + 5, pageBoxes.count)]))
        }
        let pages = NSStackView(views: pageRows + [selectAllPages])
        pages.orientation = .vertical
        pages.alignment = .leading
        pages.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)

        let stack = NSStackView(views: [
            heading("规则"),
            fillBox,
            note("把范围内的页面连成一串重新排满，去掉排空的页"),
            ungroupBox,
            note("文件夹拆开，成员放到所在页末尾"),
            categoryBox,
            note("散落的应用按 App Store 类别归入文件夹，新文件夹放在最后"),
            heading("范围"),
        ] + scopeButtons.map(\.1) + [pages])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: stack.views[6])
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        return stack
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func controlChanged(_ sender: NSButton) {
        if let scope = scopeButtons.first(where: { $0.1 === sender })?.0 {
            options.scope = scope
        }
        options.fillsGaps = fillBox.state == .on
        options.ungroupsFolders = ungroupBox.state == .on
        options.groupsByCategory = categoryBox.state == .on
        options.chosenPages = Set(pageBoxes.indices.filter { pageBoxes[$0].state == .on })
        refresh()
    }

    @objc private func chooseAllPages() {
        pageBoxes.forEach { $0.state = .on }
        controlChanged(selectAllPages)
    }

    private func refresh() {
        for (scope, button) in scopeButtons {
            button.state = scope == options.scope ? .on : .off
        }
        fillBox.isEnabled = options.canFillGaps(currentPage: currentPage, pageCount: pageCount)
        let choosing = options.scope == .chosenPages
        pageBoxes.forEach { $0.isEnabled = choosing }
        selectAllPages.isEnabled = choosing
        alert.buttons.first?.isEnabled = options.arrangement(currentPage: currentPage, pageCount: pageCount) != nil
    }
}
