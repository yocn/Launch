public struct LaunchpadApp: Equatable, Sendable {
    public let bundleIdentifier: String
    public let title: String

    public init(bundleIdentifier: String, title: String) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
    }
}

public enum LaunchpadItem: Equatable, Sendable {
    case app(LaunchpadApp)
    case folder(id: Int64, name: String, apps: [LaunchpadApp])
}

public struct LaunchpadSnapshot: Equatable, Sendable {
    public let pages: [[LaunchpadItem]]

    public init(pages: [[LaunchpadItem]]) {
        self.pages = pages
    }
}
