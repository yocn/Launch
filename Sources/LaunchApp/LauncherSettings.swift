import Foundation
import LaunchCore
import Observation

enum ReturnToFirstPage: String, CaseIterable {
    case never
    case after5Seconds
    case after15Seconds
    case after30Seconds
    case after1Minute
    case after5Minutes
    case always

    // 距上次关闭达到这个时长就回到第一页；为空表示从不
    var delay: TimeInterval? {
        switch self {
        case .never: nil
        case .after5Seconds: 5
        case .after15Seconds: 15
        case .after30Seconds: 30
        case .after1Minute: 60
        case .after5Minutes: 300
        case .always: 0
        }
    }
}

enum PinchGesture: String, CaseIterable {
    case off
    case threeFingers
    case fourOrFiveFingers
    case fiveFingers
}

enum DisplayMode: String, CaseIterable {
    case fullScreen
    case window
}

enum BrowsingStyle: String, CaseIterable {
    case paged
    case scroll
}

enum LauncherScreenChoice: String, CaseIterable {
    case mouse
    case active
    case dock
    case main
}

enum SettingsWindowStyle: String, CaseIterable {
    case glass
    case standard
}

enum LauncherBackgroundStyle: String, CaseIterable {
    case glass
    case blurredWallpaper
    case wallpaper
}

@MainActor
@Observable
final class LauncherSettings {
    static let defaultDimming = 0.47

    @ObservationIgnored private let defaults: UserDefaults

    var returnToFirstPage: ReturnToFirstPage {
        didSet { defaults.set(returnToFirstPage.rawValue, forKey: Key.returnToFirstPage) }
    }

    var screenChoice: LauncherScreenChoice {
        didSet { defaults.set(screenChoice.rawValue, forKey: Key.screenChoice) }
    }

    var optionEntersUninstallMode: Bool {
        didSet { defaults.set(optionEntersUninstallMode, forKey: Key.optionEntersUninstallMode) }
    }

    var customSourcePaths: [String] {
        didSet { defaults.set(customSourcePaths, forKey: Key.customSourcePaths) }
    }

    var browsingStyle: BrowsingStyle {
        didSet { defaults.set(browsingStyle.rawValue, forKey: Key.browsingStyle) }
    }

    var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }

    var hotCorner: HotCorner {
        didSet { defaults.set(hotCorner.rawValue, forKey: Key.hotCorner) }
    }

    var f4Launches: Bool {
        didSet { defaults.set(f4Launches, forKey: Key.f4Launches) }
    }

    var pinchGesture: PinchGesture {
        didSet { defaults.set(pinchGesture.rawValue, forKey: Key.pinchGesture) }
    }

    var background: LauncherBackgroundStyle {
        didSet { defaults.set(background.rawValue, forKey: Key.background) }
    }

    var dimming: Double {
        didSet { defaults.set(dimming, forKey: Key.dimming) }
    }

    var settingsWindowStyle: SettingsWindowStyle {
        didSet { defaults.set(settingsWindowStyle.rawValue, forKey: Key.settingsWindowStyle) }
    }

    var appIconStyle: AppIconStyle {
        didSet { defaults.set(appIconStyle.rawValue, forKey: Key.appIconStyle) }
    }

    var appIconTheme: AppIconTheme {
        didSet { defaults.set(appIconTheme.rawValue, forKey: Key.appIconTheme) }
    }

    // 玻璃上叠窗口底色的比例，0 为纯玻璃
    var settingsGlassOpacity: Double {
        didSet { defaults.set(settingsGlassOpacity, forKey: Key.settingsGlassOpacity) }
    }

    var hidesNames: Bool {
        didSet { defaults.set(hidesNames, forKey: Key.hidesNames) }
    }

    var showsHiddenAppsInSearch: Bool {
        didSet { defaults.set(showsHiddenAppsInSearch, forKey: Key.showsHiddenAppsInSearch) }
    }

    var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon) }
    }

    var showsInAppSwitcher: Bool {
        didSet { defaults.set(showsInAppSwitcher, forKey: Key.showsInAppSwitcher) }
    }

    var gridColumns: Int {
        didSet { defaults.set(gridColumns, forKey: Key.gridColumns) }
    }

    var gridRows: Int {
        didSet { defaults.set(gridRows, forKey: Key.gridRows) }
    }

    var grid: GridSize {
        GridSize(columns: gridColumns, rows: gridRows)
    }

    var sortField: SortField {
        didSet { defaults.set(sortField.rawValue, forKey: Key.sortField) }
    }

    var sortDescending: Bool {
        didSet { defaults.set(sortDescending, forKey: Key.sortDescending) }
    }

    var sortsFolderContents: Bool {
        didSet { defaults.set(sortsFolderContents, forKey: Key.sortsFolderContents) }
    }

    var folderPlacement: FolderPlacement {
        didSet { defaults.set(folderPlacement.rawValue, forKey: Key.folderPlacement) }
    }

    var displaySort: DisplaySort {
        DisplaySort(
            field: sortField,
            descending: sortDescending,
            sortsFolderContents: sortsFolderContents,
            folderPlacement: folderPlacement
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 旧版只有「停在上次的位置 / 回到第一页」两项
        returnToFirstPage = defaults.string(forKey: Key.returnToFirstPage).flatMap(ReturnToFirstPage.init)
            ?? (defaults.string(forKey: Key.legacyReopenBehavior) == "firstPage" ? .always : .never)
        screenChoice = defaults.string(forKey: Key.screenChoice).flatMap(LauncherScreenChoice.init) ?? .mouse
        optionEntersUninstallMode = defaults.object(forKey: Key.optionEntersUninstallMode) as? Bool ?? true
        customSourcePaths = defaults.stringArray(forKey: Key.customSourcePaths) ?? []
        browsingStyle = defaults.string(forKey: Key.browsingStyle).flatMap(BrowsingStyle.init) ?? .paged
        displayMode = defaults.string(forKey: Key.displayMode).flatMap(DisplayMode.init) ?? .fullScreen
        hotCorner = defaults.string(forKey: Key.hotCorner).flatMap(HotCorner.init) ?? .off
        f4Launches = defaults.bool(forKey: Key.f4Launches)
        pinchGesture = defaults.string(forKey: Key.pinchGesture).flatMap(PinchGesture.init) ?? .off
        background = defaults.string(forKey: Key.background).flatMap(LauncherBackgroundStyle.init) ?? .glass
        dimming = defaults.object(forKey: Key.dimming) as? Double ?? Self.defaultDimming
        settingsWindowStyle = defaults.string(forKey: Key.settingsWindowStyle).flatMap(SettingsWindowStyle.init) ?? .glass
        appIconStyle = defaults.string(forKey: Key.appIconStyle).flatMap(AppIconStyle.init) ?? .grid
        appIconTheme = defaults.string(forKey: Key.appIconTheme).flatMap(AppIconTheme.init) ?? .system
        settingsGlassOpacity = defaults.object(forKey: Key.settingsGlassOpacity) as? Double ?? 0.5
        hidesNames = defaults.bool(forKey: Key.hidesNames)
        showsHiddenAppsInSearch = defaults.bool(forKey: Key.showsHiddenAppsInSearch)
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
        showsInAppSwitcher = defaults.bool(forKey: Key.showsInAppSwitcher)
        gridColumns = defaults.object(forKey: Key.gridColumns) as? Int ?? GridSize.default.columns
        gridRows = defaults.object(forKey: Key.gridRows) as? Int ?? GridSize.default.rows
        sortField = defaults.string(forKey: Key.sortField).flatMap(SortField.init) ?? .custom
        sortDescending = defaults.bool(forKey: Key.sortDescending)
        sortsFolderContents = defaults.bool(forKey: Key.sortsFolderContents)
        folderPlacement = defaults.string(forKey: Key.folderPlacement).flatMap(FolderPlacement.init) ?? .mixed
    }

    private enum Key {
        static let legacyReopenBehavior = "reopenBehavior"
        static let returnToFirstPage = "returnToFirstPage"
        static let screenChoice = "screenChoice"
        static let optionEntersUninstallMode = "optionEntersUninstallMode"
        static let customSourcePaths = "customSourcePaths"
        static let browsingStyle = "browsingStyle"
        static let displayMode = "displayMode"
        static let hotCorner = "hotCorner"
        static let f4Launches = "f4Launches"
        static let pinchGesture = "pinchGesture"
        static let background = "background"
        static let dimming = "dimming"
        static let settingsWindowStyle = "settingsWindowStyle"
        static let appIconStyle = "appIconStyle"
        static let appIconTheme = "appIconTheme"
        static let settingsGlassOpacity = "settingsGlassOpacity"
        static let hidesNames = "hidesNames"
        static let showsHiddenAppsInSearch = "showsHiddenAppsInSearch"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let showsInAppSwitcher = "showsInAppSwitcher"
        static let gridColumns = "gridColumns"
        static let gridRows = "gridRows"
        static let sortField = "sortField"
        static let sortDescending = "sortDescending"
        static let sortsFolderContents = "sortsFolderContents"
        static let folderPlacement = "folderPlacement"
    }
}
