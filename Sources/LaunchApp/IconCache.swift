import AppKit

@MainActor
final class IconCache {
    static let shared = IconCache(loader: ApplicationIconResolver.icon(for:))

    private let cache = NSCache<NSString, NSImage>()
    private let loader: (String) -> NSImage

    init(loader: @escaping (String) -> NSImage) {
        self.loader = loader
    }

    func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }
        let icon = loader(path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
