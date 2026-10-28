import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
final class BookmarkPickerModelTests: XCTestCase {
    private let baidu = URL(string: "https://www.baidu.com/")!
    private let github = URL(string: "https://github.com/")!
    private let docs = URL(string: "https://example.com/docs")!

    private var tree: [BookmarkNode] {
        [
            .folder("书签栏", [
                .link("百度", baidu),
                .folder("工作", [.link("文档", docs), .link("GitHub", github)]),
            ]),
        ]
    }

    private func makeController() async throws -> ExtraItemsController {
        let root = try makeTemporaryDirectory()
        let store = LayoutStore(fileURL: root.appendingPathComponent("layout.json"))
        try store.save(LayoutDocument())
        let layout = LayoutCoordinator(store: store, launchpad: NoEntryLaunchpad(), prompter: EntryPrompter(), log: makeTestLog())
        layout.start()
        await layout.catalogDidChange([])
        return ExtraItemsController(layout: layout, fetchIcon: { _ in nil })
    }

    private func makeModel(_ controller: ExtraItemsController, loader: @escaping BookmarkPickerModel.Loader) async -> BookmarkPickerModel {
        let model = BookmarkPickerModel(controller: controller, loader: loader)
        await finishLoading(model)
        return model
    }

    private func finishLoading(_ model: BookmarkPickerModel) async {
        for _ in 0 ..< 200 where model.isLoading {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(model.isLoading, "加载没有结束")
    }

    func testFoldersStartCollapsedAndExpandOneLevelAtATime() async throws {
        let tree = self.tree
        let model = await makeModel(try await makeController(), loader: { _ in tree })
        XCTAssertEqual(model.rows.map(\.node.name), ["书签栏"])

        model.toggle(model.rows[0].node)
        XCTAssertEqual(model.rows.map(\.node.name), ["书签栏", "百度", "工作"])
        XCTAssertEqual(model.rows.map(\.depth), [0, 1, 1])

        model.toggle(model.rows[2].node)
        XCTAssertEqual(model.rows.map(\.node.name), ["书签栏", "百度", "工作", "文档", "GitHub"])

        model.toggle(model.rows[0].node)
        XCTAssertEqual(model.rows.map(\.node.name), ["书签栏"])
    }

    func testSearchIgnoresCollapseAndClearingReturnsToFolders() async throws {
        let tree = self.tree
        let model = await makeModel(try await makeController(), loader: { _ in tree })

        model.query = "git"
        XCTAssertEqual(model.rows.map(\.node.name), ["GitHub"])
        model.query = "example.com"
        XCTAssertEqual(model.rows.map(\.node.name), ["文档"])
        model.query = ""
        XCTAssertEqual(model.rows.map(\.node.name), ["书签栏"])
    }

    func testAlreadyAddedFollowsTheCurrentSavedWebsites() async throws {
        let tree = self.tree
        let controller = try await makeController()
        let model = await makeModel(controller, loader: { _ in tree })
        XCTAssertTrue(model.existing.isEmpty)

        controller.addWebsites([("百度", baidu, nil)], toPage: nil)
        XCTAssertEqual(model.existing, [baidu])

        let id = try XCTUnwrap(controller.definitions.first?.identity)
        controller.deleteWebsite(id)
        XCTAssertTrue(model.existing.isEmpty)
    }

    func testSelectedLinksKeepBookmarkOrderAndCarryTheirIcons() async throws {
        let icon = Data([1, 2, 3])
        let withIcon = [BookmarkNode.folder("栏", [
            BookmarkNode(name: "百度", url: baidu, children: [], icon: icon),
            .link("GitHub", github),
        ])]
        let model = await makeModel(try await makeController(), loader: { _ in withIcon })
        let all = BrowserBookmarks.links(in: model.tree, matching: "")
        model.selected = [all[1].id, all[0].id]

        let links = model.links(for: model.selected)
        XCTAssertEqual(links.map(\.name), ["百度", "GitHub"])
        XCTAssertEqual(links[0].icon, icon)
        XCTAssertNil(links[1].icon)
    }

    func testSwitchingBrowserReloadsAndClearsSelectionAndExpansion() async throws {
        let tree = self.tree
        let safari = [BookmarkNode.folder("个人收藏", [.link("Apple", URL(string: "https://apple.com")!)])]
        let model = await makeModel(try await makeController(), loader: { $0 == .chrome ? tree : safari })
        model.toggle(model.rows[0].node)
        model.selected = [model.rows[1].node.id]

        model.browser = .safari
        await finishLoading(model)

        XCTAssertEqual(model.rows.map(\.node.name), ["个人收藏"])
        XCTAssertTrue(model.selected.isEmpty)
        XCTAssertTrue(model.expanded.isEmpty)
    }

    func testLoadFailureShowsTheReasonAndSafariPermissionHint() async throws {
        let model = await makeModel(try await makeController(), loader: { _ in throw BookmarkError.needsFullDiskAccess })
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.needsFullDiskAccess, "Chrome 不需要完全磁盘访问")

        model.browser = .safari
        await finishLoading(model)
        XCTAssertTrue(model.needsFullDiskAccess)
    }
}
