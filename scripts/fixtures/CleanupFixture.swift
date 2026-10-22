import AppKit

// 仅用于用户授权的卸载验证；无后台任务、网络或文件写入。
@main
@MainActor
struct CleanupFixture {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 140),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Launch 卸载测试应用"
        window.isReleasedWhenClosed = false
        let label = NSTextField(wrappingLabelWithString: "这是自制的卸载测试应用。\n不读取个人文件，不访问网络。可安全用于验证退出与卸载。")
        label.frame = NSRect(x: 24, y: 35, width: 390, height: 70)
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
