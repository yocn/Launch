import CoreGraphics

struct LauncherHomeLayout: Equatable {
    // 以下尺寸按 1512×982 主屏调校，参考屏不同尺寸时整体缩放
    static let canvasSize = CGSize(width: 1512, height: 982)
    // 默认 7×5 的网格高度；改行列时网格区域高度不变
    static let baseGridHeight: CGFloat = 141 * 5 + 17 * 4
    private static let baseTileWidth: CGFloat = 112
    private static let baseTileHeight: CGFloat = 141
    private static let baseIconSide: CGFloat = 88
    // 名称连同它上方的间距；隐藏名称时让给图标，格子变成正方形、行高不变
    private static let baseLabelSpace: CGFloat = 12 + 17
    private static let baseRowSpacing: CGFloat = 17
    private static let insetRatio: CGFloat = 0.09

    // 窗口模式下启动器占屏幕的比例
    static func windowArea(for screenSize: CGSize) -> CGSize {
        CGSize(width: screenSize.width * 0.7, height: screenSize.height * 0.75)
    }

    let contentSize: CGSize
    let sizeScale: CGFloat
    let grid: GridSize
    let showsNames: Bool
    let placement: GridPlacement
    // 行列放不下时格子整体缩小的比例，放得下时为 1
    let fitScale: CGFloat

    init(
        screenSize: CGSize,
        referenceSize: CGSize,
        grid: GridSize = .default,
        showsNames: Bool = true,
        placement: GridPlacement = .spread
    ) {
        let screenScale = min(
            screenSize.width / referenceSize.width,
            screenSize.height / referenceSize.height
        )
        let referenceScale = min(
            referenceSize.width / Self.canvasSize.width,
            referenceSize.height / Self.canvasSize.height
        )
        contentSize = CGSize(
            width: referenceSize.width * screenScale,
            height: referenceSize.height * screenScale
        )
        sizeScale = referenceScale * screenScale
        self.grid = grid
        self.showsNames = showsNames
        self.placement = placement
        let baseTileWidth = Self.baseTileWidth + (showsNames ? 0 : Self.baseLabelSpace)
        let rows = CGFloat(grid.rows)
        let columns = CGFloat(grid.columns)
        let availableWidth = contentSize.width * (1 - Self.insetRatio * 2) / sizeScale
        // 列间距不小于默认行距
        fitScale = min(
            1,
            Self.baseGridHeight / (Self.baseTileHeight * rows + Self.baseRowSpacing * (rows - 1)),
            availableWidth / (baseTileWidth * columns + Self.baseRowSpacing * (columns - 1))
        )
    }

    private var tileScale: CGFloat { sizeScale * fitScale }
    private var nameSpace: CGFloat { showsNames ? 0 : Self.baseLabelSpace }
    var iconSide: CGFloat { (Self.baseIconSide + nameSpace) * tileScale }
    var tileWidth: CGFloat { (Self.baseTileWidth + nameSpace) * tileScale }
    var tilePadding: CGFloat { 12 * tileScale }
    var iconLabelSpacing: CGFloat { showsNames ? 12 * tileScale : 0 }
    var labelFontSize: CGFloat { 14 * tileScale }
    var labelHeight: CGFloat { showsNames ? 17 * tileScale : 0 }
    var tileCornerRadius: CGFloat { 24 * tileScale }
    var folderRowSpacing: CGFloat { Self.baseRowSpacing * tileScale }

    var tileHeight: CGFloat {
        tilePadding * 2 + iconSide + iconLabelSpacing + labelHeight
    }

    var gridHeight: CGFloat { Self.baseGridHeight * sizeScale }

    // 行少时多出的高度均分到行距；集中排列时不超过默认行数的行距
    var rowSpacing: CGFloat {
        let spread = Self.spacing(total: gridHeight, tile: tileHeight, count: grid.rows)
        guard placement == .centered else {
            return spread
        }
        return min(spread, Self.spacing(total: gridHeight, tile: tileHeight, count: GridSize.default.rows))
    }

    private var gridWidth: CGFloat { contentSize.width * (1 - Self.insetRatio * 2) }

    var columnSpacing: CGFloat {
        let spread = Self.spacing(total: gridWidth, tile: tileWidth, count: grid.columns)
        guard placement == .centered else {
            return spread
        }
        return min(spread, Self.spacing(total: gridWidth, tile: tileWidth, count: GridSize.default.columns))
    }

    // 集中排列且列少时两侧留白加大；铺满时为固定比例
    var horizontalInset: CGFloat {
        let columns = CGFloat(grid.columns)
        return (contentSize.width - tileWidth * columns - columnSpacing * (columns - 1)) / 2
    }

    // 集中排列且行少时网格在区域内上下居中；铺满时为 0
    var gridTopInset: CGFloat {
        let rows = CGFloat(grid.rows)
        return (gridHeight - tileHeight * rows - rowSpacing * (rows - 1)) / 2
    }

    private static func spacing(total: CGFloat, tile: CGFloat, count: Int) -> CGFloat {
        (total - tile * CGFloat(count)) / CGFloat(count - 1)
    }

    var topInset: CGFloat { 51 * sizeScale }
    var searchBarWidth: CGFloat { 240 * sizeScale }
    var searchBarHeight: CGFloat { 40 * sizeScale }
    // 搜索框各尺寸按 LaunchOS 录屏测量
    var searchBarLeadingPadding: CGFloat { 15 * sizeScale }
    var searchBarPadding: CGFloat { 12 * sizeScale }
    var searchBarSpacing: CGFloat { 9 * sizeScale }
    var searchFontSize: CGFloat { 13.5 * sizeScale }
    var searchIconSize: CGFloat { 16 * sizeScale }
    var moreIconSize: CGFloat { 17 * sizeScale }
    var clearIconSize: CGFloat { 13 * sizeScale }
    var searchToGrid: CGFloat { 42 * sizeScale }
    var pageDotSize: CGFloat { 10 * sizeScale }
    var pageDotSpacing: CGFloat { 18 * sizeScale }
    var bottomInset: CGFloat { 40 * sizeScale }

    var folderCornerRadius: CGFloat { iconSide * 0.225 }
    var folderPreviewIconSide: CGFloat { iconSide * 0.19 }
    var folderPreviewSpacing: CGFloat { iconSide * 0.065 }
    var folderPanelOutset: CGFloat { 42 * sizeScale }
    var folderPanelPadding: CGFloat { 30 * sizeScale }
    var folderPanelCornerRadius: CGFloat { 36 * sizeScale }
    var folderTitleFontSize: CGFloat { 22 * sizeScale }
    var folderTitleHeight: CGFloat { 28 * sizeScale }
    var folderTitleSpacing: CGFloat { 30 * sizeScale }
    var uninstallBadgeSide: CGFloat { iconSide * 0.3 }

    func uninstallBadgeFrame(inTile tile: CGRect) -> CGRect {
        let side = uninstallBadgeSide
        return CGRect(
            x: tile.midX - iconSide / 2 - side * 0.2,
            y: tile.minY + tilePadding - side * 0.2,
            width: side,
            height: side
        )
    }

    func folderRowCount(memberCount: Int) -> Int {
        let rows = (memberCount + grid.columns - 1) / grid.columns
        return min(max(rows, 1), grid.rows)
    }

    func folderGridHeight(memberCount: Int) -> CGFloat {
        let rows = CGFloat(folderRowCount(memberCount: memberCount))
        return tileHeight * rows + folderRowSpacing * (rows - 1)
    }
}
