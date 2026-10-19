import AppKit
import Foundation

enum ApplicationIconResolver {
    static func icon(for path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}
