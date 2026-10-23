import AppKit

// 打包时从 docs/guide.html 拷进应用的 Resources
@MainActor
enum UserGuide {
    static let url = Bundle.main.url(forResource: "guide", withExtension: "html")

    static func open() {
        guard let url else {
            return
        }
        // 同步的 open 会等浏览器启动完成，把调用方卡住
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
    }
}
