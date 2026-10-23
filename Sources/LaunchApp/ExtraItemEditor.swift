import AppKit
import LaunchCore
import UniformTypeIdentifiers

@MainActor private final class EntryIconSelection: NSObject {
    var data: Data?
    let preview: NSImageView
    private let fallback: NSImage?
    init(data: Data?, displayData: Data?, fallbackSymbol: String) {
        self.data = data
        fallback = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil)
        preview = NSImageView(frame: NSRect(x: 62, y: 44, width: 48, height: 48))
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.image = displayData.flatMap { ItemImageData.normalized($0) }.flatMap(NSImage.init(data:)) ?? fallback
        super.init()
    }
    @objc func choose() {
        if let chosen = ExtraItemEditor.chooseIcon() { data = chosen; preview.image = NSImage(data: chosen) }
    }
    @objc func reset() { data = nil; preview.image = fallback }
}

@MainActor enum ExtraItemEditor {
    static func showWebsite(controller: ExtraItemsController, existing: ExtraItemDefinition? = nil, toPage page: Int? = nil) {
        let alert = NSAlert()
        alert.messageText = existing == nil ? "添加网址" : "编辑网址"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        let name = field(existing?.name ?? "", placeholder: "名称", y: 148, in: view)
        label("名称", y: 148, in: view)
        let initialAddress: String = if case .website(let url) = existing?.target { url.absoluteString } else { "" }
        let address = field(initialAddress, placeholder: "https://example.com", y: 110, in: view)
        label("网址", y: 110, in: view)
        let icons = iconSelection(existing, symbol: "globe", in: view)
        let error = errorLabel(in: view)
        alert.accessoryView = view
        alert.window.initialFirstResponder = name
        while alert.runAboveLauncher() == .alertFirstButtonReturn {
            do {
                _ = try controller.saveWebsite(name: name.stringValue, address: address.stringValue,
                                               existing: existing, toPage: page, customIconData: icons.data)
                return
            } catch let failure { error.stringValue = failure.localizedDescription }
        }
    }

    static func showAppearance(item: LaunchItem, controller: ExtraItemsController) {
        guard item.application == nil else { return }
        let alert = NSAlert()
        alert.messageText = "更换图标"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 142))
        let name = field(item.displayName, placeholder: "名称", y: 110, in: view)
        label("名称", y: 110, in: view)
        let existing = controller.definitions.first { $0.identity == item.identity }
        let symbol: String = if case .shortcut = item.target { "square.3.layers.3d" } else { "globe" }
        let icons = iconSelection(existing, symbol: symbol, in: view)
        let error = errorLabel(in: view)
        alert.accessoryView = view
        alert.window.initialFirstResponder = name
        while alert.runAboveLauncher() == .alertFirstButtonReturn {
            do { try controller.updateAppearance(of: item.identity, name: name.stringValue, customIconData: icons.data); return }
            catch let failure { error.stringValue = failure.localizedDescription }
        }
    }

    static func chooseIcon() -> Data? {
        let panel = NSOpenPanel()
        panel.title = "选择图标"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.level = .aboveLauncher
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let limit = 16 * 1024 * 1024
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit else {
                throw ExtraIconError.invalidImage
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard let image = ItemImageData.normalized(data, inputLimit: limit) else { throw ExtraIconError.invalidImage }
            return image
        } catch { _ = NSAlert(error: error).runAboveLauncher(); return nil }
    }

    static func confirmDelete(_ item: LaunchItem, controller: ExtraItemsController) {
        guard case .website = item.target else { return }
        let alert = NSAlert()
        alert.messageText = "删除网址“\(item.displayName)”？"
        alert.informativeText = "只移除 Launch 中的入口，可用 ⌘Z 撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if alert.runAboveLauncher() == .alertFirstButtonReturn { controller.deleteWebsite(item.identity) }
    }

    private static func field(_ value: String, placeholder: String, y: CGFloat, in view: NSView) -> NSTextField {
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 62, y: y, width: 338, height: 24)
        field.placeholderString = placeholder
        view.addSubview(field)
        return field
    }
    private static func label(_ text: String, y: CGFloat, in view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 0, y: y, width: 56, height: 24)
        view.addSubview(label)
    }
    private static func errorLabel(in view: NSView) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.textColor = .systemRed
        label.frame = NSRect(x: 0, y: 0, width: 400, height: 36)
        label.maximumNumberOfLines = 2
        view.addSubview(label)
        return label
    }
    private static func iconSelection(_ entry: ExtraItemDefinition?, symbol: String, in view: NSView) -> EntryIconSelection {
        let selection = EntryIconSelection(data: entry?.customIconData,
                                           displayData: entry?.customIconData ?? entry?.cachedIconData, fallbackSymbol: symbol)
        view.addSubview(selection.preview)
        for (title, action, x) in [("选择图片…", #selector(EntryIconSelection.choose), 126.0),
                                    ("恢复默认", #selector(EntryIconSelection.reset), 236.0)] {
            let button = NSButton(title: title, target: selection, action: action)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: x, y: 54, width: 100, height: 28)
            view.addSubview(button)
        }
        return selection
    }
}

private enum ExtraIconError: LocalizedError {
    case invalidImage
    var errorDescription: String? { "请选择不超过 16 MB、尺寸不超过 8192×8192 的有效图片。" }
}
