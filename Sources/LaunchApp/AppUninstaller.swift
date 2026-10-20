import AppKit
import LaunchCore

protocol RunningAppHandle: AnyObject {
    var bundleIdentifier: String? { get }
    var bundlePath: String? { get }
    var isTerminated: Bool { get }
    func terminate() -> Bool
}

extension NSRunningApplication: RunningAppHandle {
    var bundlePath: String? {
        bundleURL?.path(percentEncoded: false)
    }
}

enum UninstallError: LocalizedError, Equatable {
    case notAllowed

    var errorDescription: String? {
        "该应用不能直接移到废纸篓"
    }
}

@MainActor
struct AppUninstaller {
    var roots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
    ]
    var ownBundlePath = Bundle.main.bundleURL.path(percentEncoded: false)
    var fileManager = FileManager.default
    var quitTimeout: TimeInterval = 5
    var runningApplications: () -> [any RunningAppHandle] = { NSWorkspace.shared.runningApplications }
    var trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    // 只允许当前用户能直接移动的应用；系统应用、符号链接入口和需要管理员权限的都不行
    func canUninstall(_ app: CatalogApp) -> Bool {
        let path = Self.normalized(app.identity.path)
        guard path.hasSuffix(".app"),
              !path.hasPrefix("/System/"),
              path != Self.normalized(ownBundlePath),
              roots.contains(where: { path.hasPrefix(Self.normalized($0.path(percentEncoded: false)) + "/") }),
              let attributes = try? fileManager.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
            return false
        }
        let parent = (path as NSString).deletingLastPathComponent
        return fileManager.isWritableFile(atPath: path) && fileManager.isWritableFile(atPath: parent)
    }

    func runningInstance(of app: CatalogApp) -> (any RunningAppHandle)? {
        let path = Self.normalized(app.identity.path)
        return runningApplications().first { running in
            if let bundlePath = running.bundlePath, Self.normalized(bundlePath) == path {
                return true
            }
            guard let bundleIdentifier = app.identity.bundleIdentifier else {
                return false
            }
            return running.bundleIdentifier == bundleIdentifier
        }
    }

    func quit(_ running: any RunningAppHandle) async -> Bool {
        if !running.isTerminated {
            _ = running.terminate()
        }
        let deadline = Date().addingTimeInterval(quitTimeout)
        while !running.isTerminated, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return running.isTerminated
    }

    func moveToTrash(_ app: CatalogApp) throws {
        guard canUninstall(app) else {
            throw UninstallError.notAllowed
        }
        try trash(URL(fileURLWithPath: app.identity.path))
    }

    private static func normalized(_ path: String) -> String {
        (path as NSString).standardizingPath
    }
}
