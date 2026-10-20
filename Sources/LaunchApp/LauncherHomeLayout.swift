import CoreGraphics

struct LauncherHomeLayout: Equatable {
    static let columnCount = 7
    static let rowCount = 5
    static let pageCapacity = columnCount * rowCount

    // 以下尺寸按 1512×982 主屏调校，参考屏不同尺寸时整体缩放
    static let canvasSize = CGSize(width: 1512, height: 982)

    let contentSize: CGSize
    let sizeScale: CGFloat

    init(screenSize: CGSize, referenceSize: CGSize) {
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
    }

    var iconSide: CGFloat { 88 * sizeScale }
    var tileWidth: CGFloat { 112 * sizeScale }
    var tilePadding: CGFloat { 12 * sizeScale }
    var iconLabelSpacing: CGFloat { 12 * sizeScale }
    var labelFontSize: CGFloat { 14 * sizeScale }
    var labelHeight: CGFloat { 17 * sizeScale }
    var tileCornerRadius: CGFloat { 24 * sizeScale }
    var rowSpacing: CGFloat { 17 * sizeScale }

    var tileHeight: CGFloat {
        tilePadding * 2 + iconSide + iconLabelSpacing + labelHeight
    }

    var gridHeight: CGFloat {
        let rows = CGFloat(Self.rowCount)
        return tileHeight * rows + rowSpacing * (rows - 1)
    }

    var horizontalInset: CGFloat { contentSize.width * 0.09 }

    var columnSpacing: CGFloat {
        let columns = CGFloat(Self.columnCount)
        return (contentSize.width - horizontalInset * 2 - tileWidth * columns) / (columns - 1)
    }

    var topInset: CGFloat { 51 * sizeScale }
    var searchBarWidth: CGFloat { 240 * sizeScale }
    var searchBarHeight: CGFloat { 42 * sizeScale }
    var searchBarPadding: CGFloat { 12 * sizeScale }
    var searchBarSpacing: CGFloat { 14 * sizeScale }
    var searchFontSize: CGFloat { 14 * sizeScale }
    var searchIconSize: CGFloat { 15 * sizeScale }
    var clearIconSize: CGFloat { 13 * sizeScale }
    var searchShadowRadius: CGFloat { 14 * sizeScale }
    var searchShadowOffset: CGFloat { 8 * sizeScale }
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
        let rows = (memberCount + Self.columnCount - 1) / Self.columnCount
        return min(max(rows, 1), Self.rowCount)
    }

    func folderGridHeight(memberCount: Int) -> CGFloat {
        let rows = CGFloat(folderRowCount(memberCount: memberCount))
        return tileHeight * rows + rowSpacing * (rows - 1)
    }
}
