import Foundation

enum ApplicationSources {
    static func defaultRoots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            homeDirectory.appending(path: "Applications", directoryHint: .isDirectory),
        ]
    }
}
