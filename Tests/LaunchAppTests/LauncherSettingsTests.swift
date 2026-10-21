import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
final class LauncherSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "LauncherSettingsTests-\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return UserDefaults(suiteName: name)!
    }

    func testDefaults() {
        let settings = LauncherSettings(defaults: makeDefaults())

        XCTAssertEqual(settings.reopenBehavior, .resume)
        XCTAssertEqual(settings.background, .glass)
        XCTAssertEqual(settings.dimming, 0.47)
        XCTAssertFalse(settings.hidesNames)
        XCTAssertFalse(settings.showsHiddenAppsInSearch)
        XCTAssertTrue(settings.showsMenuBarIcon)
    }

    func testSortDefaultsAndPersists() {
        let defaults = makeDefaults()
        let settings = LauncherSettings(defaults: defaults)
        XCTAssertEqual(settings.displaySort, DisplaySort())

        settings.sortField = .lastUsed
        settings.sortDescending = true
        settings.sortsFolderContents = true
        settings.folderPlacement = .last

        XCTAssertEqual(
            LauncherSettings(defaults: defaults).displaySort,
            DisplaySort(field: .lastUsed, descending: true, sortsFolderContents: true, folderPlacement: .last)
        )
    }

    func testGridDefaultsAndPersists() {
        let defaults = makeDefaults()
        let settings = LauncherSettings(defaults: defaults)
        XCTAssertEqual(settings.grid, .default)

        settings.gridColumns = 5
        settings.gridRows = 4

        XCTAssertEqual(LauncherSettings(defaults: defaults).grid, GridSize(columns: 5, rows: 4))
    }

    func testChangesPersist() {
        let defaults = makeDefaults()
        let settings = LauncherSettings(defaults: defaults)

        settings.reopenBehavior = .firstPage
        settings.background = .blurredWallpaper
        settings.dimming = 0.2
        settings.hidesNames = true
        settings.showsHiddenAppsInSearch = true
        settings.showsMenuBarIcon = false

        let reloaded = LauncherSettings(defaults: defaults)
        XCTAssertEqual(reloaded.reopenBehavior, .firstPage)
        XCTAssertEqual(reloaded.background, .blurredWallpaper)
        XCTAssertEqual(reloaded.dimming, 0.2)
        XCTAssertTrue(reloaded.hidesNames)
        XCTAssertTrue(reloaded.showsHiddenAppsInSearch)
        XCTAssertFalse(reloaded.showsMenuBarIcon)
    }
}
