import AppKit

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
    private var cache: [URL: NSImage] = [:]

    func wallpaper(for screen: NSScreen) -> Wallpaper? {
        wallpaper(
            url: NSWorkspace.shared.desktopImageURL(for: screen),
            options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        )
    }

    func wallpaper(url: URL?, options: [NSWorkspace.DesktopImageOptionKey: Any]) -> Wallpaper? {
        guard let url, let image = image(at: url) else {
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

    private func image(at url: URL) -> NSImage? {
        if let cached = cache[url] {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache[url] = image
        return image
    }
}
