import AppKit
import LaunchCore
import SwiftUI

enum SearchPresentation {
    static func showsClearControl(for query: String) -> Bool {
        !query.isEmpty
    }

    static func showsMoreControl(for query: String) -> Bool {
        query.isEmpty
    }
}

struct LauncherView: View {
    let model: LauncherModel
    let onEscape: () -> Void
    let onBackgroundClick: () -> Void
    let onLaunch: (CatalogApp) -> Void

    @FocusState private var searchFieldIsFocused: Bool
    @State private var folderFrames: [String: CGRect] = [:]
    @State private var dragTracker = PageDragTracker()
    nonisolated private static let contentSpace = "launcher-content"

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.47))
                    .ignoresSafeArea()
                    .onTapGesture(perform: onBackgroundClick)

                let layout = LauncherHomeLayout(
                    screenSize: proxy.size,
                    referenceSize: NSScreen.screens.first?.frame.size ?? proxy.size
                )
                ZStack {
                    homeContent(layout: layout)
                        .opacity(model.openFolder == nil ? 1 : 0)
                        .allowsHitTesting(model.openFolder == nil)

                    if let folder = model.openFolder {
                        FolderOverlay(
                            model: model,
                            folder: folder,
                            layout: layout,
                            columns: gridColumns(layout),
                            dragTracker: dragTracker,
                            onLaunch: onLaunch
                        )
                        .transition(.folderZoom(from: folderFrames[folder.id], in: layout.contentSize))
                    }
                }
                .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                .coordinateSpace(.named(Self.contentSpace))
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    model.updatePageWidth(width)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.25), value: model.openFolderID)
        }
        .onExitCommand(perform: onEscape)
        .onAppear {
            searchFieldIsFocused = true
        }
        .onChange(of: model.presentationCount) {
            searchFieldIsFocused = true
        }
    }

    @ViewBuilder
    private func homeContent(layout: LauncherHomeLayout) -> some View {
        let columns = gridColumns(layout)

        VStack(spacing: 0) {
            searchBar(layout: layout)
                .padding(.top, layout.topInset)

            Color.clear
                .frame(height: layout.searchToGrid)

            if model.pages.isEmpty {
                ContentUnavailableView(
                    "未找到应用",
                    systemImage: "magnifyingglass",
                    description: Text("换个关键词试试")
                )
                .foregroundStyle(.white)
            } else {
                PageOffset(
                    model: model,
                    page: model.currentPage,
                    pageCount: model.pages.count,
                    pageWidth: layout.contentSize.width,
                    followsDrag: model.openFolder == nil
                ) {
                HStack(spacing: 0) {
                    ForEach(Array(model.pages.enumerated()), id: \.offset) { pageIndex, items in
                        LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                itemView(
                                    item,
                                    layout: layout,
                                    isSelected: pageIndex == model.currentPage && index == model.selectedIndex
                                )
                            }
                        }
                        .padding(.horizontal, layout.horizontalInset)
                        .frame(width: layout.contentSize.width, height: layout.gridHeight, alignment: .top)
                        .allowsHitTesting(pageIndex == model.currentPage)
                    }
                }
                }
                .frame(width: layout.contentSize.width, height: layout.gridHeight, alignment: .topLeading)
                .clipped()
                .modifier(PageDragArea(model: model, tracker: dragTracker))
                .onTapGesture {
                    if !dragTracker.suppressesTap {
                        onBackgroundClick()
                    }
                }
            }

            Spacer(minLength: 0)

            if model.pages.count > 1 {
                pageIndicator(layout: layout)
                    .padding(.bottom, layout.bottomInset)
            }
        }
    }

    private func gridColumns(_ layout: LauncherHomeLayout) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(layout.tileWidth), spacing: layout.columnSpacing),
            count: LauncherHomeLayout.columnCount
        )
    }

    @ViewBuilder
    private func itemView(_ item: ResolvedItem, layout: LauncherHomeLayout, isSelected: Bool) -> some View {
        switch item {
        case .app(let app):
            LauncherAppTile(app: app, layout: layout, isSelected: isSelected) {
                if !dragTracker.suppressesTap {
                    onLaunch(app)
                }
            }
        case .folder(let folder):
            LauncherFolderTile(folder: folder, layout: layout, isSelected: isSelected) {
                if !dragTracker.suppressesTap {
                    model.showFolder(id: folder.id)
                }
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.contentSpace))
            } action: { frame in
                folderFrames[folder.id] = frame
            }
        case .empty:
            Color.clear
                .frame(width: layout.tileWidth, height: layout.tileHeight)
        }
    }

    private func searchBar(layout: LauncherHomeLayout) -> some View {
        HStack(spacing: layout.searchBarSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: layout.searchIconSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            TextField("搜索应用", text: Binding(
                get: { model.query },
                set: { model.setQuery($0) }
            ))
                .textFieldStyle(.plain)
                .font(.system(size: layout.searchFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .focused($searchFieldIsFocused)

            if SearchPresentation.showsClearControl(for: model.query) {
                Button {
                    model.setQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: layout.clearIconSize))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            } else if SearchPresentation.showsMoreControl(for: model.query) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: layout.searchIconSize))
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityLabel("更多选项")
            }
        }
        .padding(.horizontal, layout.searchBarPadding)
        .frame(width: layout.searchBarWidth, height: layout.searchBarHeight)
        .background(.white.opacity(0.11), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(0.18),
            radius: layout.searchShadowRadius,
            y: layout.searchShadowOffset
        )
    }

    private func pageIndicator(layout: LauncherHomeLayout) -> some View {
        HStack(spacing: layout.pageDotSpacing) {
            ForEach(model.pages.indices, id: \.self) { pageIndex in
                Button {
                    model.selectPage(pageIndex)
                } label: {
                    Circle()
                        .fill(pageIndex == model.currentPage ? .white : .white.opacity(0.4))
                        .frame(width: layout.pageDotSize, height: layout.pageDotSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第 \(pageIndex + 1) 页")
            }
        }
    }
}

private struct LauncherAppTile: View {
    let app: CatalogApp
    let layout: LauncherHomeLayout
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: layout.iconLabelSpacing) {
                Image(nsImage: IconCache.shared.icon(for: app.identity.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: layout.iconSide, height: layout.iconSide)
                Text(app.displayName)
                    .font(.system(size: layout.labelFontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
                    .lineLimit(1)
                    .frame(maxWidth: layout.tileWidth)
                    .frame(height: layout.labelHeight)
            }
            .padding(.vertical, layout.tilePadding)
            .frame(width: layout.tileWidth)
            .background {
                RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.26 : (isHovering ? 0.15 : 0)))
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .accessibilityLabel(app.displayName)
    }
}

private struct LauncherFolderTile: View {
    let folder: ResolvedFolder
    let layout: LauncherHomeLayout
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: layout.iconLabelSpacing) {
                FolderPreview(apps: Array(folder.apps.prefix(9)), layout: layout)
                Text(folder.name)
                    .font(.system(size: layout.labelFontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
                    .lineLimit(1)
                    .frame(maxWidth: layout.tileWidth)
                    .frame(height: layout.labelHeight)
            }
            .padding(.vertical, layout.tilePadding)
            .frame(width: layout.tileWidth)
            .background {
                RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.26 : (isHovering ? 0.15 : 0)))
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .accessibilityLabel(folder.name)
    }
}

private struct FolderPreview: View {
    let apps: [CatalogApp]
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
                Image(nsImage: IconCache.shared.icon(for: app.identity.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
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

private struct FolderOverlay: View {
    let model: LauncherModel
    let folder: ResolvedFolder
    let layout: LauncherHomeLayout
    let columns: [GridItem]
    let dragTracker: PageDragTracker
    let onLaunch: (CatalogApp) -> Void

    var body: some View {
        let pages = model.folderPages
        VStack(spacing: layout.folderTitleSpacing) {
            Text(folder.name)
                .font(.system(size: layout.folderTitleFontSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(height: layout.folderTitleHeight)
            PageOffset(
                model: model,
                page: model.folderPage,
                pageCount: pages.count,
                pageWidth: layout.contentSize.width,
                followsDrag: true
            ) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, apps in
                    LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
                        ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
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
                    .padding(.horizontal, layout.horizontalInset)
                    .frame(width: layout.contentSize.width, alignment: .top)
                    .allowsHitTesting(pageIndex == model.folderPage)
                }
            }
            }
            .frame(
                width: layout.contentSize.width,
                height: layout.folderGridHeight(memberCount: folder.apps.count),
                alignment: .topLeading
            )
            .clipped()
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

private struct FolderZoomModifier: ViewModifier {
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

private extension AnyTransition {
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

@MainActor
final class PageDragTracker {
    var isDragging = false
    var lastDragEnd: TimeInterval = 0

    // 鼠标松开时按钮动作与拖动结束的先后不固定，结束后短时间内仍视为拖动
    var suppressesTap: Bool {
        isDragging || ProcessInfo.processInfo.systemUptime - lastDragEnd < 0.2
    }
}

private struct PageDragArea: ViewModifier {
    let model: LauncherModel
    let tracker: PageDragTracker

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { value in
                        tracker.isDragging = true
                        model.dragPage(by: value.translation.width)
                    }
                    .onEnded { value in
                        model.endPageDrag(predictedTranslation: value.predictedEndTranslation.width)
                        tracker.isDragging = false
                        tracker.lastDragEnd = ProcessInfo.processInfo.systemUptime
                    }
            )
    }
}

// 只有这一层读取拖动位移，拖动时不重建页面内容
private struct PageOffset<Content: View>: View {
    let model: LauncherModel
    let page: Int
    let pageCount: Int
    let pageWidth: CGFloat
    let followsDrag: Bool
    @ViewBuilder let content: Content

    var body: some View {
        let drag = followsDrag
            ? PageDragResolver.displayOffset(
                translation: model.pageDragTranslation,
                currentPage: page,
                pageCount: pageCount
            )
            : 0
        content
            .offset(x: -CGFloat(page) * pageWidth + drag)
            .animation(.easeOut(duration: 0.3), value: page)
            .animation(.easeOut(duration: 0.3), value: model.isPageDragging)
    }
}
