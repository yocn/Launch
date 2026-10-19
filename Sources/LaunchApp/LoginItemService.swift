import Foundation
import ServiceManagement

enum LoginItemAvailability {
    static func isAvailable(bundleIdentifier: String?, bundleURL: URL, homeDirectory: URL) -> Bool {
        guard bundleIdentifier != nil, bundleURL.pathExtension == "app" else {
            return false
        }
        let parentPath = bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let allowedPaths = [
            "/Applications",
            homeDirectory.appending(path: "Applications").standardizedFileURL.path,
        ]
        return allowedPaths.contains(parentPath)
    }
}

@MainActor
final class LoginItemService {
    private let service = SMAppService.mainApp

    var isAvailable: Bool {
        LoginItemAvailability.isAvailable(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            bundleURL: Bundle.main.bundleURL,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            guard service.status == .requiresApproval else {
                throw error
            }
        }
        if enabled, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
