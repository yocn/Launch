import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class IconEntry {
    fileprivate(set) var image: NSImage?
}

@MainActor
final class IconCache {
    typealias Load = (String, @escaping @MainActor @Sendable (CGImage?) -> Void) -> Void

    static let shared = IconCache(load: ApplicationIconResolver.loadInBackground)

    private var entries: [String: IconEntry] = [:]
    private let load: Load

    init(load: @escaping Load) {
        self.load = load
    }

    // 未读到时返回空并开始后台读取；读完只通知读过这个图标的视图
    func icon(for path: String) -> NSImage? {
        if let entry = entries[path] {
            return entry.image
        }
        let entry = IconEntry()
        entries[path] = entry
        load(path) { [weak self, weak entry] image in
            guard let self, let entry, entries[path] === entry, let image else {
                return
            }
            entry.image = NSImage(cgImage: image, size: .zero)
        }
        return entry.image
    }

    func removeAll() {
        entries.removeAll()
    }
}

struct AppIconImage: View {
    let path: String
    let side: CGFloat

    var body: some View {
        if let icon = IconCache.shared.icon(for: path) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
        } else {
            RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(width: side, height: side)
        }
    }
}
