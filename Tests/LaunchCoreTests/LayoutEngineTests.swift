import XCTest
@testable import LaunchCore

final class LayoutEngineTests: XCTestCase {
    private let mail = layoutApp("Mail")
    private let notes = layoutApp("Notes")
    private let zoom = layoutApp("Zoom")
    private let gone = AppIdentity(bundleIdentifier: "com.example.gone", path: "")

    func testMissingAppIsHiddenButKeptInDocument() {
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.app(mail.identity), .app(gone), .app(notes.identity)]),
        ])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.app(mail), .app(notes)]])
        XCTAssertEqual(result.document, document)
        XCTAssertEqual(result.appendedApps, [])
    }

    func testBundleIdentifierMatchesMovedApp() {
        let saved = AppIdentity(bundleIdentifier: mail.identity.bundleIdentifier, path: "/Old/Mail.app")
        let document = LayoutDocument(pages: [LayoutPage(slots: [.app(saved)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.app(mail)]])
    }

    func testFolderShowsOnlyInstalledMembers() {
        let folder = LayoutFolder(id: "f", name: "效率", apps: [mail.identity, gone])
        let document = LayoutDocument(pages: [LayoutPage(slots: [.folder(folder)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.folder(ResolvedFolder(id: "f", name: "效率", apps: [mail]))]])
        XCTAssertEqual(result.appendedApps, [])
    }

    func testFolderWithoutInstalledMembersAndEmptiedPageAreHidden() {
        let folder = LayoutFolder(id: "f", name: "空", apps: [gone])
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.folder(folder)]),
            LayoutPage(slots: [.app(notes.identity)]),
        ])

        let result = LayoutEngine.reconcile(layout: document, catalog: [notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.app(notes)]])
    }

    func testIntentionalEmptySlotIsKept() {
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.app(mail.identity), .empty, .app(notes.identity)]),
        ])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail, notes], pageCapacity: 35)

        XCTAssertEqual(result.pages, [[.app(mail), .empty, .app(notes)]])
    }

    func testNewAppsAppendToLastPageThenOpenNewPage() {
        let document = LayoutDocument(pages: [
            LayoutPage(slots: [.app(mail.identity), .app(notes.identity)]),
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
            LayoutPage(slots: [.app(mail.identity), .app(notes.identity), .app(alpha.identity)]),
            LayoutPage(slots: [.app(beta.identity)]),
        ])
        XCTAssertEqual(result.pages, [[.app(mail), .app(notes), .app(alpha)], [.app(beta)]])
    }

    func testAppsInsideFoldersAreNotAppendedAgain() {
        let folder = LayoutFolder(id: "f", name: "效率", apps: [mail.identity])
        let document = LayoutDocument(pages: [LayoutPage(slots: [.folder(folder)])])

        let result = LayoutEngine.reconcile(layout: document, catalog: [mail], pageCapacity: 35)

        XCTAssertEqual(result.appendedApps, [])
    }

    func testDefaultDocumentPaginatesCatalogInOrder() {
        let document = LayoutEngine.defaultDocument(catalog: [mail, notes, zoom], pageCapacity: 2)

        XCTAssertEqual(document.pages, [
            LayoutPage(slots: [.app(mail.identity), .app(notes.identity)]),
            LayoutPage(slots: [.app(zoom.identity)]),
        ])
    }

    func testAppendingKeepsHiddenApps() {
        let document = LayoutDocument(pages: [], hiddenApps: [zoom.identity])

        let result = LayoutEngine.appending([mail.identity], to: document, pageCapacity: 35)

        XCTAssertEqual(result.hiddenApps, [zoom.identity])
    }
}
