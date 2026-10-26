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
    static func normalized(_ data: Data, minimumSide: Int = 1, inputLimit: Int = 1_048_576) -> Data? {
        guard data.count <= inputLimit,
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
    // 返回内容与跟随跳转后的最终地址
    typealias Load = @Sendable (URL, Int) async throws -> (Data, URL)
    private let load: Load
    init(load: @escaping Load = BoundedWebsiteRequest.load) { self.load = load }

    // 图标常放在 CDN 等其他域名，只拦截凭证、非网页地址和局域网（访问局域网会触发系统的本地网络授权）
    static func isAllowed(_ url: URL, origin: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return host == origin.host?.lowercased() || !isLocal(host)
    }

    static func isLocal(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".local") || host.contains(":")
            || host.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil
    }

    func fetch(for url: URL) async -> Data? {
        guard (try? WebsiteAddress.normalized(url.absoluteString)) != nil else { return nil }
        let pageLimit = 512 * 1024
        var base = url
        var candidates: [URL] = []
        if let (data, finalURL) = try? await load(url, pageLimit), data.count <= pageLimit {
            if Self.isAllowed(finalURL, origin: url) { base = finalURL }
            candidates = Self.candidates(in: Self.text(of: data), base: base)
        }
        for path in ["/apple-touch-icon.png", "/favicon.ico"] {
            if let fallback = URL(string: path, relativeTo: base)?.absoluteURL { candidates.append(fallback) }
        }
        var seen = Set<URL>()
        for candidate in candidates.filter({ Self.isAllowed($0, origin: base) && seen.insert($0).inserted }).prefix(4) {
            guard !Task.isCancelled else { return nil }
            if let (data, _) = try? await load(candidate, 1_048_576), let icon = ItemImageData.normalized(data, minimumSide: 64) {
                return icon
            }
        }
        return nil
    }

    // 只需找 link 标签，UTF-8 失败时按国内网站常见的 GB18030 解码
    private static func text(of data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb)) ?? String(decoding: data, as: UTF8.self)
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
                  let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            icons.append((url, touch ? 0 : 1))
        }
        return icons.sorted { $0.1 < $1.1 }.map(\.0)
    }
}

// 跟随跳转，但不降级到 http、不跳到本地或带凭证的地址
private final class WebsiteRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, WebsiteIconFetcher.isAllowed(url, origin: origin),
              !(origin.scheme == "https" && url.scheme == "http") else { return completionHandler(nil) }
        completionHandler(request)
    }
}

private enum BoundedWebsiteRequest {
    static func load(_ url: URL, limit: Int) async throws -> (Data, URL) {
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
        return (result, response.url ?? url)
    }
}

// 用户给的图片链接：同步下载（图标编辑窗口是模态的，异步结果回不来），限大小与时间，拒绝本地地址
final class RemoteImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let sizeLimit = 8 * 1024 * 1024
    private var data = Data()
    private var tooLarge = false
    private var status = 0
    private let finished = DispatchSemaphore(value: 0)

    static func fetch(_ address: String, timeout: TimeInterval = 10) -> Data? {
        guard let url = try? WebsiteAddress.normalized(address), let host = url.host?.lowercased(),
              !WebsiteIconFetcher.isLocal(host) else { return nil }
        let download = RemoteImageDownload()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        let task = session.dataTask(with: url)
        task.resume()
        if download.finished.wait(timeout: .now() + timeout) == .timedOut { task.cancel() }
        session.invalidateAndCancel()
        guard (200 ... 299).contains(download.status), !download.tooLarge else { return nil }
        return ItemImageData.normalized(download.data, inputLimit: sizeLimit)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finished.signal()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= Self.sizeLimit else {
            tooLarge = true
            dataTask.cancel()
            return
        }
        self.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https" || task.originalRequest?.url?.scheme == "http",
              !WebsiteIconFetcher.isLocal(url.host?.lowercased() ?? "") else { return completionHandler(nil) }
        completionHandler(request)
    }
}
