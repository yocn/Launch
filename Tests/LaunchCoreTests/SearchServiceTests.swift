import XCTest
@testable import LaunchCore

final class SearchServiceTests: XCTestCase {
    func testSearchFindsNameCaseInsensitively() {
        let reader = catalogApp()

        XCTAssertEqual(
            SearchService.results(for: "READ", in: [reader], hidden: []),
            [reader]
        )
    }

    func testSearchExcludesHiddenApps() {
        let reader = catalogApp()

        XCTAssertTrue(
            SearchService.results(
                for: "read",
                in: [reader],
                hidden: [reader.identity]
            ).isEmpty
        )
    }

    func testFullPinyinInitialsAndMixedMatch() {
        let notes = app("备忘录", file: "Notes")
        let wechat = app("微信", file: "WeChat")

        for query in ["beiwanglu", "bwl", "beiwl", "BeiWang Lu"] {
            XCTAssertEqual(SearchService.results(for: query, in: [notes, wechat], hidden: []), [notes], query)
        }
        XCTAssertEqual(SearchService.results(for: "weix", in: [notes, wechat], hidden: []), [wechat])
    }

    func testPolyphonesFollowWordReading() {
        let music = app("音乐", file: "Music")
        let maps = app("地图", file: "Maps")

        for query in ["yinyue", "yy"] {
            XCTAssertEqual(SearchService.results(for: query, in: [music, maps], hidden: []), [music], query)
        }
        for query in ["ditu", "dt"] {
            XCTAssertEqual(SearchService.results(for: query, in: [music, maps], hidden: []), [maps], query)
        }
    }

    func testDoesNotMatchAcrossSyllableBoundaries() {
        let notes = app("备忘录", file: "Notes")

        XCTAssertEqual(SearchService.results(for: "angl", in: [notes], hidden: []), [])
        XCTAssertEqual(SearchService.results(for: "wanglu", in: [notes], hidden: []), [notes])
    }

    func testLatinAndHanSyllablesMix() {
        let safari = app("Safari浏览器", file: "Safari")

        for query in ["safarill", "safariliulan", "llq"] {
            XCTAssertEqual(SearchService.results(for: query, in: [safari], hidden: []), [safari], query)
        }
    }

    func testMatchesEnglishFileName() {
        let settings = app("系统设置", file: "System Settings", bundleID: "com.apple.systempreferences")

        XCTAssertEqual(SearchService.results(for: "settings", in: [settings], hidden: []), [settings])
    }

    func testRanksNamePrefixThenPinyinFromStartThenOthers() {
        let wxwork = app("WXWork", file: "WXWork")
        let wechat = app("微信", file: "WeChat")
        let rewx = app("Rewx", file: "Rewx")

        XCTAssertEqual(
            SearchService.results(for: "wx", in: [rewx, wechat, wxwork], hidden: []),
            [wxwork, wechat, rewx]
        )
    }

    func testPinyinFromStartRanksBeforeMiddleSyllables() {
        let cloudMusic = app("网易云音乐", file: "NeteaseMusic")
        let music = app("音乐", file: "Music")

        XCTAssertEqual(
            SearchService.results(for: "yy", in: [cloudMusic, music], hidden: []),
            [music, cloudMusic]
        )
    }

    func testIndexReusesPrecomputedSyllables() {
        let notes = app("备忘录", file: "Notes")
        let index = SearchIndex(apps: [notes])

        XCTAssertEqual(index.results(for: "bwl", hidden: []), [notes])
        XCTAssertEqual(index.results(for: "", hidden: []), [notes])
    }

    func testSyllablesSplitWordReadingByCharacter() {
        XCTAssertEqual(SearchName.syllables(of: "网易云音乐"), ["wang", "yi", "yun", "yin", "yue"])
        XCTAssertEqual(SearchName.syllables(of: "Safari浏览器"), ["safari", "liu", "lan", "qi"])
        XCTAssertEqual(SearchName.syllables(of: "重庆"), ["chong", "qing"])
    }

    private func catalogApp() -> LaunchItem {
        LaunchItem(
            identity: AppIdentity(
                bundleIdentifier: "com.example.Reader",
                path: "/Applications/Reader.app"
            ),
            displayName: "Reader"
        )
    }

    private func app(_ name: String, file: String, bundleID: String? = nil) -> LaunchItem {
        LaunchItem(
            identity: AppIdentity(
                bundleIdentifier: bundleID ?? "com.example.\(file.replacingOccurrences(of: " ", with: ""))",
                path: "/Applications/\(file).app"
            ),
            displayName: name
        )
    }
}
