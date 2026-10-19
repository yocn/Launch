import LaunchCore

func layoutApp(_ name: String) -> CatalogApp {
    CatalogApp(
        identity: AppIdentity(
            bundleIdentifier: "com.example.\(name.lowercased())",
            path: "/Applications/\(name).app"
        ),
        displayName: name
    )
}
