import AppKit

enum AppIconStyle: String, CaseIterable, Identifiable {
    case aperture, grid, tiles
    var id: Self { self }
    var title: String {
        switch self {
        case .aperture: "四瓣开合"
        case .grid: "九宫格"
        case .tiles: "蓝紫四格"
        }
    }
}

enum AppIconTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    func isDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
    }
}

@MainActor
enum AppIconAssets {
    private static var cache: [String: NSImage] = [:]

    static func image(style: AppIconStyle, dark: Bool) -> NSImage? {
        let name = "\(style.rawValue)-\(dark ? "dark" : "light")"
        if let image = cache[name] { return image }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "AppIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

// 只更新运行中图标，不写入应用包；NSWorkspace.setIcon 会附加 FinderInfo，破坏签名验证。
@MainActor
final class AppIconController {
    private let application: NSApplication
    private var appearanceObservation: NSKeyValueObservation?
    private var style = AppIconStyle.grid
    private var theme = AppIconTheme.system
    private var appliedKey: String?
    private(set) var currentImage: NSImage?
    // 菜单栏图标跟着应用图标变
    var onChange: ((NSImage) -> Void)?

    init(application: NSApplication = .shared) {
        self.application = application
        appearanceObservation = application.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func apply(style: AppIconStyle, theme: AppIconTheme) {
        self.style = style
        self.theme = theme
        // 外观不只管图标：设置窗口、菜单、弹窗和启动器主界面都跟着浅色或深色
        let appearance: NSAppearance? = switch theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if application.appearance?.name != appearance?.name { application.appearance = appearance }
        refresh()
    }

    private func refresh() {
        let systemIsDark = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let dark = theme.isDark(systemIsDark: systemIsDark)
        let key = "\(style.rawValue)-\(dark)"
        guard key != appliedKey, let image = AppIconAssets.image(style: style, dark: dark) else { return }
        application.applicationIconImage = image
        currentImage = image
        onChange?(image)
        IconCache.shared.setOverride(image, for: Bundle.main.bundleURL.path)
        appliedKey = key
    }
}
