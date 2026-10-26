import Foundation

struct BookmarkNode: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL?
    var children: [BookmarkNode]

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
        guard FileManager.default.fileExists(atPath: url.path) else { throw BookmarkError.notFound(browser.rawValue) }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            throw BookmarkError.needsFullDiskAccess
        }
        switch browser {
        case .chrome: return try parseChrome(data)
        case .safari: return try parseSafari(data)
        }
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
            guard title != "com.apple.ReadingList", title != "History" else { return nil }
            guard let node = safariNode(dict), !node.children.isEmpty else { return nil }
            let names = ["BookmarksBar": "个人收藏", "BookmarksMenu": "书签菜单"]
            return .folder(names[title] ?? title, node.children)
        }
    }

    private static func safariNode(_ dict: [String: Any]) -> BookmarkNode? {
        switch dict["WebBookmarkType"] as? String {
        case "WebBookmarkTypeLeaf":
            guard let url = webURL(dict["URLString"] as? String) else { return nil }
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
        guard let text, let url = try? WebsiteAddress.normalized(text), text.lowercased().hasPrefix("http") else { return nil }
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
