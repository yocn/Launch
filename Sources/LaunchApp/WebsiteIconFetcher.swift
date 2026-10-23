import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WebsiteAddress {
    static func normalized(_ text: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { throw WebsiteError.invalidAddress }
        let hasScheme = trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
        let address = hasScheme ? trimmed : "https://" + trimmed
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw WebsiteError.invalidAddress
        }
        return url
    }
}

enum WebsiteError: LocalizedError {
    case invalidAddress, rejectedResponse
    var errorDescription: String? {
        switch self {
        case .invalidAddress: "请输入有效的 HTTP 或 HTTPS 网址，不支持账号密码或本地文件地址。"
        case .rejectedResponse: "无法安全获取网站图标"
        }
    }
}

enum ItemImageData {
    static func normalized(_ data: Data, minimumSide: Int = 1) -> Data? {
        guard data.count <= 1_048_576,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let count = min(CGImageSourceGetCount(source), 32)
        var selected: (index: Int, side: Int)?
        for index in 0 ..< count {
            guard let info = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = info[kCGImagePropertyPixelWidth] as? Int,
                  let height = info[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192 else { continue }
            let side = min(width, height)
            if side >= minimumSide, side > (selected?.side ?? 0) { selected = (index, side) }
        }
        guard let selected, let image = CGImageSourceCreateThumbnailAtIndex(source, selected.index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { return nil }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), result.length <= 1_048_576 else { return nil }
        return result as Data
    }
}

struct WebsiteIconFetcher: Sendable {
    typealias Load = @Sendable (URL, Int) async throws -> Data
    private let load: Load
    init(load: @escaping Load = BoundedWebsiteRequest.load) { self.load = load }

    static func isAllowed(_ url: URL, origin: URL) -> Bool {
        let valid = ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        return valid && url.scheme?.lowercased() == origin.scheme?.lowercased()
            && url.host?.lowercased() == origin.host?.lowercased() && url.port == origin.port
            && url.user == nil && url.password == nil
    }

    func fetch(for url: URL) async -> Data? {
        guard (try? WebsiteAddress.normalized(url.absoluteString)) != nil else { return nil }
        let pageLimit = 512 * 1024
        let data = try? await load(url, pageLimit)
        var candidates: [URL] = []
        if let data, data.count <= pageLimit, let html = String(data: data, encoding: .utf8) {
            candidates = Self.candidates(in: html, base: url)
        }
        if let fallback = URL(string: "/favicon.ico", relativeTo: url)?.absoluteURL { candidates.append(fallback) }
        var seen = Set<URL>()
        for candidate in candidates.filter({ Self.isAllowed($0, origin: url) && seen.insert($0).inserted }).prefix(3) {
            guard !Task.isCancelled else { return nil }
            if let data = try? await load(candidate, 1_048_576), let icon = ItemImageData.normalized(data, minimumSide: 64) {
                return icon
            }
        }
        return nil
    }

    private static func candidates(in html: String, base: URL) -> [URL] {
        guard let links = try? NSRegularExpression(pattern: #"<link\b[^>]{0,8192}>"#, options: .caseInsensitive),
              let attribute = try? NSRegularExpression(pattern: #"([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#) else { return [] }
        let text = html as NSString
        var icons: [(URL, Int)] = []
        for link in links.matches(in: html, range: NSRange(location: 0, length: text.length)).prefix(128) {
            let tag = text.substring(with: link.range)
            let tagText = tag as NSString
            var attrs: [String: String] = [:]
            for pair in attribute.matches(in: tag, range: NSRange(location: 0, length: tagText.length)) {
                let key = tagText.substring(with: pair.range(at: 1)).lowercased()
                let value = (2 ... 4).first { pair.range(at: $0).location != NSNotFound }.map { tagText.substring(with: pair.range(at: $0)) } ?? ""
                attrs[key] = value.replacingOccurrences(of: "&amp;", with: "&")
            }
            let rel = (attrs["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            let touch = rel.contains { $0.hasPrefix("apple-touch-icon") }
            guard touch || rel.contains("icon"), let href = attrs["href"],
                  let url = URL(string: href, relativeTo: base)?.absoluteURL, isAllowed(url, origin: base) else { continue }
            icons.append((url, touch ? 0 : 1))
        }
        return icons.sorted { $0.1 < $1.1 }.map(\.0)
    }
}

private final class WebsiteRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { WebsiteIconFetcher.isAllowed($0, origin: origin) } == true ? request : nil)
    }
}

private enum BoundedWebsiteRequest {
    static func load(_ url: URL, limit: Int) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        let policy = WebsiteRedirectPolicy(origin: url)
        let session = URLSession(configuration: configuration, delegate: policy, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
              response.expectedContentLength <= Int64(limit) else { throw WebsiteError.rejectedResponse }
        var result = Data()
        for try await byte in bytes {
            guard result.count < limit else { throw WebsiteError.rejectedResponse }
            result.append(byte)
        }
        return result
    }
}
