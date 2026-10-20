import Foundation
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reopenBehavior = defaults.string(forKey: Key.reopenBehavior).flatMap(ReopenBehavior.init) ?? .resume
        background = defaults.string(forKey: Key.background).flatMap(LauncherBackgroundStyle.init) ?? .glass
        dimming = defaults.object(forKey: Key.dimming) as? Double ?? Self.defaultDimming
        hidesNames = defaults.bool(forKey: Key.hidesNames)
        showsHiddenAppsInSearch = defaults.bool(forKey: Key.showsHiddenAppsInSearch)
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
    }

    private enum Key {
        static let reopenBehavior = "reopenBehavior"
        static let background = "background"
        static let dimming = "dimming"
        static let hidesNames = "hidesNames"
        static let showsHiddenAppsInSearch = "showsHiddenAppsInSearch"
        static let showsMenuBarIcon = "showsMenuBarIcon"
    }
}
