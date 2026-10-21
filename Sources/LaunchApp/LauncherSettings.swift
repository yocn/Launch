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

    var background: LauncherBackgroundStyle {
        didSet { defaults.set(background.rawValue, forKey: Key.background) }
    }

    var dimming: Double {
        didSet { defaults.set(dimming, forKey: Key.dimming) }
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
        background = defaults.string(forKey: Key.background).flatMap(LauncherBackgroundStyle.init) ?? .glass
        dimming = defaults.object(forKey: Key.dimming) as? Double ?? Self.defaultDimming
        hidesNames = defaults.bool(forKey: Key.hidesNames)
        showsHiddenAppsInSearch = defaults.bool(forKey: Key.showsHiddenAppsInSearch)
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
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
        static let background = "background"
        static let dimming = "dimming"
        static let hidesNames = "hidesNames"
        static let showsHiddenAppsInSearch = "showsHiddenAppsInSearch"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let gridColumns = "gridColumns"
        static let gridRows = "gridRows"
        static let sortField = "sortField"
        static let sortDescending = "sortDescending"
        static let sortsFolderContents = "sortsFolderContents"
        static let folderPlacement = "folderPlacement"
    }
}
