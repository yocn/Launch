import CoreGraphics

// SwiftUI 全局坐标以窗口内容左上角为原点，AppKit 窗口坐标以左下角为原点
enum LauncherCoordinates {
    static func global(fromWindow point: CGPoint, contentHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: contentHeight - point.y)
    }

    static func window(fromGlobal rect: CGRect, contentHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: contentHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
