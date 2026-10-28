import AppKit
import LaunchCore
import SwiftUI

// 文件夹相关视图：网格里的文件夹预览、展开面板、标题和放大动画
struct FolderPreview: View {
    let apps: [LaunchItem]
    let layout: LauncherHomeLayout

    var body: some View {
        let side = layout.folderPreviewIconSide
        let spacing = layout.folderPreviewSpacing
        let gridSide = side * 3 + spacing * 2
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: 3),
            spacing: spacing
        ) {
            ForEach(apps, id: \.identity) { app in
                LaunchItemIcon(item: app, side: side)
            }
        }
        .frame(width: gridSide, height: gridSide, alignment: .top)
        .frame(width: layout.iconSide, height: layout.iconSide)
        .background {
            RoundedRectangle(cornerRadius: layout.folderCornerRadius, style: .continuous)
                .fill(.white.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: layout.folderCornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
        }
    }
}

struct FolderTitle: View {
    let model: LauncherModel
    let folder: ResolvedFolder
    let layout: LauncherHomeLayout

    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if model.renamingFolderID == folder.id {
                TextField("", text: Binding(
                    get: { model.folderNameDraft },
                    set: { model.folderNameDraft = $0 }
                ))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .onSubmit {
                    model.finishRenamingFolder()
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        model.finishRenamingFolder()
                    }
                }
                .onAppear {
                    // 刚出现时输入框还不在响应链里，同步设置焦点会被忽略
                    DispatchQueue.main.async {
                        isFocused = true
                        DispatchQueue.main.async {
                            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                        }
                    }
                }
            } else {
                Text(folder.name)
                    .onTapGesture {
                        model.beginRenamingFolder()
                    }
            }
        }
        .font(.system(size: layout.folderTitleFontSize, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: layout.tileWidth * 3, height: layout.folderTitleHeight)
    }
}

struct FolderOverlay: View {
    let model: LauncherModel
    let folder: ResolvedFolder
    let layout: LauncherHomeLayout
    let columns: [GridItem]
    let dragTracker: PageDragTracker
    let onLaunch: (LaunchItem) -> Void

    var body: some View {
        let pages = model.folderPages
        VStack(spacing: layout.folderTitleSpacing) {
            FolderTitle(model: model, folder: folder, layout: layout)
            PageOffset(model: model, pager: .folder, pageWidth: layout.contentSize.width) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, apps in
                    LazyVGrid(columns: columns, spacing: layout.folderRowSpacing) {
                        ForEach(model.gridEntries(page: pageIndex, items: apps.map(ResolvedItem.item), area: .folder)) { entry in
                            GridCell(model: model, entry: entry, layout: layout) { item, index in
                                if case .item(let app) = item {
                                    LauncherAppTile(
                                        app: app,
                                        layout: layout,
                                        isSelected: pageIndex == model.folderPage && index == model.folderSelectedIndex
                                    ) {
                                        if !dragTracker.suppressesTap {
                                            onLaunch(app)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, layout.horizontalInset)
                    .frame(width: layout.contentSize.width, alignment: .top)
                    .allowsHitTesting(pageIndex == model.folderPage)
                }
            }
            .animation(.easeOut(duration: 0.25), value: model.dragPreview)
            }
            .frame(
                width: layout.contentSize.width,
                height: layout.folderGridHeight(memberCount: folder.items.count),
                alignment: .topLeading
            )
            .clipped()
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                model.updateFolderGridFrame(frame)
            }
            .modifier(PageDragArea(model: model, tracker: dragTracker))
            .padding(.vertical, layout.folderPanelPadding)
            .background {
                RoundedRectangle(cornerRadius: layout.folderPanelCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: layout.folderPanelCornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    }
                    .padding(.horizontal, layout.horizontalInset - layout.folderPanelOutset)
                    .onTapGesture {}
            }
            if pages.count > 1 {
                HStack(spacing: layout.pageDotSpacing) {
                    ForEach(pages.indices, id: \.self) { pageIndex in
                        Button {
                            model.selectFolderPage(pageIndex)
                        } label: {
                            Circle()
                                .fill(pageIndex == model.folderPage ? .white : .white.opacity(0.4))
                                .frame(width: layout.pageDotSize, height: layout.pageDotSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("文件夹第 \(pageIndex + 1) 页")
                    }
                }
            }
        }
    }
}

struct FolderZoomModifier: ViewModifier {
    let scale: CGFloat
    let offset: CGSize
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static func folderZoom(from source: CGRect?, in size: CGSize) -> AnyTransition {
        guard let source, size.width > 0 else {
            return .opacity.combined(with: .scale(scale: 0.92))
        }
        let offset = CGSize(width: source.midX - size.width / 2, height: source.midY - size.height / 2)
        return .modifier(
            active: FolderZoomModifier(scale: max(source.width / size.width, 0.05), offset: offset, opacity: 0),
            identity: FolderZoomModifier(scale: 1, offset: .zero, opacity: 1)
        )
    }
}
