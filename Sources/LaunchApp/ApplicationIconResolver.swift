import AppKit

enum ApplicationIconResolver {
    // 最大显示尺寸约 176 像素（2x 屏），留余量
    static let pixelSide = 256

    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        return queue
    }()

    // 读取应用包属性可能被系统卡住数秒（如挂起的授权弹窗），不能放在主线程
    static func loadInBackground(_ path: String, _ completion: @escaping @MainActor @Sendable (CGImage?) -> Void) {
        queue.addOperation {
            let start = Date()
            let image = icon(for: path)
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 1 {
                AppLog.shared.warning(String(format: "读取图标耗时 %.1f 秒：%@", elapsed, path))
            }
            Task { @MainActor in
                completion(image)
            }
        }
    }

    // 栅格化后主线程绘制时不再读取应用包
    static func icon(for path: String) -> CGImage? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let side = CGFloat(pixelSide)
        guard let context = CGContext(
            data: nil,
            width: pixelSide,
            height: pixelSide,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
