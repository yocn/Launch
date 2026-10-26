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
    // 应用包的修改标记；变了说明应用在安装、更新或换了图标，缓存的图标可能是占位图
    typealias Signature = @Sendable (String) -> String?

    static let shared = IconCache(load: ApplicationIconResolver.loadInBackground)

    private var entries: [String: IconEntry] = [:]
    private var overrides: [String: NSImage] = [:]
    private var signatures: [String: String] = [:]
    private let load: Load
    private let signature: Signature

    init(load: @escaping Load, signature: @escaping Signature = IconCache.bundleSignature) {
        self.load = load
        self.signature = signature
    }

    nonisolated static func bundleSignature(_ path: String) -> String? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let dates = ["", "Contents", "Contents/Info.plist", "Contents/Resources"].map { part -> Date? in
            let url = part.isEmpty ? URL(fileURLWithPath: path) : URL(fileURLWithPath: path).appending(path: part)
            return (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate
        }
        guard dates.contains(where: { $0 != nil }) else { return nil }
        return dates.map { $0.map { String($0.timeIntervalSince1970) } ?? "-" }.joined(separator: "|")
    }

    // 未读到时返回空并开始后台读取；读完只通知读过这个图标的视图
    func icon(for path: String) -> NSImage? {
        if let entry = entries[path] {
            return entry.image
        }
        let entry = IconEntry()
        entries[path] = entry
        signatures[path] = signature(path)
        if let image = overrides[path] {
            entry.image = image
            return image
        }
        load(path) { [weak self, weak entry] image in
            guard let self, let entry, entries[path] === entry, overrides[path] == nil, let image else {
                return
            }
            entry.image = NSImage(cgImage: image, size: .zero)
        }
        return entry.image
    }

    func removeAll() {
        entries.removeAll()
        signatures.removeAll()
    }

    // 安装中读到占位图的应用，装完后就地重读，不换掉图标对象；读文件属性放后台，免得被系统卡住主线程
    func reloadChanged() async {
        let known = signatures.filter { overrides[$0.key] == nil }
        let signature = signature
        let current = await Task.detached(priority: .utility) {
            known.keys.reduce(into: [String: String?]()) { $0[$1] = signature($1) }
        }.value
        for (path, value) in current {
            guard let entry = entries[path], overrides[path] == nil, value != known[path], let value else { continue }
            signatures[path] = value
            load(path) { [weak self, weak entry] image in
                guard let self, let entry, entries[path] === entry, overrides[path] == nil, let image else {
                    return
                }
                entry.image = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    func setOverride(_ image: NSImage, for path: String) {
        overrides[path] = image
        entries[path]?.image = image
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
