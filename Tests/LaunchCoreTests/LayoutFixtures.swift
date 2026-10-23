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

// Fixtures represent real application targets without exposing file paths on generic identities.
extension ItemIdentity {
    init(bundleIdentifier: String?, path: String) {
        self = .application(AppIdentity(bundleIdentifier: bundleIdentifier, path: path))
    }
}
