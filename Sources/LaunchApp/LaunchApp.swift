import AppKit
import LaunchCore

public enum LauncherPlacement: Equatable, Sendable {
    case mouseScreen

    public static let defaultTarget = LauncherPlacement.mouseScreen
}

@main
struct LaunchApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = LaunchAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
private final class LaunchAppDelegate: NSObject, NSApplicationDelegate {
    private let presenter = ScreenPresenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let catalog = (try? AppCatalog().scan(
            roots: ApplicationSources.defaultRoots()
        )) ?? []
        presenter.show(catalog: catalog)
    }
}
