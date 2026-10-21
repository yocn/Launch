import XCTest
@testable import LaunchCore

final class AppCategoryTests: XCTestCase {
    func testMapsAppStoreCategories() {
        XCTAssertEqual(AppCategory.name(for: "public.app-category.productivity", bundleIdentifier: nil), "效率")
        XCTAssertEqual(AppCategory.name(for: "public.app-category.developer-tools", bundleIdentifier: nil), "开发者工具")
        XCTAssertEqual(AppCategory.name(for: "public.app-category.puzzle-games", bundleIdentifier: nil), "游戏")
        XCTAssertNil(AppCategory.name(for: "public.app-category.unknown", bundleIdentifier: nil))
    }

    func testFillsAppleAppsWithoutCategory() {
        XCTAssertEqual(AppCategory.name(for: nil, bundleIdentifier: "com.apple.weather"), "天气")
        XCTAssertEqual(AppCategory.name(for: nil, bundleIdentifier: "com.apple.calculator"), "实用工具")
        XCTAssertEqual(AppCategory.name(for: "", bundleIdentifier: "com.apple.stocks"), "财务")
        XCTAssertNil(AppCategory.name(for: nil, bundleIdentifier: "com.google.Chrome"))
    }
}
