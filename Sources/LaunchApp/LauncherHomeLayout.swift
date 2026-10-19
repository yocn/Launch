import CoreGraphics

enum LauncherHomeLayout {
    static let columnCount = 7
    static let rowCount = 5
    static let pageCapacity = columnCount * rowCount

    static func iconSideLength(for screenSize: CGSize) -> CGFloat {
        let availableSide = min(screenSize.width / 18, screenSize.height / 12)
        return min(max(availableSide, 88), 160)
    }

    static func horizontalInset(for screenSize: CGSize) -> CGFloat {
        max(56, screenSize.width * 0.09)
    }

    static func columnSpacing(for screenSize: CGSize, itemWidth: CGFloat) -> CGFloat {
        let usableWidth = screenSize.width - horizontalInset(for: screenSize) * 2
        let naturalSpacing = (usableWidth - itemWidth * CGFloat(columnCount))
            / CGFloat(columnCount - 1)
        return max(32, naturalSpacing)
    }

    static func gridHeight(for screenSize: CGSize) -> CGFloat {
        screenSize.height * 0.7
    }

    static func rowSpacing(for screenSize: CGSize, iconSide: CGFloat) -> CGFloat {
        let tileHeight = iconSide + 56
        let availableSpacing = (
            gridHeight(for: screenSize) - tileHeight * CGFloat(rowCount)
        ) / CGFloat(rowCount - 1)
        return min(max(availableSpacing, 18), 48)
    }
}
