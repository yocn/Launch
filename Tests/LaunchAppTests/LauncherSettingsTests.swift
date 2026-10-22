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

    func testSettingsWindowStyleDefaultsToGlassAndPersists() {
        let defaults = makeDefaults()
        let settings = LauncherSettings(defaults: defaults)
        XCTAssertEqual(settings.settingsWindowStyle, .glass)
        XCTAssertEqual(settings.settingsGlassOpacity, 0.5)

        settings.settingsWindowStyle = .standard
        settings.settingsGlassOpacity = 0.4

        let reloaded = LauncherSettings(defaults: defaults)
        XCTAssertEqual(reloaded.settingsWindowStyle, .standard)
        XCTAssertEqual(reloaded.settingsGlassOpacity, 0.4)
    }

    func testAppSwitcherAndStatusBarVisibilityPersistIndependently() {
        let defaults = makeDefaults()
        let settings = LauncherSettings(defaults: defaults)
        XCTAssertFalse(settings.showsInAppSwitcher)
        XCTAssertTrue(settings.showsMenuBarIcon)

        settings.showsInAppSwitcher = true
        settings.showsMenuBarIcon = false
        let dockOnly = LauncherSettings(defaults: defaults)
        XCTAssertTrue(dockOnly.showsInAppSwitcher)
        XCTAssertFalse(dockOnly.showsMenuBarIcon)

        dockOnly.showsInAppSwitcher = false
        dockOnly.showsMenuBarIcon = true
        let statusOnly = LauncherSettings(defaults: defaults)
        XCTAssertFalse(statusOnly.showsInAppSwitcher)
        XCTAssertTrue(statusOnly.showsMenuBarIcon)

        statusOnly.showsMenuBarIcon = false
        let hidden = LauncherSettings(defaults: defaults)
        XCTAssertFalse(hidden.showsInAppSwitcher)
        XCTAssertFalse(hidden.showsMenuBarIcon)
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

    func testSystemEntriesDefaultOffAndPersist() {
        let defaults = makeDefaults()
        let settings = LauncherSettings(defaults: defaults)
        XCTAssertEqual(settings.hotCorner, .off)
        XCTAssertFalse(settings.f4Launches)
        XCTAssertEqual(settings.pinchGesture, .off)

        settings.hotCorner = .bottomLeft
        settings.f4Launches = true
        settings.pinchGesture = .threeFingers

        let reloaded = LauncherSettings(defaults: defaults)
        XCTAssertEqual(reloaded.hotCorner, .bottomLeft)
        XCTAssertTrue(reloaded.f4Launches)
        XCTAssertEqual(reloaded.pinchGesture, .threeFingers)
    }

    func testDisplayModePersists() {
        let defaults = makeDefaults()
        let settings = LauncherSettings(defaults: defaults)
        XCTAssertEqual(settings.displayMode, .fullScreen)

        settings.displayMode = .window

        XCTAssertEqual(LauncherSettings(defaults: defaults).displayMode, .window)
    }

    func testBrowsingStylePersists() {
        let defaults = makeDefaults()
        let settings = LauncherSettings(defaults: defaults)
        XCTAssertEqual(settings.browsingStyle, .paged)

        settings.browsingStyle = .scroll

        XCTAssertEqual(LauncherSettings(defaults: defaults).browsingStyle, .scroll)
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
        XCTAssertEqual(settings.gridPlacement, .spread)

        settings.gridColumns = 5
        settings.gridRows = 4
        settings.gridPlacement = .centered

        XCTAssertEqual(LauncherSettings(defaults: defaults).grid, GridSize(columns: 5, rows: 4))
        XCTAssertEqual(LauncherSettings(defaults: defaults).gridPlacement, .centered)
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
