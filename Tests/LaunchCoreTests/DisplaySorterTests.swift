import XCTest
@testable import LaunchCore

final class DisplaySorterTests: XCTestCase {
    private func app(_ name: String) -> CatalogApp {
        CatalogApp(identity: AppIdentity(bundleIdentifier: "com.example.\(name)", path: "/Applications/\(name).app"), displayName: name)
    }

    private func names(_ items: [ResolvedItem]) -> [String] {
        items.map { item in
            switch item {
            case .app(let app): app.displayName
            case .folder(let folder): "[\(folder.name)]"
            case .empty: "-"
            }
        }
    }

    private func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day) * 86400)
    }

    func testNameSortInterleavesPinyinAndLatin() {
        let apps = ["微信", "App Store", "备忘录", "地图", "iTerm", "计算器"].map(app)
        let pages: [[ResolvedItem]] = [Array(apps.prefix(3)).map(ResolvedItem.app), Array(apps.dropFirst(3)).map(ResolvedItem.app) + [.empty]]

        XCTAssertEqual(
            names(DisplaySorter.sorted(pages, by: DisplaySort(field: .name), dates: [:])),
            ["App Store", "备忘录", "地图", "iTerm", "计算器", "微信"]
        )
        XCTAssertEqual(
            names(DisplaySorter.sorted(pages, by: DisplaySort(field: .name, descending: true), dates: [:])),
            ["微信", "计算器", "iTerm", "地图", "备忘录", "App Store"]
        )
    }

    func testMissingDatesStayLastInBothDirections() {
        let (a, b, c) = (app("A"), app("B"), app("C"))
        let dates = [a.identity.stableKey: AppDates(lastUsed: date(2)), c.identity.stableKey: AppDates(lastUsed: date(1))]
        let pages: [[ResolvedItem]] = [[.app(a), .app(b), .app(c)]]

        XCTAssertEqual(names(DisplaySorter.sorted(pages, by: DisplaySort(field: .lastUsed), dates: dates)), ["C", "A", "B"])
        XCTAssertEqual(names(DisplaySorter.sorted(pages, by: DisplaySort(field: .lastUsed, descending: true), dates: dates)), ["A", "C", "B"])
    }

    func testFolderDateIsNewestMember() {
        let (a, b, x) = (app("A"), app("B"), app("X"))
        let folder = ResolvedFolder(id: "f", name: "效率", apps: [a, b])
        let dates = [
            a.identity.stableKey: AppDates(added: date(1)),
            b.identity.stableKey: AppDates(added: date(5)),
            x.identity.stableKey: AppDates(added: date(3)),
        ]
        let pages: [[ResolvedItem]] = [[.folder(folder), .app(x)]]

        XCTAssertEqual(names(DisplaySorter.sorted(pages, by: DisplaySort(field: .dateAdded), dates: dates)), ["X", "[效率]"])
    }

    func testFolderPlacement() {
        let (b, z) = (app("B"), app("Z"))
        let folder = ResolvedFolder(id: "f", name: "M", apps: [app("Q")])
        let pages: [[ResolvedItem]] = [[.app(z), .folder(folder), .app(b)]]

        XCTAssertEqual(names(DisplaySorter.sorted(pages, by: DisplaySort(field: .name, folderPlacement: .mixed), dates: [:])), ["B", "[M]", "Z"])
        XCTAssertEqual(names(DisplaySorter.sorted(pages, by: DisplaySort(field: .name, folderPlacement: .first), dates: [:])), ["[M]", "B", "Z"])
        XCTAssertEqual(
            names(DisplaySorter.sorted(pages, by: DisplaySort(field: .name, descending: true, folderPlacement: .last), dates: [:])),
            ["Z", "B", "[M]"]
        )
    }

    func testFolderContentsSortOnlyWhenAsked() {
        let folder = ResolvedFolder(id: "f", name: "F", apps: [app("C"), app("A"), app("B")])
        let pages: [[ResolvedItem]] = [[.folder(folder)]]

        guard case .folder(let kept) = DisplaySorter.sorted(pages, by: DisplaySort(field: .name), dates: [:]).first,
              case .folder(let sorted) = DisplaySorter.sorted(pages, by: DisplaySort(field: .name, sortsFolderContents: true), dates: [:]).first else {
            return XCTFail("expected folder")
        }
        XCTAssertEqual(kept.apps.map(\.displayName), ["C", "A", "B"])
        XCTAssertEqual(sorted.apps.map(\.displayName), ["A", "B", "C"])
        XCTAssertEqual(sorted.id, "f")
    }
}
