import XCTest
@testable import LaunchCore

final class LayoutEngineTests: XCTestCase {
    private let mail = layoutApp("Mail")
    private let notes = layoutApp("Notes")
    private let zoom = layoutApp("Zoom")
    private let gone = ItemIdentity(bundleIdentifier: "com.example.gone", path: "")

    func testMissingAppIsHiddenButKeptInDocument() {
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.item(mail.identity), .item(gone), .item(notes.identity)]),
        ])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.item(mail), .item(notes)]])
        XCTAssertEqual(result.document, document)
        XCTAssertEqual(result.appendedApps, [])
    }

    func testBundleIdentifierMatchesMovedApp() {
        let saved = ItemIdentity(bundleIdentifier: mail.identity.applicationIdentity?.bundleIdentifier, path: "/Old/Mail.app")
        let document = LayoutDocument(pages: [LayoutPage(slots: [.item(saved)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.item(mail)]])
    }

    func testDuplicateCopiesResolveToTheFirstPathRegardlessOfScanOrder() {
        let system = LaunchItem(identity: AppIdentity(bundleIdentifier: "com.example.tool", path: "/Applications/Tool.app"), displayName: "Tool")
        let user = LaunchItem(identity: AppIdentity(bundleIdentifier: "com.example.tool", path: "/Users/me/Applications/Tool.app"), displayName: "Tool")
        let document = LayoutDocument(pages: [LayoutPage(slots: [.item(system.identity)])])

        for catalog in [[system, user], [user, system]] {
            let result = LayoutEngine.reconcile(layout: document, catalog: catalog, pageCapacity: 35)
            XCTAssertEqual(result.pages, [[.item(system)]])
        }
    }

    func testNewAppsFillEarlierPagesBeforeOpeningANewPage() {
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.item(mail.identity), .item(notes.identity), .item(zoom.identity)]),
            LayoutPage(slots: [.item(layoutApp("Page2").identity)]),
            LayoutPage(slots: [.item(layoutApp("A").identity), .item(layoutApp("B").identity), .item(layoutApp("C").identity)]),
        ])
        let alpha = layoutApp("Alpha")
        let beta = layoutApp("Beta")
        let gamma = layoutApp("Gamma")
        let catalog = [mail, notes, zoom, layoutApp("Page2"), layoutApp("A"), layoutApp("B"), layoutApp("C"), alpha, beta, gamma]

        let result = LayoutEngine.reconcile(layout: document, catalog: catalog, pageCapacity: 3)

        XCTAssertEqual(result.document.pages[1].slots, [.item(layoutApp("Page2").identity), .item(alpha.identity), .item(beta.identity)])
        XCTAssertEqual(result.document.pages[3].slots, [.item(gamma.identity)])
        XCTAssertEqual(result.document.pages.count, 4)
    }

    func testFolderShowsOnlyInstalledMembers() {
        let folder = LayoutFolder(id: "f", name: "效率", items: [mail.identity, gone])
        let document = LayoutDocument(pages: [LayoutPage(slots: [.folder(folder)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.folder(ResolvedFolder(id: "f", name: "效率", items: [mail]))]])
        XCTAssertEqual(result.appendedApps, [])
    }

    func testFolderWithoutInstalledMembersAndEmptiedPageAreHidden() {
        let folder = LayoutFolder(id: "f", name: "空", items: [gone])
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.folder(folder)]),
            LayoutPage(slots: [.item(notes.identity)]),
        ])

        let result = LayoutEngine.reconcile(layout: document, catalog: [notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.item(notes)]])
    }

    func testIntentionalEmptySlotIsKept() {
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.item(mail.identity), .empty, .item(notes.identity)]),
        ])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.item(mail), .empty, .item(notes)]])
    }

    func testNewAppsAppendToLastPageThenOpenNewPage() {
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.item(mail.identity), .item(notes.identity)]),
        ])
        let alpha = layoutApp("Alpha")
        let beta = layoutApp("Beta")

        let result = LayoutEngine.reconcile(
            layout: document,
            catalog: [alpha, beta, mail, notes],
            pageCapacity: 3
        )

        XCTAssertEqual(result.appendedApps, [alpha, beta])
        XCTAssertEqual(result.document.pages, [
            LayoutPage(slots: [.item(mail.identity), .item(notes.identity), .item(alpha.identity)]),
            LayoutPage(slots: [.item(beta.identity)]),
        ])
        XCTAssertEqual(result.pages, [[.item(mail), .item(notes), .item(alpha)], [.item(beta)]])
    }

    func testAppsInsideFoldersAreNotAppendedAgain() {
        let folder = LayoutFolder(id: "f", name: "效率", items: [mail.identity])
        let document = LayoutDocument(pages: [LayoutPage(slots: [.folder(folder)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail], pageCapacity: 35)

        XCTAssertEqual(result.appendedApps, [])
    }

    func testDefaultDocumentPaginatesCatalogInOrder() {
        let document = LayoutEngine.defaultDocument(catalog: [mail, notes, zoom], pageCapacity: 2)

        XCTAssertEqual(document.pages, [
            LayoutPage(slots: [.item(mail.identity), .item(notes.identity)]),
            LayoutPage(slots: [.item(zoom.identity)]),
        ])
    }

    func testAppendingKeepsHiddenApps() {
        let document = LayoutDocument(pages: [], hiddenItems: [zoom.identity])

        let result = LayoutEngine.appending([mail.identity], to: document, pageCapacity: 35)

        XCTAssertEqual(result.hiddenItems, [zoom.identity])
    }

    func testHiddenAppsStayPlacedButInvisible() {
        let folder = LayoutFolder(id: "f", name: "效率", items: [notes.identity, zoom.identity])
        let document = LayoutDocument(
            pages: [LayoutPage(slots: [.item(mail.identity), .folder(folder)])],
            hiddenItems: [zoom.identity, mail.identity]
        )

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes, zoom], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.folder(ResolvedFolder(id: "f", name: "效率", items: [notes]))]])
        XCTAssertEqual(result.appendedApps, [])
        XCTAssertEqual(result.hiddenItems, [mail, zoom])
    }

    func testFolderWithOnlyHiddenMembersDisappears() {
        let folder = LayoutFolder(id: "f", name: "效率", items: [notes.identity])
        let document = LayoutDocument(
            pages: [LayoutPage(slots: [.item(mail.identity), .folder(folder)])],
            hiddenItems: [notes.identity]
        )

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.item(mail)]])
    }

    func testHiddenAppMatchesMovedInstall() {
        let saved = ItemIdentity(bundleIdentifier: mail.identity.applicationIdentity?.bundleIdentifier, path: "/Old/Mail.app")
        let document = LayoutDocument(
            pages: [LayoutPage(slots: [.item(mail.identity), .item(notes.identity)])],
            hiddenItems: [saved]
        )

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.item(notes)]])
        XCTAssertEqual(result.hiddenItems, [mail])
    }
}
