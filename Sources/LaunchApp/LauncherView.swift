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
                homeContent(layout: layout)
                    .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                    .opacity(model.openFolder == nil ? 1 : 0)
                    .allowsHitTesting(model.openFolder == nil)

                if let folder = model.openFolder {
                    FolderOverlay(
                        folder: folder,
                        layout: layout,
                        columns: gridColumns(layout),
                        onLaunch: onLaunch
                    )
                    .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.2), value: model.openFolderID)
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

            if model.visibleItems.isEmpty {
                ContentUnavailableView(
                    "未找到应用",
                    systemImage: "magnifyingglass",
                    description: Text("换个关键词试试")
                )
                .foregroundStyle(.white)
            } else {
                LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
                    ForEach(Array(model.visibleItems.enumerated()), id: \.offset) { _, item in
                        itemView(item, layout: layout)
                    }
                }
                .padding(.horizontal, layout.horizontalInset)
                .frame(height: layout.gridHeight, alignment: .top)
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
    private func itemView(_ item: ResolvedItem, layout: LauncherHomeLayout) -> some View {
        switch item {
        case .app(let app):
            LauncherAppTile(app: app, layout: layout) {
                onLaunch(app)
            }
        case .folder(let folder):
            LauncherFolderTile(folder: folder, layout: layout) {
                model.showFolder(id: folder.id)
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
                    .fill(.white.opacity(isHovering ? 0.15 : 0))
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
                    .fill(.white.opacity(isHovering ? 0.15 : 0))
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
    let folder: ResolvedFolder
    let layout: LauncherHomeLayout
    let columns: [GridItem]
    let onLaunch: (CatalogApp) -> Void

    var body: some View {
        VStack(spacing: layout.folderTitleSpacing) {
            Text(folder.name)
                .font(.system(size: layout.folderTitleFontSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(height: layout.folderTitleHeight)
            members
                .frame(height: layout.folderGridHeight(memberCount: folder.apps.count), alignment: .top)
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
        }
    }

    @ViewBuilder
    private var members: some View {
        let grid = LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
            ForEach(folder.apps, id: \.identity) { app in
                LauncherAppTile(app: app, layout: layout) {
                    onLaunch(app)
                }
            }
        }
        .padding(.horizontal, layout.horizontalInset)

        if folder.apps.count > LauncherHomeLayout.pageCapacity {
            ScrollView(.vertical, showsIndicators: false) {
                grid
            }
        } else {
            grid
        }
    }
}
