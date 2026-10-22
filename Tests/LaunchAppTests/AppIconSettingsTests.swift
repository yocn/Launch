import AppKit
import XCTest
@testable import LaunchApp

@MainActor
final class AppIconSettingsTests: XCTestCase {
    func testChoiceAndThemePersistWithSafeDefaults() {
        let name = "AppIconSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let initial = LauncherSettings(defaults: defaults)
        XCTAssertEqual(initial.appIconStyle, .grid)
        XCTAssertEqual(initial.appIconTheme, .system)
        initial.appIconStyle = .aperture
        initial.appIconTheme = .dark
        let restored = LauncherSettings(defaults: defaults)
        XCTAssertEqual(restored.appIconStyle, .aperture)
        XCTAssertEqual(restored.appIconTheme, .dark)
        defaults.set("obsolete", forKey: "appIconStyle")
        defaults.set("obsolete", forKey: "appIconTheme")
        XCTAssertEqual(LauncherSettings(defaults: defaults).appIconStyle, .grid)
        XCTAssertEqual(LauncherSettings(defaults: defaults).appIconTheme, .system)
    }

    func testSelectedDesignsCanBeRestoredFromPreferences() {
        let name = "AppIconSelectionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        // 用户确认的三套：四瓣、单色九宫格、蓝紫色四格；不能用折光 L 替代。
        for value in ["aperture", "grid", "tiles"] {
            defaults.set(value, forKey: "appIconStyle")
            XCTAssertEqual(LauncherSettings(defaults: defaults).appIconStyle.rawValue, value)
        }
        defaults.set("prism", forKey: "appIconStyle")
        XCTAssertEqual(LauncherSettings(defaults: defaults).appIconStyle, .grid)
    }

    func testExplicitThemeDoesNotChangeWithSystem() {
        XCTAssertFalse(AppIconTheme.system.isDark(systemIsDark: false))
        XCTAssertTrue(AppIconTheme.system.isDark(systemIsDark: true))
        XCTAssertFalse(AppIconTheme.light.isDark(systemIsDark: true))
        XCTAssertTrue(AppIconTheme.dark.isDark(systemIsDark: false))
    }

    func testEveryChoiceHasLoadableTransparentSquareArtwork() throws {
        for style in AppIconStyle.allCases {
            for dark in [false, true] {
                let image = try XCTUnwrap(AppIconAssets.image(style: style, dark: dark), "\(style) \(dark)")
                let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
                XCTAssertEqual(cgImage.width, cgImage.height)
                XCTAssertGreaterThanOrEqual(cgImage.width, 1024)
                XCTAssertNotEqual(cgImage.alphaInfo, .none)
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                for (x, y) in [(0, 0), (cgImage.width - 1, 0), (0, cgImage.height - 1),
                               (cgImage.width - 1, cgImage.height - 1)] {
                    // 柔和投影可能量化为 1/255；拒绝不透明展示背景，不苛求阴影逐字节为零。
                    XCTAssertLessThanOrEqual(try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent,
                                             1.0 / 255.0, "\(style) \(dark) 画布四角应透明")
                }
            }
        }
    }

    func testSelfIconOverrideSurvivesCatalogRefreshAndPendingLoad() {
        var finish: (@MainActor @Sendable (CGImage?) -> Void)?
        let cache = IconCache { _, completion in finish = completion }
        let path = "/Applications/Launch.app"
        XCTAssertNil(cache.icon(for: path))
        let selected = NSImage(size: NSSize(width: 32, height: 32))
        cache.setOverride(selected, for: path)
        XCTAssertTrue(cache.icon(for: path) === selected)
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        finish?(context.makeImage())
        XCTAssertTrue(cache.icon(for: path) === selected, "异步旧图标不得覆盖新选择")
        cache.removeAll()
        XCTAssertTrue(cache.icon(for: path) === selected)
    }
}
