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

        XCTAssertEqual(settings.returnToFirstPage, .never)
        XCTAssertEqual(settings.screenChoice, .mouse)
        XCTAssertTrue(settings.optionEntersUninstallMode)
        XCTAssertEqual(settings.background, .glass)
        XCTAssertEqual(settings.dimming, 0.47)
        XCTAssertFalse(settings.hidesNames)
        XCTAssertFalse(settings.showsHiddenAppsInSearch)
        XCTAssertTrue(settings.showsMenuBarIcon)
    }

    func testReturnToFirstPageMigratesOldChoice() {
        let defaults = makeDefaults()
        defaults.set("firstPage", forKey: "reopenBehavior")
        XCTAssertEqual(LauncherSettings(defaults: defaults).returnToFirstPage, .always)

        defaults.set("resume", forKey: "reopenBehavior")
        XCTAssertEqual(LauncherSettings(defaults: defaults).returnToFirstPage, .never)
        XCTAssertEqual(ReturnToFirstPage.after1Minute.delay, 60)
        XCTAssertNil(ReturnToFirstPage.never.delay)
        XCTAssertEqual(ReturnToFirstPage.always.delay, 0)
    }

    func testCustomSourcesPersist() {
        let defaults = makeDefaults()
        let settings = LauncherSettings(defaults: defaults)
        XCTAssertEqual(settings.customSourcePaths, [])

        settings.customSourcePaths = ["/Volumes/Tools"]

        XCTAssertEqual(LauncherSettings(defaults: defaults).customSourcePaths, ["/Volumes/Tools"])
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

        settings.returnToFirstPage = .after30Seconds
        settings.screenChoice = .dock
        settings.optionEntersUninstallMode = false
        settings.background = .blurredWallpaper
        settings.dimming = 0.2
        settings.hidesNames = true
        settings.showsHiddenAppsInSearch = true
        settings.showsMenuBarIcon = false

        let reloaded = LauncherSettings(defaults: defaults)
        XCTAssertEqual(reloaded.returnToFirstPage, .after30Seconds)
        XCTAssertEqual(reloaded.screenChoice, .dock)
        XCTAssertFalse(reloaded.optionEntersUninstallMode)
        XCTAssertEqual(reloaded.background, .blurredWallpaper)
        XCTAssertEqual(reloaded.dimming, 0.2)
        XCTAssertTrue(reloaded.hidesNames)
        XCTAssertTrue(reloaded.showsHiddenAppsInSearch)
        XCTAssertFalse(reloaded.showsMenuBarIcon)
    }
}
