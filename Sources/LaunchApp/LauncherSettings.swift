import Foundation
import LaunchCore
import Observation

enum ReopenBehavior: String, CaseIterable {
    case resume
    case firstPage
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

    var reopenBehavior: ReopenBehavior {
        didSet { defaults.set(reopenBehavior.rawValue, forKey: Key.reopenBehavior) }
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
        reopenBehavior = defaults.string(forKey: Key.reopenBehavior).flatMap(ReopenBehavior.init) ?? .resume
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
        static let reopenBehavior = "reopenBehavior"
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
