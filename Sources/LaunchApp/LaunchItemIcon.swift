import SwiftUI
import LaunchCore

private struct FetchingIconsKey: EnvironmentKey {
    static let defaultValue: Set<ItemIdentity> = []
}

extension EnvironmentValues {
    var fetchingIcons: Set<ItemIdentity> {
        get { self[FetchingIconsKey.self] }
        set { self[FetchingIconsKey.self] = newValue }
    }
}

enum ItemTypeBadge { case website, shortcut }

enum ItemIconPresentation {
    static func badge(for item: LaunchItem) -> ItemTypeBadge? {
        switch item.target {
        case .application: nil
        case .website: .website
        case .shortcut: .shortcut
        }
    }

    // 与系统应用图标一致：主体占画布 824/1024 并居中，四周留白
    static func bodyFrame(side: CGFloat) -> CGRect {
        let body = side * 824 / 1024
        let inset = (side - body) / 2
        return CGRect(x: inset, y: inset, width: body, height: body)
    }

    // 角标贴主体左下角，略伸出主体但不出画布
    static func badgeFrame(side: CGFloat) -> CGRect {
        let body = bodyFrame(side: side)
        let diameter = body.width / 3
        let overhang = body.width * 0.03
        return CGRect(x: body.minX - overhang, y: body.maxY - diameter + overhang, width: diameter, height: diameter)
    }
}

@MainActor private enum EntryIconCache {
    static let images: NSCache<NSData, NSImage> = {
        let cache = NSCache<NSData, NSImage>()
        cache.countLimit = 128
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    static func image(_ data: Data?) -> NSImage? {
        guard let data else { return nil }
        if let cached = images.object(forKey: data as NSData) { return cached }
        guard let normalized = ItemImageData.normalized(data), let image = NSImage(data: normalized) else { return nil }
        images.setObject(image, forKey: data as NSData, cost: 256 * 256 * 4)
        return image
    }
}

// 只有应用走按路径读图标，网址和快捷指令用自带图片或首字图标
struct LaunchItemIcon: View {
    let item: LaunchItem
    let side: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fetchingIcons) private var fetchingIcons

    var body: some View {
        base
            .frame(width: side, height: side)
            .overlay(alignment: .topLeading) {
                if let type = ItemIconPresentation.badge(for: item) {
                    let frame = ItemIconPresentation.badgeFrame(side: side)
                    badge(type, side: frame.width)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .opacity(item.isAvailable ? 1 : 0.45)
            .overlay {
                if fetchingIcons.contains(item.identity) {
                    ProgressView().controlSize(.small).accessibilityLabel("正在获取图标")
                }
            }
    }

    @ViewBuilder private var base: some View {
        if let application = item.application {
            AppIconImage(path: application.identity.path, side: side)
        } else {
            let body = ItemIconPresentation.bodyFrame(side: side).width
            let shape = RoundedRectangle(cornerRadius: body * 0.225, style: .continuous)
            Group {
                if let image = EntryIconCache.image(item.iconData) {
                    Image(nsImage: image)
                        .resizable().interpolation(.high)
                } else {
                    LinearGradient(colors: fallbackColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            Text(String(item.displayName.prefix(1)))
                                .font(.system(size: body * 0.5, weight: .medium))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: body, height: body)
            .clipShape(shape)
            .shadow(color: .black.opacity(0.18), radius: side * 0.012, y: side * 0.006)
        }
    }

    private var fallbackColors: [Color] {
        switch item.target {
        case .shortcut: [.purple.opacity(0.8), .indigo]
        default: [.cyan.opacity(0.8), .blue]
        }
    }

    private func badge(_ type: ItemTypeBadge, side: CGFloat) -> some View {
        Circle()
            .fill(colorScheme == .dark ? Color(white: 0.16) : .white)
            .overlay { Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: max(0.5, side * 0.025)) }
            .overlay {
                if type == .website {
                    Image(systemName: "globe")
                        .font(.system(size: side * 0.65, weight: .medium))
                        .foregroundStyle(.blue)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: side * 0.06).fill(.purple)
                            .frame(width: side * 0.40, height: side * 0.40).rotationEffect(.degrees(45)).offset(y: side * 0.13)
                        RoundedRectangle(cornerRadius: side * 0.06)
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: side * 0.40, height: side * 0.40).rotationEffect(.degrees(45)).offset(y: -side * 0.10)
                    }
                }
            }
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.18), radius: side * 0.05, y: side * 0.04)
            .accessibilityHidden(true)
    }
}

// 启动器主界面的前景与背景色，随外观自动变：深色是白字加深色玻璃，浅色是深色字加浅色玻璃
extension Color {
    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static let launcherInk = dynamic(dark: .white, light: NSColor(white: 0.1, alpha: 1))
    // 文字外围的柔和描边：深色下是深影，浅色下是浅影
    static let launcherShadow = dynamic(dark: NSColor.black.withAlphaComponent(0.38), light: NSColor.white.withAlphaComponent(0.5))
    static let launcherDim = dynamic(dark: NSColor(white: 0.12, alpha: 1), light: NSColor(white: 0.97, alpha: 1))

    // 文件夹底板、面板底这类半透明填充：深色下是半透明白，浅色下是更实的白色玻璃
    static func launcherFill(_ opacity: Double) -> Color {
        dynamic(dark: NSColor.white.withAlphaComponent(opacity), light: NSColor.white.withAlphaComponent(min(0.9, opacity * 3.5)))
    }

    // 选中高亮：深色下提亮，浅色下压暗一点
    static func launcherSelection(_ isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        return dynamic(dark: NSColor.white.withAlphaComponent(0.26), light: NSColor.black.withAlphaComponent(0.10))
    }
}
