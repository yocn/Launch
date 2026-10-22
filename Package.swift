// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Launch",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LaunchCore", targets: ["LaunchCore"]),
        .executable(name: "LaunchApp", targets: ["LaunchApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "LaunchCore"),
        .executableTarget(
            name: "LaunchApp",
            dependencies: [
                "LaunchCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            resources: [.copy("AppIcons")]
        ),
        .testTarget(name: "LaunchCoreTests", dependencies: ["LaunchCore"]),
        .testTarget(name: "LaunchAppTests", dependencies: ["LaunchApp", "LaunchCore"]),
    ]
)
