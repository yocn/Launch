import XCTest
@testable import LaunchCore

final class LaunchpadImporterTests: XCTestCase {
    private let calendar = layoutApp("Calendar")
    private let chess = layoutApp("Chess")
    private let mail = layoutApp("Mail")
    private let notes = layoutApp("Notes")
    private let zoom = layoutApp("Zoom")

    private func launchpad(_ app: LaunchItem) -> LaunchpadApp {
        LaunchpadApp(bundleIdentifier: app.application!.identity.bundleIdentifier!, title: app.displayName)
    }

    func testImportMapsFoldersMissingAppsAndNewApps() {
        let gone = LaunchpadApp(bundleIdentifier: "com.example.gone", title: "Gone")
        let snapshot = LaunchpadSnapshot(pages: [
            [],
            [
                .folder(id: 12, name: "效率", apps: [launchpad(mail), launchpad(calendar)]),
                .app(launchpad(notes)),
                .app(gone),
            ],
            [.app(launchpad(chess))],
        ])

        let result = LaunchpadImporter.makeImport(
            from: snapshot,
            catalog: [calendar, chess, mail, notes, zoom].compactMap(\.application),
            pageCapacity: 35
        )

        XCTAssertEqual(result.document.pages, [
            LayoutPage(slots: [
                .folder(LayoutFolder(id: "launchpad-12", name: "效率", items: [mail.identity, calendar.identity])),
                .item(notes.identity),
                .item(.application(AppIdentity(bundleIdentifier: "com.example.gone", path: ""))),
            ]),
            LayoutPage(slots: [.item(chess.identity), .item(zoom.identity)]),
        ])
        XCTAssertEqual(result.summary, LaunchpadImportSummary(
            pageCount: 2,
            folderCount: 1,
            appCount: 5,
            installedCount: 4,
            newAppCount: 1
        ))
        XCTAssertEqual(result.summary.missingCount, 1)
    }

    func testDuplicateBundleIdentifierKeepsFirstOccurrence() {
        let snapshot = LaunchpadSnapshot(pages: [[
            .folder(id: 1, name: "A", apps: [launchpad(notes)]),
            .app(launchpad(notes)),
            .folder(id: 2, name: "B", apps: [launchpad(notes)]),
        ]])

        let result = LaunchpadImporter.makeImport(from: snapshot, catalog: [notes].compactMap(\.application), pageCapacity: 35)

        XCTAssertEqual(result.document.pages, [
            LayoutPage(slots: [.folder(LayoutFolder(id: "launchpad-1", name: "A", items: [notes.identity]))]),
        ])
        XCTAssertEqual(result.summary.folderCount, 1)
        XCTAssertEqual(result.summary.appCount, 1)
    }

    func testOversizedPageIsSplit() {
        let snapshot = LaunchpadSnapshot(pages: [[
            .app(launchpad(calendar)), .app(launchpad(chess)), .app(launchpad(mail)),
        ]])

        let result = LaunchpadImporter.makeImport(
            from: snapshot,
            catalog: [calendar, chess, mail].compactMap(\.application),
            pageCapacity: 2
        )

        XCTAssertEqual(result.document.pages, [
            LayoutPage(slots: [.item(calendar.identity), .item(chess.identity)]),
            LayoutPage(slots: [.item(mail.identity)]),
        ])
        XCTAssertEqual(result.summary.pageCount, 1)
    }
}
