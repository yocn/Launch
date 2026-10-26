import LaunchCore

func layoutApp(_ name: String) -> LaunchItem {
    LaunchItem(
        identity: AppIdentity(
            bundleIdentifier: "com.example.\(name.lowercased())",
            path: "/Applications/\(name).app"
        ),
        displayName: name
    )
}

// 测试里用应用构造条目
extension ItemIdentity {
    init(bundleIdentifier: String?, path: String) {
        self = .application(AppIdentity(bundleIdentifier: bundleIdentifier, path: path))
    }
}

extension LaunchItem {
    init(identity: AppIdentity, displayName: String, category: String? = nil) {
        self.init(application: CatalogApp(identity: identity, displayName: displayName, category: category))
    }
}
