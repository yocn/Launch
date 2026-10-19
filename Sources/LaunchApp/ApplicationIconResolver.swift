import AppKit
import Foundation

enum ApplicationIconResolver {
    static func icon(for path: String) -> NSImage {
        let appURL = URL(fileURLWithPath: path)
        if let iconURL = iconFileURL(for: appURL),
           let icon = NSImage(contentsOf: iconURL) {
            return icon
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    static func iconFileURL(for appURL: URL) -> URL? {
        guard let bundle = Bundle(url: appURL),
              let iconFile = bundle.object(
                forInfoDictionaryKey: "CFBundleIconFile"
              ) as? String else {
            return nil
        }

        let iconName = URL(fileURLWithPath: iconFile)
            .deletingPathExtension()
            .lastPathComponent
        guard !iconName.isEmpty,
              let iconPath = bundle.path(forResource: iconName, ofType: "icns") else {
            return nil
        }
        return URL(fileURLWithPath: iconPath)
    }
}
