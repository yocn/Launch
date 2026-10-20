import AppKit
import CoreImage

struct Wallpaper {
    enum Fill: Equatable {
        case aspectFill
        case aspectFit
        case stretch
        case center
    }

    let image: NSImage
    let fill: Fill
    let fillColor: NSColor?
}

@MainActor
final class WallpaperProvider {
    private struct CacheKey: Hashable {
        let url: URL
        let blurred: Bool
    }

    private var cache: [CacheKey: NSImage] = [:]

    func wallpaper(for screen: NSScreen, blurred: Bool) -> Wallpaper? {
        wallpaper(
            url: NSWorkspace.shared.desktopImageURL(for: screen),
            options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:],
            blurred: blurred
        )
    }

    func wallpaper(url: URL?, options: [NSWorkspace.DesktopImageOptionKey: Any], blurred: Bool = false) -> Wallpaper? {
        guard let url, let image = image(at: url, blurred: blurred) else {
            return nil
        }
        let scaling = (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) }
        let allowsClipping = options[.allowClipping] as? Bool ?? true
        let fill: Wallpaper.Fill
        switch scaling {
        case .scaleAxesIndependently:
            fill = .stretch
        case .scaleNone:
            fill = .center
        default:
            fill = allowsClipping ? .aspectFill : .aspectFit
        }
        return Wallpaper(image: image, fill: fill, fillColor: options[.fillColor] as? NSColor)
    }

    private func image(at url: URL, blurred: Bool) -> NSImage? {
        let key = CacheKey(url: url, blurred: blurred)
        if let cached = cache[key] {
            return cached
        }
        guard let source = NSImage(contentsOf: url),
              let image = blurred ? Self.blur(source) : source else {
            return nil
        }
        cache[key] = image
        return image
    }

    // 预先模糊再缓存：SwiftUI 的 blur 是图层效果，离屏渲染画不出来，也省掉每次显示的实时模糊
    private static func blur(_ image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let input = CIImage(cgImage: cgImage)
        let sigma = Double(max(cgImage.width, cgImage.height)) * 0.02
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        guard let result = CIContext().createCGImage(output, from: input.extent) else {
            return nil
        }
        return NSImage(cgImage: result, size: image.size)
    }
}
