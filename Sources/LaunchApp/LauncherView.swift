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
    let apps: [CatalogApp]
    let onClose: () -> Void
    let onLaunch: () -> Void

    @State private var query = ""
    @State private var currentPage = 0
    @FocusState private var searchFieldIsFocused: Bool

    private var results: [CatalogApp] {
        SearchService.results(for: query, in: apps, hidden: [])
    }

    private var pages: [[CatalogApp]] {
        LauncherPagination.pages(
            results,
            capacity: LauncherHomeLayout.pageCapacity
        )
    }

    private var visibleApps: [CatalogApp] {
        guard !pages.isEmpty else {
            return []
        }
        let pageIndex = LauncherPagination.normalizedPageIndex(
            currentPage,
            pageCount: pages.count
        )
        return pages[pageIndex]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                .overlay(Color.black.opacity(0.47))
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                homeContent(in: proxy.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onExitCommand(perform: onClose)
        .onChange(of: query) {
            currentPage = 0
        }
        .onAppear {
            searchFieldIsFocused = true
        }
    }

    @ViewBuilder
    private func homeContent(in screenSize: CGSize) -> some View {
        let iconSide = LauncherHomeLayout.iconSideLength(for: screenSize)
        let tileWidth = iconSide + 24
        let columns = Array(
            repeating: GridItem(
                .fixed(tileWidth),
                spacing: LauncherHomeLayout.columnSpacing(
                    for: screenSize,
                    itemWidth: tileWidth
                )
            ),
            count: LauncherHomeLayout.columnCount
        )
        let topInset = min(max(42, screenSize.height * 0.052), 100)
        let searchToGrid = min(max(42, screenSize.height * 0.028), 56)
        let rowSpacing = LauncherHomeLayout.rowSpacing(
            for: screenSize,
            iconSide: iconSide
        )

        VStack(spacing: 0) {
            searchBar(width: min(240, screenSize.width - 48))
                .padding(.top, topInset)

            Color.clear
                .frame(height: searchToGrid)

            if visibleApps.isEmpty {
                ContentUnavailableView(
                    "未找到应用",
                    systemImage: "magnifyingglass",
                    description: Text("换个关键词试试")
                )
                .foregroundStyle(.white)
            } else {
                LazyVGrid(columns: columns, spacing: rowSpacing) {
                    ForEach(visibleApps, id: \.identity) { app in
                        LauncherAppTile(app: app, iconSide: iconSide) {
                            if NSWorkspace.shared.open(
                                URL(fileURLWithPath: app.identity.path)
                            ) {
                                onLaunch()
                            }
                        }
                    }
                }
                .padding(.horizontal, LauncherHomeLayout.horizontalInset(for: screenSize))
                .frame(
                    height: LauncherHomeLayout.gridHeight(for: screenSize),
                    alignment: .top
                )
                .clipped()
            }

            Spacer(minLength: 24)

            if pages.count > 1 {
                pageIndicator
                    .padding(.bottom, 110)
            }
        }
    }

    private func searchBar(width: CGFloat) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            TextField("搜索应用", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .focused($searchFieldIsFocused)

            if SearchPresentation.showsClearControl(for: query) {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            } else if SearchPresentation.showsMoreControl(for: query) {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityLabel("更多选项")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 42)
        .background(.white.opacity(0.11), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private var pageIndicator: some View {
        HStack(spacing: 18) {
            ForEach(pages.indices, id: \.self) { pageIndex in
                Button {
                    currentPage = pageIndex
                } label: {
                    Circle()
                        .fill(pageIndex == currentPage ? .white : .white.opacity(0.4))
                        .frame(width: 10, height: 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第 \(pageIndex + 1) 页")
            }
        }
    }
}

private struct LauncherAppTile: View {
    let app: CatalogApp
    let iconSide: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(nsImage: ApplicationIconResolver.icon(for: app.identity.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSide, height: iconSide)
                Text(app.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
                    .lineLimit(1)
                    .frame(maxWidth: iconSide + 24)
            }
            .padding(.vertical, 12)
            .frame(width: iconSide + 24)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.15 : 0))
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onHover { isHovering = $0 }
        .accessibilityLabel(app.displayName)
    }
}
