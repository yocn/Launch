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

    static func roots(custom: [String], homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var seen = Set<String>()
        return (defaultRoots(homeDirectory: homeDirectory).map(\.path) + custom).map(normalized).compactMap { path in
            seen.insert(path).inserted ? URL(fileURLWithPath: path, isDirectory: true) : nil
        }
    }

    // 已在列表里或位于已有目录之下的跳过：子文件夹本来就会扫描
    static func adding(
        _ folders: [URL],
        to custom: [String],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> (custom: [String], skipped: [String]) {
        var custom = custom.map(normalized)
        var skipped: [String] = []
        for folder in folders {
            let path = normalized(folder.standardizedFileURL.path)
            let known = defaultRoots(homeDirectory: homeDirectory).map(\.path) + custom
            if known.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                skipped.append(path)
            } else {
                custom.append(path)
            }
        }
        return (custom, skipped)
    }

    private static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
