import AppKit
import LaunchCore
import SwiftUI

extension EnvironmentValues {
    @Entry var showsItemNames = true
}

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
    let settings: LauncherSettings
    let onEscape: () -> Void
    let onBackgroundClick: () -> Void
    let onLaunch: (LaunchItem) -> Void
    let onMainMenu: () -> Void

    @FocusState private var searchFieldIsFocused: Bool
    @State private var folderFrames: [String: CGRect] = [:]
    @State private var dragTracker = PageDragTracker()
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    nonisolated private static let contentSpace = "launcher-content"

    var body: some View {
        GeometryReader { proxy in
            let windowed = model.displayMode == .window
            let layout = LauncherHomeLayout(
                screenSize: windowed ? LauncherHomeLayout.windowArea(for: proxy.size) : proxy.size,
                referenceSize: NSScreen.screens.first?.frame.size ?? proxy.size,
                grid: model.grid,
                showsNames: !settings.hidesNames,
                placement: settings.gridPlacement
            )
            ZStack {
                // 窗口模式下窗口外透明，点到也按点空白处理
                if windowed {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture(perform: onBackgroundClick)
                }
                LauncherBackground(model: model, settings: settings)
                    .modifier(WindowFrame(size: windowed ? layout.contentSize : nil, cornerRadius: 26 * layout.sizeScale))
                    .opacity(model.isPresented ? 1 : 0)
                    .animation(
                        PresentationTransition.backgroundAnimation(presented: model.isPresented),
                        value: model.isPresented
                    )
                    .ignoresSafeArea()
                    .onTapGesture(perform: onBackgroundClick)

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
                .animation(PresentationTransition.scaleAnimation(presented: model.isPresented)) {
                    $0.scaleEffect(model.isPresented || reduceMotion ? 1 : PresentationTransition.hiddenScale)
                }
                .animation(PresentationTransition.opacityAnimation(presented: model.isPresented)) {
                    $0.opacity(model.isPresented ? 1 : 0)
                }
                .onChange(of: layout, initial: true) {
                    model.updateHomeLayout(layout)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    model.updatePageWidth(width)
                }

                MarqueeOverlay(model: model)
                    .ignoresSafeArea()

                HintOverlay(model: model, layout: layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.25), value: model.openFolderID)
        }
        .environment(\.showsItemNames, !settings.hidesNames)
        .environment(\.fetchingIcons, model.fetchingIcons)
        .onExitCommand(perform: onEscape)
        .onAppear {
            searchFieldIsFocused = true
        }
        .onChange(of: model.presentationCount) {
            searchFieldIsFocused = true
        }
        .onChange(of: model.renamingFolderID) { _, folderID in
            if folderID == nil {
                searchFieldIsFocused = true
            }
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
            } else if model.browsingStyle == .scroll {
                scrollContent(layout: layout, columns: columns)
            } else {
                PageOffset(model: model, pager: .grid, pageWidth: layout.contentSize.width) {
                HStack(spacing: 0) {
                    ForEach(Array(model.pages.enumerated()), id: \.offset) { pageIndex, items in
                        LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
                            ForEach(model.gridEntries(page: pageIndex, items: items, area: .grid)) { entry in
                                GridCell(model: model, entry: entry, layout: layout) { item, index in
                                    itemView(
                                        item,
                                        layout: layout,
                                        isSelected: pageIndex == model.currentPage && index == model.selectedIndex
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, layout.horizontalInset)
                        .padding(.top, layout.gridTopInset)
                        .frame(width: layout.contentSize.width, height: layout.gridHeight, alignment: .top)
                        .allowsHitTesting(pageIndex == model.currentPage)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: model.dragPreview)
                }
                .frame(width: layout.contentSize.width, height: layout.gridHeight, alignment: .topLeading)
                .clipped()
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    model.updateGridFrame(frame)
                }
                .modifier(PageDragArea(model: model, tracker: dragTracker))
                .onTapGesture {
                    if !dragTracker.suppressesTap {
                        onBackgroundClick()
                    }
                }
            }

            Spacer(minLength: 0)

            if model.browsingStyle == .paged, model.pages.count > 1 {
                pageIndicator(layout: layout)
                    .padding(.bottom, layout.bottomInset)
            }
        }
    }

    // 滚动浏览：各页上下排开，紧凑行距，页间一条淡分隔线
    private func scrollContent(layout: LauncherHomeLayout, columns: [GridItem]) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(Array(model.pages.enumerated()), id: \.offset) { pageIndex, items in
                    if pageIndex > 0 {
                        Rectangle()
                            .fill(.white.opacity(0.15))
                            .frame(height: 1)
                            .padding(.horizontal, layout.horizontalInset)
                            .padding(.vertical, layout.folderRowSpacing * 1.5)
                    }
                    LazyVGrid(columns: columns, spacing: layout.folderRowSpacing) {
                        ForEach(model.gridEntries(page: pageIndex, items: items, area: .grid)) { entry in
                            GridCell(model: model, entry: entry, layout: layout) { item, index in
                                itemView(
                                    item,
                                    layout: layout,
                                    isSelected: pageIndex == model.currentPage && index == model.selectedIndex
                                )
                            }
                        }
                    }
                    .padding(.horizontal, layout.horizontalInset)
                    .frame(width: layout.contentSize.width, alignment: .top)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        model.updatePageFrame(frame, page: pageIndex)
                    }
                    .id(pageIndex)
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, layout.bottomInset)
            .contentShape(Rectangle())
            .onTapGesture(perform: onBackgroundClick)
            .animation(.easeOut(duration: 0.25), value: model.dragPreview)
        }
        .scrollIndicators(.never)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, offset in
            scrollOffset = offset
        }
        .frame(width: layout.contentSize.width)
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            model.updateGridFrame(frame)
        }
        .onChange(of: model.scrollRequest) { _, request in
            switch request?.kind {
            case .page(let page)?:
                withAnimation(.easeOut(duration: 0.25)) {
                    scrollPosition.scrollTo(id: page, anchor: .top)
                }
            case .by(let delta)?:
                scrollPosition.scrollTo(y: max(0, scrollOffset + delta))
            case nil:
                break
            }
        }
    }

    private func gridColumns(_ layout: LauncherHomeLayout) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(layout.tileWidth), spacing: layout.columnSpacing),
            count: layout.grid.columns
        )
    }

    @ViewBuilder
    private func itemView(_ item: ResolvedItem, layout: LauncherHomeLayout, isSelected: Bool) -> some View {
        switch item {
        case .item(let app):
            LauncherAppTile(app: app, layout: layout, isSelected: isSelected) {
                if !dragTracker.suppressesTap {
                    onLaunch(app)
                }
            }
            .opacity(model.isHiddenItem(app) ? 0.45 : 1)
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

            // 液态玻璃会按背后亮暗切换外观，系统占位色在亮背景下变深灰，所以显式给白色
            TextField("搜索应用", text: Binding(
                get: { model.query },
                set: { model.setQuery($0) }
            ), prompt: Text("搜索应用").foregroundStyle(.white.opacity(0.6)))
                .textFieldStyle(.plain)
                .font(.system(size: layout.searchFontSize, weight: .regular))
                .foregroundStyle(.white)
                .tint(.white)
                .environment(\.colorScheme, .dark)
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
                Button(action: onMainMenu) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: layout.moreIconSize))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多选项")
            }
        }
        .padding(.leading, layout.searchBarLeadingPadding)
        .padding(.trailing, layout.searchBarPadding)
        .frame(width: layout.searchBarWidth, height: layout.searchBarHeight)
        // 液态玻璃不接点击，不补命中区域的话点到框内空白会落到背景上关闭启动器
        .contentShape(Capsule())
        .onTapGesture { searchFieldIsFocused = true }
        // 与 LaunchOS 一样用系统液态玻璃出内阴影与边缘高光，淡黑着色按其截图亮度校准
        .glassEffect(.clear.tint(.black.opacity(0.1)), in: Capsule())
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

struct LauncherAppTile: View {
    let app: LaunchItem
    let layout: LauncherHomeLayout
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.showsItemNames) private var showsName

    var body: some View {
        VStack(spacing: layout.iconLabelSpacing) {
            LaunchItemIcon(item: app, side: layout.iconSide)
            Text(app.displayName)
                .font(.system(size: layout.labelFontSize, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
                .lineLimit(1)
                .frame(maxWidth: layout.tileWidth)
                .frame(height: layout.labelHeight)
                .opacity(showsName ? 1 : 0)
        }
        .padding(.vertical, layout.tilePadding)
        .frame(width: layout.tileWidth)
        .background {
            RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.26 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous))
        // 鼠标点击统一由 ItemDragController 处理；SwiftUI 手势不受本地事件监听拦截，这里只吞掉点击，免得落到背景上
        .onTapGesture {}
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.displayName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

private struct LauncherFolderTile: View {
    let folder: ResolvedFolder
    let layout: LauncherHomeLayout
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.showsItemNames) private var showsName

    var body: some View {
        VStack(spacing: layout.iconLabelSpacing) {
            FolderPreview(apps: Array(folder.items.prefix(9)), layout: layout)
            Text(folder.name)
                .font(.system(size: layout.labelFontSize, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
                .lineLimit(1)
                .frame(maxWidth: layout.tileWidth)
                .frame(height: layout.labelHeight)
                .opacity(showsName ? 1 : 0)
        }
        .padding(.vertical, layout.tilePadding)
        .frame(width: layout.tileWidth)
        .background {
            RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.26 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: layout.tileCornerRadius, style: .continuous))
        // 鼠标点击统一由 ItemDragController 处理；SwiftUI 手势不受本地事件监听拦截，这里只吞掉点击，免得落到背景上
        .onTapGesture {}
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(folder.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

struct GridCell<ItemView: View>: View {
    let model: LauncherModel
    let entry: LauncherModel.GridEntry
    let layout: LauncherHomeLayout
    @ViewBuilder let itemView: (ResolvedItem, Int) -> ItemView

    var body: some View {
        switch entry.content {
        case .gap:
            Color.clear
                .frame(width: layout.tileWidth, height: layout.tileHeight)
        case .item(let item, let index):
            itemView(item, index)
                .background(alignment: .top) {
                    if entry.isMergeTarget {
                        RoundedRectangle(cornerRadius: layout.folderCornerRadius * 1.2, style: .continuous)
                            .fill(.white.opacity(0.24))
                            .frame(width: layout.iconSide * 1.2, height: layout.iconSide * 1.2)
                            .padding(.top, layout.tilePadding - layout.iconSide * 0.1)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if entry.isPicked {
                        SelectionCheck(layout: layout)
                    }
                }
                .modifier(LandingModifier(
                    from: model.landing?.entryIDs.contains(entry.id) == true ? model.landing?.from : nil,
                    onFinished: { model.clearLanding() }
                ))
                .overlay(alignment: .topLeading) {
                    let showsBadge = showsUninstallBadge(for: item)
                    ZStack {
                        if showsBadge {
                            UninstallBadge(layout: layout)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.55), value: showsBadge)
                }
                .modifier(JiggleModifier(isActive: model.isJiggling, seed: entry.id.hashValue))
        }
    }

    private func showsUninstallBadge(for item: ResolvedItem) -> Bool {
        guard model.isJiggling, case .item(let app) = item else {
            return false
        }
        return model.canUninstall(app)
    }
}

// 新位置的格子先偏移到松手处，再缓动回自身位置
private struct LandingModifier: ViewModifier {
    let from: CGRect?
    let onFinished: @MainActor @Sendable () -> Void

    @State private var offset: CGSize?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                guard let from, offset == nil else {
                    return
                }
                offset = CGSize(width: from.minX - frame.minX, height: from.minY - frame.minY)
                withAnimation(.easeOut(duration: 0.2)) {
                    offset = .zero
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: onFinished)
            }
            .offset(offset ?? .zero)
    }
}

private struct UninstallBadge: View {
    let layout: LauncherHomeLayout

    var body: some View {
        let side = layout.uninstallBadgeSide
        Image(systemName: "xmark")
            .font(.system(size: side * 0.42, weight: .bold))
            .foregroundStyle(.black.opacity(0.75))
            .frame(width: side, height: side)
            .background(Circle().fill(.white.opacity(0.92)))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .offset(x: (layout.tileWidth - layout.iconSide) / 2 - side * 0.2, y: layout.tilePadding - side * 0.2)
            .transition(.scale.combined(with: .opacity))
            // 点击交给下面的图标吞掉，× 本身由 ItemDragController 按位置识别
            .allowsHitTesting(false)
            .accessibilityLabel("移到废纸篓")
    }
}

private struct SelectionCheck: View {
    let layout: LauncherHomeLayout

    var body: some View {
        let side = layout.uninstallBadgeSide
        Image(systemName: "checkmark")
            .font(.system(size: side * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(Circle().fill(.blue))
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .offset(x: -((layout.tileWidth - layout.iconSide) / 2 - side * 0.2), y: layout.tilePadding - side * 0.2)
            .allowsHitTesting(false)
            .accessibilityLabel("已选中")
    }
}

// 只有这一层读取背景设置与壁纸，切换时不重建网格
private struct HintOverlay: View {
    let model: LauncherModel
    let layout: LauncherHomeLayout

    var body: some View {
        VStack {
            Spacer()
            if let hint = model.hint {
                Text(hint)
                    .font(.system(size: 14 * layout.sizeScale, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16 * layout.sizeScale)
                    .padding(.vertical, 8 * layout.sizeScale)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.bottom, layout.bottomInset + layout.pageDotSize + 24 * layout.sizeScale)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.hint)
        .allowsHitTesting(false)
    }
}

// 只有这一层读取选框矩形，拖动选框时不重建网格
private struct MarqueeOverlay: View {
    let model: LauncherModel

    var body: some View {
        GeometryReader { proxy in
            if let rect = model.marqueeRect {
                let origin = proxy.frame(in: .global).origin
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(.white.opacity(0.6), lineWidth: 1)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX - origin.x, y: rect.midY - origin.y)
            }
        }
        .allowsHitTesting(false)
    }
}

// 抖动时各图标以略有差异的周期左右摇摆
private struct JiggleModifier: ViewModifier {
    let isActive: Bool
    let seed: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            let period = 0.11 + Double(((seed % 5) + 5) % 5) * 0.008
            content.phaseAnimator([-1.0, 1.0]) { view, phase in
                view.rotationEffect(.degrees(phase * 2))
            } animation: { _ in
                .easeInOut(duration: period)
            }
        } else {
            content
        }
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

struct PageDragArea: ViewModifier {
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
                        model.endPageDrag(
                            predictedTranslation: value.predictedEndTranslation.width,
                            velocity: value.velocity.width
                        )
                        tracker.isDragging = false
                        tracker.lastDragEnd = ProcessInfo.processInfo.systemUptime
                    }
            )
    }
}

// 只有这一层读取逐帧变化的翻页位置，翻页时不重建页面内容
struct PageOffset<Content: View>: View {
    enum Pager {
        case grid
        case folder
    }

    let model: LauncherModel
    let pager: Pager
    let pageWidth: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let position = pager == .grid ? model.gridPosition : model.folderPosition
        content.offset(x: -position * pageWidth)
    }
}
