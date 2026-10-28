import AppKit
import LaunchCore
import SwiftUI

// 拖动中图标的卡片视图与渲染
@MainActor
enum DragCardRenderer {
    static func image(
        for item: ResolvedItem,
        count: Int,
        showsName: Bool,
        layout: LauncherHomeLayout,
        scale: CGFloat
    ) -> NSImage? {
        let renderer = ImageRenderer(content: DragCard(item: item, count: count, showsName: showsName, layout: layout))
        renderer.scale = scale
        return renderer.nsImage
    }
}

struct DragCard: View {
    let item: ResolvedItem
    let count: Int
    let showsName: Bool
    let layout: LauncherHomeLayout

    var body: some View {
        VStack(spacing: layout.iconLabelSpacing) {
            switch item {
            case .item(let app):
                LaunchItemIcon(item: app, side: layout.iconSide)
                label(app.displayName)
            case .folder(let folder):
                FolderPreview(apps: Array(folder.items.prefix(9)), layout: layout)
                label(folder.name)
            case .empty:
                EmptyView()
            }
        }
        .padding(.vertical, layout.tilePadding)
        .frame(width: layout.tileWidth)
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: layout.labelFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, layout.uninstallBadgeSide * 0.25)
                    .frame(minWidth: layout.uninstallBadgeSide, minHeight: layout.uninstallBadgeSide)
                    .background(Capsule().fill(.red))
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: layout.labelFontSize, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
            .lineLimit(1)
            .frame(maxWidth: layout.tileWidth)
            .frame(height: layout.labelHeight)
            .opacity(showsName ? 1 : 0)
    }
}
