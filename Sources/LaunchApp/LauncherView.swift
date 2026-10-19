import AppKit
import LaunchCore
import SwiftUI

enum SearchPresentation {
    static func showsClearControl(for query: String) -> Bool {
        !query.isEmpty
    }
}

struct LauncherView: View {
    let apps: [CatalogApp]
    let onClose: () -> Void
    let onLaunch: () -> Void

    @State private var query = ""
    @State private var currentPage = 0
    @FocusState private var searchFieldIsFocused: Bool

    private let columnCount = 7
    private let rowCount = 5

    private var results: [CatalogApp] {
        SearchService.results(for: query, in: apps, hidden: [])
    }

    private var pages: [[CatalogApp]] {
        LauncherPagination.pages(
            results,
            capacity: columnCount * rowCount
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
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 42) {
                searchBar

                if visibleApps.isEmpty {
                    ContentUnavailableView(
                        "未找到应用",
                        systemImage: "magnifyingglass",
                        description: Text("换个关键词试试")
                    )
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity)
                } else {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(minimum: 120), spacing: 44),
                            count: columnCount
                        ),
                        spacing: 54
                    ) {
                        ForEach(visibleApps, id: \.identity) { app in
                            Button {
                                if NSWorkspace.shared.open(
                                    URL(fileURLWithPath: app.identity.path)
                                ) {
                                    onLaunch()
                                }
                            } label: {
                                VStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(
                                        forFile: app.identity.path
                                    ))
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 104, height: 104)
                                    Text(app.displayName)
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                                        .lineLimit(1)
                                        .frame(maxWidth: 180)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(app.displayName)
                        }
                    }
                    .padding(.horizontal, 160)
                }

                Spacer(minLength: 20)

                if pages.count > 1 {
                    pageIndicator
                }
            }
            .padding(.top, 82)
            .padding(.bottom, 52)
        }
        .onExitCommand(perform: onClose)
        .onChange(of: query) {
            currentPage = 0
        }
        .onAppear {
            searchFieldIsFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            TextField("搜索应用", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .focused($searchFieldIsFocused)

            if SearchPresentation.showsClearControl(for: query) {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 24)
        .frame(width: 480, height: 58)
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
