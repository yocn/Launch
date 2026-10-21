public enum AppCategory {
    private static let names: [String: String] = [
        "business": "商务",
        "developer-tools": "开发者工具",
        "education": "教育",
        "entertainment": "娱乐",
        "finance": "财务",
        "games": "游戏",
        "graphics-design": "图形与设计",
        "healthcare-fitness": "健康与健身",
        "lifestyle": "生活",
        "medical": "医疗",
        "music": "音乐",
        "news": "新闻",
        "photography": "摄影",
        "productivity": "效率",
        "reference": "参考",
        "social-networking": "社交",
        "sports": "体育",
        "travel": "旅行",
        "utilities": "实用工具",
        "video": "视频",
        "weather": "天气",
        "books": "图书",
        "food-and-drink": "美食佳饮",
        "shopping": "购物",
        "navigation": "导航",
        "magazines-and-newspapers": "报刊杂志",
        "kids": "儿童",
    ]

    // 系统自带应用多数没有类别标记
    private static let appleApps: [String: String] = [
        "com.apple.weather": "weather",
        "com.apple.Home": "lifestyle",
        "com.apple.stocks": "finance",
        "com.apple.podcasts": "entertainment",
        "com.apple.mobilephone": "social-networking",
        "com.apple.DVDPlayer": "video",
        "com.apple.calculator": "utilities",
        "com.apple.clock": "utilities",
        "com.apple.findmy": "utilities",
        "com.apple.Passwords": "utilities",
        "com.apple.ScreenContinuity": "utilities",
        "com.apple.DiskUtility": "utilities",
        "com.apple.Magnifier": "utilities",
        "com.apple.AboutThisMacLauncher": "utilities",
        "com.apple.DeskCam": "utilities",
        "com.apple.DirectoryUtility": "utilities",
        "com.apple.ExpansionSlotUtility": "utilities",
        "com.apple.appleseed.FeedbackAssistant": "utilities",
        "com.apple.FolderActionsSetup": "utilities",
        "com.apple.Ticket-Viewer": "utilities",
        "com.apple.wifi.diagnostics": "utilities",
    ]

    public static func name(for category: String?, bundleIdentifier: String?) -> String? {
        let prefix = "public.app-category."
        let declared = category.flatMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
        guard let key = declared ?? bundleIdentifier.flatMap({ appleApps[$0] }) else {
            return nil
        }
        // 各类游戏（puzzle-games 等）都归「游戏」
        return key.hasSuffix("-games") ? names["games"] : names[key]
    }
}
