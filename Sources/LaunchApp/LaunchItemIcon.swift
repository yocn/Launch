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
        guard let data else {
            return nil
        }
        if let cached = images.object(forKey: data as NSData) {
            return cached
        }
        guard let normalized = ItemImageData.normalized(data), let image = NSImage(data: normalized) else {
            return nil
        }
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
