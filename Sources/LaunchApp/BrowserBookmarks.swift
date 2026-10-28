import Foundation
import CryptoKit
import SQLite3

struct BookmarkNode: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL?
    var children: [BookmarkNode]
    // 浏览器本地缓存的小图标，只用于选择列表预览
    var icon: Data?

    static func link(_ name: String, _ url: URL) -> BookmarkNode { BookmarkNode(name: name, url: url, children: []) }
    static func folder(_ name: String, _ children: [BookmarkNode]) -> BookmarkNode { BookmarkNode(name: name, url: nil, children: children) }
    var isFolder: Bool { url == nil }
}

enum BookmarkBrowser: String, CaseIterable {
    case chrome = "Chrome"
    case safari = "Safari"

    var fileURL: URL {
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        switch self {
        case .chrome: return library.appending(path: "Application Support/Google/Chrome/Default/Bookmarks")
        case .safari: return library.appending(path: "Safari/Bookmarks.plist")
        }
    }
}

enum BookmarkError: LocalizedError {
    case notFound(String), needsFullDiskAccess, invalid
    var errorDescription: String? {
        switch self {
        case .notFound(let name): "没有找到 \(name) 的书签"
        case .needsFullDiskAccess: "读取 Safari 书签需要在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中允许 Launch"
        case .invalid: "书签文件格式无法识别"
        }
    }
}

// 只读，不修改浏览器数据；只保留 http/https 链接，空文件夹不显示
enum BrowserBookmarks {
    static func load(_ browser: BookmarkBrowser) throws -> [BookmarkNode] {
        let url = browser.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BookmarkError.notFound(browser.rawValue)
        }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            throw BookmarkError.needsFullDiskAccess
        }
        switch browser {
        case .chrome:
            let icons = chromeFavicons()
            return try parseChrome(data).map { attach(icons, to: $0) }
        case .safari:
            let icons = safariFavicons()
            let tree = try parseSafari(data)
            let all = links(in: tree, matching: "").count
            let hit = links(in: tree.map { attach(icons, to: $0) }, matching: "").filter { $0.icon != nil }.count
            DebugLog.log("Safari 图标库 \(icons.count) 个网址，书签命中 \(hit)/\(all)")
            return tree.map { attach(icons, to: $0) }
        }
    }

    // Chrome 的 Favicons 库运行时被占用，复制一份只读打开；按网址取最大的一张
    static func chromeFavicons() -> [String: Data] {
        let source = BookmarkBrowser.chrome.fileURL.deletingLastPathComponent().appending(path: "Favicons")
        let copy = FileManager.default.temporaryDirectory.appending(path: "launch-favicons-\(UUID().uuidString).db")
        guard (try? FileManager.default.copyItem(at: source, to: copy)) != nil else {
            return [:]
        }
        defer { try? FileManager.default.removeItem(at: copy) }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_close(db) }
        let sql = "SELECT m.page_url, b.image_data FROM icon_mapping m JOIN favicon_bitmaps b ON b.icon_id = m.icon_id ORDER BY b.width DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }
        var result: [String: Data] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0), let bytes = sqlite3_column_blob(statement, 1) else {
                continue
            }
            let url = String(cString: text)
            if result[url] == nil {
                result[url] = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            }
        }
        return result
    }

    // Safari 的 Favicon Cache：page_url 记网址到图标 uuid，图片文件在 favicons 目录下（ICO，文件名是 32 位十六进制）
    static func safariFavicons() -> [String: Data] {
        let base = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari/Favicon Cache")
        let dir = FileManager.default.temporaryDirectory.appending(path: "launch-safari-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let copy = dir.appending(path: "favicons.db")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.copyItem(atPath: base.appending(path: "favicons.db").path + suffix, toPath: copy.path + suffix)
        }
        var db: OpaquePointer?
        // WAL 里还有未合并的内容，需要读写方式打开才会应用
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_close(db) }
        let sql = "SELECT p.url, i.uuid, i.url, i.width FROM page_url p JOIN icon_info i ON i.uuid = p.uuid ORDER BY i.width DESC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }
        let files = base.appending(path: "favicons")
        func md5(_ text: String) -> String {
            Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02X", $0) }.joined()
        }
        var result: [String: Data] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let page = sqlite3_column_text(statement, 0), let uuid = sqlite3_column_text(statement, 1),
                  let icon = sqlite3_column_text(statement, 2) else { continue }
            let key = String(cString: page)
            guard result[key] == nil else {
                continue
            }
            let id = String(cString: uuid)
            let names = [md5(id), md5(id.lowercased()), md5(String(cString: icon))]
            for name in names {
                if let data = try? Data(contentsOf: files.appending(path: name)) {
                    result[key] = data
                    break
                }
            }
        }
        return result
    }

    static func attach(_ icons: [String: Data], to node: BookmarkNode) -> BookmarkNode {
        var node = node
        node.icon = node.url.flatMap { url in
            let full = url.absoluteString
            let origin = url.scheme.flatMap { scheme in url.host.map { "\(scheme)://\($0)" } } ?? ""
            return icons[full] ?? icons[full.hasSuffix("/") ? String(full.dropLast()) : full + "/"] ?? icons[origin]
        }
        node.children = node.children.map { attach(icons, to: $0) }
        return node
    }

    static func parseChrome(_ data: Data) throws -> [BookmarkNode] {
        guard let root = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["roots"] as? [String: Any] else {
            throw BookmarkError.invalid
        }
        return ["bookmark_bar", "other", "synced"].compactMap { key in
            (root[key] as? [String: Any]).flatMap(chromeNode).flatMap { $0.children.isEmpty ? nil : $0 }
        }
    }

    private static func chromeNode(_ dict: [String: Any]) -> BookmarkNode? {
        let name = (dict["name"] as? String) ?? ""
        if dict["type"] as? String == "url" {
            return webURL(dict["url"] as? String).map { .link(name.isEmpty ? ($0.host ?? "") : name, $0) }
        }
        let children = (dict["children"] as? [[String: Any]] ?? []).compactMap(chromeNode)
        return children.isEmpty ? nil : .folder(name, children)
    }

    static func parseSafari(_ data: Data) throws -> [BookmarkNode] {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw BookmarkError.invalid
        }
        return (root["Children"] as? [[String: Any]] ?? []).compactMap { dict in
            let title = dict["Title"] as? String ?? ""
            // 阅读列表和历史记录不是书签
            guard title != "com.apple.ReadingList", title != "History" else {
                return nil
            }
            guard let node = safariNode(dict), !node.children.isEmpty else {
                return nil
            }
            let names = ["BookmarksBar": "个人收藏", "BookmarksMenu": "书签菜单"]
            return .folder(names[title] ?? title, node.children)
        }
    }

    private static func safariNode(_ dict: [String: Any]) -> BookmarkNode? {
        switch dict["WebBookmarkType"] as? String {
        case "WebBookmarkTypeLeaf":
            guard let url = webURL(dict["URLString"] as? String) else {
                return nil
            }
            let title = (dict["URIDictionary"] as? [String: Any])?["title"] as? String ?? ""
            return .link(title.isEmpty ? (url.host ?? "") : title, url)
        case "WebBookmarkTypeList":
            let children = (dict["Children"] as? [[String: Any]] ?? []).compactMap(safariNode)
            return children.isEmpty ? nil : .folder(dict["Title"] as? String ?? "", children)
        default:
            return nil
        }
    }

    private static func webURL(_ text: String?) -> URL? {
        guard let text, let url = try? WebsiteAddress.normalized(text), text.lowercased().hasPrefix("http") else {
            return nil
        }
        return url
    }

    // 搜索名称或网址，空查询返回全部
    static func links(in tree: [BookmarkNode], matching query: String) -> [BookmarkNode] {
        let query = query.trimmingCharacters(in: .whitespaces)
        func flat(_ nodes: [BookmarkNode]) -> [BookmarkNode] { nodes.flatMap { $0.isFolder ? flat($0.children) : [$0] } }
        return flat(tree).filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || ($0.url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}
