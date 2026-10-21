import XCTest
@testable import LaunchCore

final class LayoutEditorTests: XCTestCase {
    private let a = layoutApp("A")
    private let b = layoutApp("B")
    private let c = layoutApp("C")
    private let d = layoutApp("D")
    private let e = layoutApp("E")
    private let gone = AppIdentity(bundleIdentifier: "com.example.gone", path: "")

    private var catalog: [CatalogApp] { [a, b, c, d, e] }

    private func slot(_ app: CatalogApp) -> LayoutSlot { .app(app.identity) }
    private func key(_ app: CatalogApp) -> String { app.identity.stableKey }
    private func id(_ app: CatalogApp) -> LayoutItemID { .app(key(app)) }

    private func folder(_ id: String, _ apps: [CatalogApp], name: String = "效率") -> LayoutSlot {
        .folder(LayoutFolder(id: id, name: name, apps: apps.map(\.identity)))
    }

    private func document(_ pages: [[LayoutSlot]]) -> LayoutDocument {
        LayoutDocument(pages: pages.map { LayoutPage(slots: $0) })
    }

    private func apply(_ edit: LayoutEdit, _ pages: [[LayoutSlot]], capacity: Int = 35) -> [[LayoutSlot]] {
        LayoutEditor.apply(
            edit,
            to: document(pages),
            catalog: catalog,
            pageCapacity: capacity,
            makeFolderID: { "new" }
        ).pages.map(\.slots)
    }

    func testInsertBeforeItemOnSamePage() {
        let result = apply(.move(id(d), to: .insert(page: 0, before: id(b))), [[slot(a), slot(b), slot(c), slot(d)]])

        XCTAssertEqual(result, [[slot(a), slot(d), slot(b), slot(c)]])
    }

    func testInsertAtPageEnd() {
        let result = apply(.move(id(a), to: .insert(page: 0, before: nil)), [[slot(a), slot(b), slot(c)]])

        XCTAssertEqual(result, [[slot(b), slot(c), slot(a)]])
    }

    func testMoveAcrossPages() {
        let result = apply(.move(id(a), to: .insert(page: 1, before: id(c))), [[slot(a), slot(b)], [slot(c)]])

        XCTAssertEqual(result, [[slot(b)], [slot(a), slot(c)]])
    }

    func testOverflowCascadesThroughFullPages() {
        let result = apply(
            .move(id(e), to: .insert(page: 0, before: id(a))),
            [[slot(a), slot(b)], [slot(c), slot(d)], [slot(e)]],
            capacity: 2
        )

        XCTAssertEqual(result, [[slot(e), slot(a)], [slot(b), slot(c)], [slot(d)]])
    }

    func testOverflowFromLastPageCreatesPageAndEmptyPageIsRemoved() {
        let result = apply(
            .move(id(a), to: .insert(page: 1, before: id(b))),
            [[slot(a)], [slot(b), slot(c)]],
            capacity: 2
        )

        XCTAssertEqual(result, [[slot(a), slot(b)], [slot(c)]])
    }

    func testNewPageTarget() {
        let result = apply(.move(id(a), to: .newPage), [[slot(a), slot(b)]])

        XCTAssertEqual(result, [[slot(b)], [slot(a)]])
    }

    func testMissingAppsStayAndDoNotCountTowardCapacity() {
        let result = apply(
            .move(id(c), to: .insert(page: 0, before: id(b))),
            [[slot(a), .app(gone), slot(b)], [slot(c)]],
            capacity: 2
        )

        XCTAssertEqual(result, [[slot(a), .app(gone), slot(c)], [slot(b)]])
    }

    func testOversizedLegacyPageIsSplitBeforeEditing() {
        let result = apply(
            .move(id(a), to: .insert(page: 1, before: id(d))),
            [[slot(a), slot(b), slot(c), slot(d)]],
            capacity: 2
        )

        XCTAssertEqual(result, [[slot(b)], [slot(c), slot(a)], [slot(d)]])
    }

    func testNoChangeOrUnknownItemReturnsOriginalDocument() {
        let original = document([[slot(a), slot(b), slot(c)]])

        let unchanged = LayoutEditor.apply(
            .move(id(b), to: .insert(page: 0, before: id(c))),
            to: original,
            catalog: catalog,
            pageCapacity: 35
        )
        let unknown = LayoutEditor.apply(
            .move(.app("bundle:missing"), to: .newPage),
            to: original,
            catalog: catalog,
            pageCapacity: 35
        )

        XCTAssertEqual(unchanged, original)
        XCTAssertEqual(unknown, original)
    }

    func testResolvedItemLayoutID() {
        XCTAssertEqual(ResolvedItem.app(a).layoutID, id(a))
        XCTAssertEqual(ResolvedItem.folder(ResolvedFolder(id: "f", name: "x", apps: [a])).layoutID, .folder("f"))
        XCTAssertNil(ResolvedItem.empty.layoutID)
    }

    func testMergeAppOntoAppCreatesUntitledFolderAtTargetPosition() {
        let result = apply(.move(id(c), to: .merge(id(a))), [[slot(a), slot(b), slot(c)]])

        XCTAssertEqual(result, [[folder("new", [a, c], name: "未命名"), slot(b)]])
    }

    func testMergeAppIntoFolderAppendsMember() {
        let result = apply(.move(id(c), to: .merge(.folder("f"))), [[folder("f", [a, b]), slot(c)]])

        XCTAssertEqual(result, [[folder("f", [a, b, c])]])
    }

    func testFolderCannotMergeIntoAnything() {
        let pages = [[folder("f", [a, b]), slot(c)]]

        XCTAssertEqual(apply(.move(.folder("f"), to: .merge(id(c))), pages), pages)
    }

    func testReorderInsideFolder() {
        let pages = [[folder("f", [a, b, c])]]

        XCTAssertEqual(apply(.reorderInFolder(folder: "f", app: key(c), before: key(a)), pages), [[folder("f", [c, a, b])]])
        XCTAssertEqual(apply(.reorderInFolder(folder: "f", app: key(a), before: nil), pages), [[folder("f", [b, c, a])]])
    }

    func testMoveOutOfFolderToGrid() {
        let result = apply(
            .moveOutOfFolder(app: key(b), folder: "f", to: .insert(page: 0, before: id(d))),
            [[folder("f", [a, b, c]), slot(d)]]
        )

        XCTAssertEqual(result, [[folder("f", [a, c]), slot(b), slot(d)]])
    }

    func testFolderDissolvesWhenOneMemberLeft() {
        let result = apply(
            .moveOutOfFolder(app: key(a), folder: "f", to: .insert(page: 0, before: nil)),
            [[folder("f", [a, b]), slot(c)]]
        )

        XCTAssertEqual(result, [[slot(b), slot(c), slot(a)]])
    }

    func testDroppingBackOnSourceFolderMovesMemberToEnd() {
        let result = apply(
            .moveOutOfFolder(app: key(a), folder: "f", to: .merge(.folder("f"))),
            [[folder("f", [a, b, c])]]
        )

        XCTAssertEqual(result, [[folder("f", [b, c, a])]])
    }

    func testInsertBeforeDissolvedFolderUsesRemainingApp() {
        let result = apply(
            .moveOutOfFolder(app: key(a), folder: "f", to: .insert(page: 0, before: .folder("f"))),
            [[slot(c), folder("f", [a, b])]]
        )

        XCTAssertEqual(result, [[slot(c), slot(a), slot(b)]])
    }

    func testMissingMemberCountsWhenDissolving() {
        let result = apply(
            .moveOutOfFolder(app: key(a), folder: "f", to: .insert(page: 0, before: nil)),
            [[.folder(LayoutFolder(id: "f", name: "效率", apps: [a.identity, gone])), slot(b)]]
        )

        XCTAssertEqual(result, [[.app(gone), slot(b), slot(a)]])
    }

    func testRenameFolderTrimsAndDefaults() {
        let pages = [[folder("f", [a, b])]]

        XCTAssertEqual(apply(.renameFolder(folder: "f", name: "  工具 "), pages), [[folder("f", [a, b], name: "工具")]])
        XCTAssertEqual(apply(.renameFolder(folder: "f", name: "  "), pages), [[folder("f", [a, b], name: "未命名")]])
    }

    func testGroupInsertKeepsGroupOrderBeforeAnchor() {
        let result = apply(
            .moveGroup([id(a), id(e)], to: .insert(page: 0, before: id(c))),
            [[slot(a), slot(b), slot(c), slot(d), slot(e)]]
        )

        XCTAssertEqual(result, [[slot(b), slot(a), slot(e), slot(c), slot(d)]])
    }

    func testGroupInsertAtEndOfAnotherPage() {
        let result = apply(
            .moveGroup([id(a), id(c)], to: .insert(page: 1, before: nil)),
            [[slot(a), slot(b)], [slot(c), slot(d)]]
        )

        XCTAssertEqual(result, [[slot(b)], [slot(d), slot(a), slot(c)]])
    }

    func testGroupOverflowMovesInBulk() {
        let result = apply(
            .moveGroup([id(d), id(e)], to: .insert(page: 0, before: id(a))),
            [[slot(a), slot(b)], [slot(c), slot(d)], [slot(e)]],
            capacity: 2
        )

        XCTAssertEqual(result, [[slot(d), slot(e)], [slot(a), slot(b)], [slot(c)]])
    }

    func testGroupToNewPageOverflowsIntoFollowingPage() {
        let result = apply(
            .moveGroup([id(a), id(b), id(c)], to: .newPage),
            [[slot(a), slot(b)], [slot(c), slot(d)]],
            capacity: 2
        )

        XCTAssertEqual(result, [[slot(d)], [slot(a), slot(b)], [slot(c)]])
    }

    func testGroupInsertAnchoredOnGroupMemberIsIgnored() {
        let pages = [[slot(a), slot(b), slot(c)]]

        XCTAssertEqual(apply(.moveGroup([id(a), id(b)], to: .insert(page: 0, before: id(b))), pages), pages)
    }

    func testGroupMergeIntoAppFlattensSelectedFolders() {
        let result = apply(
            .moveGroup([.folder("f"), id(e)], to: .merge(id(a))),
            [[slot(a), folder("f", [b, c]), slot(d), slot(e)]]
        )

        XCTAssertEqual(result, [[folder("new", [a, b, c, e], name: "未命名"), slot(d)]])
    }

    func testGroupMergeIntoSelectedFolderAppendsOthers() {
        let result = apply(
            .moveGroup([.folder("f"), id(b), .folder("g")], to: .merge(.folder("f"))),
            [[folder("f", [a]), slot(b), folder("g", [c, d])]]
        )

        XCTAssertEqual(result, [[folder("f", [a, b, c, d])]])
    }

    func testGroupMergeKeepsMissingMembersOfFlattenedFolder() {
        let g = LayoutSlot.folder(LayoutFolder(id: "g", name: "效率", apps: [c.identity, gone]))

        let result = apply(.moveGroup([.folder("g")], to: .merge(id(a))), [[slot(a), g]])

        XCTAssertEqual(result, [[.folder(LayoutFolder(id: "new", name: "未命名", apps: [a.identity, c.identity, gone]))]])
    }

    func testMergeIntoNewFolderTakesFirstItemPosition() {
        let result = apply(
            .mergeIntoNewFolder([id(b), .folder("f")]),
            [[slot(a), slot(b), slot(c)], [slot(d), folder("f", [e])]]
        )

        XCTAssertEqual(result, [[slot(a), folder("new", [b, e], name: "未命名"), slot(c)], [slot(d)]])
    }

    func testMergeIntoNewFolderNeedsTwoItems() {
        let pages = [[slot(a), slot(b)]]

        XCTAssertEqual(apply(.mergeIntoNewFolder([id(a)]), pages), pages)
    }

    func testEditKeepsHiddenApps() {
        let document = LayoutDocument(pages: [LayoutPage(slots: [slot(a), slot(b)])], hiddenApps: [gone])

        let result = LayoutEditor.apply(
            .move(id(b), to: .insert(page: 0, before: id(a))),
            to: document,
            catalog: catalog,
            pageCapacity: 35
        )

        XCTAssertEqual(result.hiddenApps, [gone])
    }

    private func applyDocument(
        _ edit: LayoutEdit,
        _ pages: [[LayoutSlot]],
        hidden: [AppIdentity] = [],
        capacity: Int = 35
    ) -> LayoutDocument {
        LayoutEditor.apply(
            edit,
            to: LayoutDocument(pages: pages.map { LayoutPage(slots: $0) }, hiddenApps: hidden),
            catalog: catalog,
            pageCapacity: capacity,
            makeFolderID: { "new" }
        )
    }

    func testHideAppAndFolderMembersKeepsPositions() {
        let pages = [[slot(a), folder("f", [b, c]), slot(d)]]

        let result = applyDocument(.hide([id(a), .folder("f")]), pages)

        XCTAssertEqual(result.pages.map(\.slots), pages)
        XCTAssertEqual(result.hiddenApps, [a.identity, b.identity, c.identity])
    }

    func testHideFolderMemberByKey() {
        let result = applyDocument(.hide([id(b)]), [[folder("f", [b, c])]])

        XCTAssertEqual(result.hiddenApps, [b.identity])
    }

    func testHidingHiddenAppChangesNothing() {
        let document = LayoutDocument(pages: [LayoutPage(slots: [slot(a), slot(b)])], hiddenApps: [a.identity])

        XCTAssertEqual(
            LayoutEditor.apply(.hide([id(a)]), to: document, catalog: catalog, pageCapacity: 35),
            document
        )
    }

    func testHiddenAppsTakeNoCapacityAndCannotAnchor() {
        let result = applyDocument(
            .move(id(d), to: .insert(page: 0, before: id(b))),
            [[slot(a), slot(b), slot(c)], [slot(d)]],
            hidden: [b.identity],
            capacity: 3
        )

        XCTAssertEqual(result.pages.map(\.slots), [[slot(a), slot(b), slot(c), slot(d)]])
    }

    func testUnhideRestoresOriginalPosition() {
        let pages = [[slot(a), slot(b), slot(c)]]

        let result = applyDocument(.unhide([b.identity]), pages, hidden: [b.identity, c.identity])

        XCTAssertEqual(result.pages.map(\.slots), pages)
        XCTAssertEqual(result.hiddenApps, [c.identity])
    }

    func testUnhideMatchesMovedInstall() {
        let moved = AppIdentity(bundleIdentifier: b.identity.bundleIdentifier, path: "/Old/B.app")

        let result = applyDocument(.unhide([b.identity]), [[slot(a), slot(b)]], hidden: [moved])

        XCTAssertEqual(result.hiddenApps, [])
    }

    func testUngroupAppendsMembersToPageEndAndCascades() {
        let result = applyDocument(
            .ungroupFolder("f"),
            [[folder("f", [b, c]), slot(a), .app(gone)], [slot(d)]],
            capacity: 2
        )

        XCTAssertEqual(result.pages.map(\.slots), [[slot(a), .app(gone), slot(b)], [slot(c), slot(d)]])
    }

    func testArrangeFillsAllPagesKeepingHiddenNeighbors() {
        let result = applyDocument(
            .arrange(LayoutArrangement(pages: [0, 1, 2], fillsGaps: true, ungroupsFolders: false)),
            [[slot(a), .app(gone)], [slot(b)], [slot(c), slot(d)]],
            capacity: 2
        )

        XCTAssertEqual(result.pages.map(\.slots), [[slot(a), .app(gone), slot(b)], [slot(c), slot(d)]])
    }

    func testArrangeChosenPagesLeavesOtherPagesInPlace() {
        let result = applyDocument(
            .arrange(LayoutArrangement(pages: [0, 2], fillsGaps: true, ungroupsFolders: false)),
            [[slot(a)], [slot(b)], [slot(c)], [slot(d), slot(e)]],
            capacity: 2
        )

        XCTAssertEqual(result.pages.map(\.slots), [[slot(a), slot(c)], [slot(b)], [slot(d), slot(e)]])
    }

    func testArrangeUngroupOverflowBecomesFollowingPage() {
        let result = applyDocument(
            .arrange(LayoutArrangement(pages: [0], fillsGaps: false, ungroupsFolders: true)),
            [[folder("f", [b, c]), slot(a)], [slot(d)]],
            capacity: 2
        )

        XCTAssertEqual(result.pages.map(\.slots), [[slot(a), slot(b)], [slot(c)], [slot(d)]])
    }

    func testArrangeUngroupsBeforeFilling() {
        let result = applyDocument(
            .arrange(LayoutArrangement(pages: [0, 1], fillsGaps: true, ungroupsFolders: true)),
            [[folder("f", [b, c]), slot(a)], [slot(d)], [LayoutSlot.folder(LayoutFolder(id: "g", name: "效率", apps: [e.identity, gone]))]],
            capacity: 3
        )

        XCTAssertEqual(result.pages.map(\.slots), [[slot(a), slot(b), slot(c)], [slot(d)], [LayoutSlot.folder(LayoutFolder(id: "g", name: "效率", apps: [e.identity, gone]))]])
    }

    func testArrangeWithoutChangeKeepsDocument() {
        let pages = [[slot(a), slot(b)], [slot(c)]]
        let original = LayoutDocument(pages: pages.map { LayoutPage(slots: $0) })

        XCTAssertEqual(applyDocument(.arrange(LayoutArrangement(pages: [0, 1], fillsGaps: true, ungroupsFolders: false)), pages, capacity: 2), original)
        XCTAssertEqual(applyDocument(.arrange(LayoutArrangement(pages: [5], fillsGaps: true, ungroupsFolders: true)), pages, capacity: 2), original)
    }
}
