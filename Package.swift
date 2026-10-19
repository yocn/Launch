// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Launch",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LaunchCore", targets: ["LaunchCore"]),
        .executable(name: "LaunchApp", targets: ["LaunchApp"]),
    ],
    targets: [
        .target(name: "LaunchCore"),
        .executableTarget(name: "LaunchApp", dependencies: ["LaunchCore"]),
        .testTarget(name: "LaunchCoreTests", dependencies: ["LaunchCore"]),
        .testTarget(name: "LaunchAppTests", dependencies: ["LaunchApp"]),
    ]
)
