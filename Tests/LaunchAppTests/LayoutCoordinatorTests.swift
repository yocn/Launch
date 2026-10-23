import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
private final class FakePrompter: LayoutPrompting {
    var answer = true
    private(set) var firstImportSummaries: [LaunchpadImportSummary] = []
    private(set) var reimportSummaries: [LaunchpadImportSummary] = []
    private(set) var backupSummaries: [LaunchpadImportSummary] = []
    private(set) var restoreRequests = 0
    private(set) var errors: [String] = []

    func confirmFirstImport(_ summary: LaunchpadImportSummary) -> Bool {
        firstImportSummaries.append(summary)
        return answer
    }

    func confirmReimport(_ summary: LaunchpadImportSummary) -> Bool {
        reimportSummaries.append(summary)
        return answer
    }

    func confirmBackupImport(_ summary: LaunchpadImportSummary) -> Bool {
        backupSummaries.append(summary)
        return answer
    }

    func confirmRestore() -> Bool {
        restoreRequests += 1
        return answer
    }

    func showError(_ message: String) {
        errors.append(message)
    }
}

private struct FakeLaunchpad: LaunchpadSource {
    var isAvailable = true
    var snapshot = LaunchpadSnapshot(pages: [])
    var failure: LaunchpadReadError?

    func readSnapshot() async throws -> LaunchpadSnapshot {
        if let failure {
            throw failure
        }
        return snapshot
    }
}

@MainActor
private final class PublishedPages {
    var values: [[[ResolvedItem]]] = []
    var last: [[ResolvedItem]]? { values.last }
}

final class LayoutCoordinatorTests: XCTestCase {
    private let apps = makeLaunchItems(count: 3)

    private func launchpadApp(_ app: LaunchItem) -> LaunchpadApp {
        LaunchpadApp(bundleIdentifier: app.application!.identity.bundleIdentifier!, title: app.displayName)
    }

    @MainActor
    func testFirstLaunchImportsLaunchpadLayoutAfterConfirmation() async throws {
        let store = try temporaryStore()
        let prompter = FakePrompter()
        let snapshot = LaunchpadSnapshot(pages: [[
            .folder(id: 7, name: "效率", apps: [launchpadApp(apps[0])]),
            .app(launchpadApp(apps[1])),
        ]])
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad(snapshot: snapshot))

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertEqual(prompter.firstImportSummaries.count, 1)
        XCTAssertEqual(published.last, [[
            makeFolder(id: "launchpad-7", name: "效率", apps: [apps[0]]),
            .item(apps[1]),
            .item(apps[2]),
        ]])
        XCTAssertEqual(try store.load()?.pages.first?.slots.count, 3)
    }

    @MainActor
    func testDecliningFirstImportSavesDefaultLayout() async throws {
        let store = try temporaryStore()
        let prompter = FakePrompter()
        prompter.answer = false
        let snapshot = LaunchpadSnapshot(pages: [[.folder(id: 7, name: "效率", apps: [launchpadApp(apps[0])])]])
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad(snapshot: snapshot))

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertEqual(published.last, [apps.map(ResolvedItem.item)])
        XCTAssertEqual(try store.load(), LayoutEngine.defaultDocument(catalog: apps, pageCapacity: 35))
    }

    @MainActor
    func testFirstLaunchWithoutLaunchpadUsesDefaultSilently() async throws {
        let store = try temporaryStore()
        let prompter = FakePrompter()
        let (coordinator, _) = makeCoordinator(store, prompter, FakeLaunchpad(isAvailable: false))

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertTrue(prompter.firstImportSummaries.isEmpty)
        XCTAssertNotNil(try store.load())
    }

    @MainActor
    func testReadFailureDuringFirstLaunchFallsBackToDefault() async throws {
        let store = try temporaryStore()
        let prompter = FakePrompter()
        let (coordinator, _) = makeCoordinator(store, prompter, FakeLaunchpad(failure: .missingRoot))

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertEqual(prompter.errors.count, 1)
        XCTAssertEqual(try store.load(), LayoutEngine.defaultDocument(catalog: apps, pageCapacity: 35))
    }

    @MainActor
    func testExistingLayoutAppendsNewAppsAndSaves() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: [.item(apps[2].identity)])]))
        let prompter = FakePrompter()
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad())

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertTrue(prompter.firstImportSummaries.isEmpty)
        XCTAssertEqual(published.last, [[.item(apps[2]), .item(apps[0]), .item(apps[1])]])
        XCTAssertEqual(try store.load()?.pages.first?.slots.count, 3)
    }

    @MainActor
    func testCorruptLayoutIsLeftUntouched() async throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: store.fileURL)
        let prompter = FakePrompter()
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad())

        coordinator.start()
        await coordinator.catalogDidChange(apps)

        XCTAssertEqual(prompter.errors.count, 1)
        XCTAssertTrue(prompter.firstImportSummaries.isEmpty)
        XCTAssertEqual(published.last, [apps.map(ResolvedItem.item)])
        XCTAssertEqual(try Data(contentsOf: store.fileURL), Data("not json".utf8))
    }

    @MainActor
    func testReimportBacksUpAndRestoreSwapsBack() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: [.item(apps[2].identity)])]))
        let prompter = FakePrompter()
        let snapshot = LaunchpadSnapshot(pages: [[.app(launchpadApp(apps[0]))]])
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad(snapshot: snapshot))
        coordinator.start()
        await coordinator.catalogDidChange(apps)

        await coordinator.importFromLaunchpad()

        XCTAssertEqual(prompter.reimportSummaries.count, 1)
        XCTAssertTrue(coordinator.canRestore)
        XCTAssertEqual(published.last, [[.item(apps[0]), .item(apps[1]), .item(apps[2])]])

        coordinator.restoreBackup()

        XCTAssertEqual(prompter.restoreRequests, 1)
        XCTAssertEqual(published.last, [[.item(apps[2]), .item(apps[0]), .item(apps[1])]])
    }

    @MainActor
    func testApplyEditSavesPublishesAndUndoRestores() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: apps.map { .item($0.identity) })]))
        let (coordinator, published) = makeCoordinator(store, FakePrompter(), FakeLaunchpad())
        coordinator.start()
        await coordinator.catalogDidChange(apps)

        coordinator.apply(.move(
            .item(apps[2].identity.stableKey),
            to: .insert(page: 0, before: .item(apps[0].identity.stableKey))
        ))

        XCTAssertEqual(published.last, [[.item(apps[2]), .item(apps[0]), .item(apps[1])]])
        XCTAssertEqual(try store.load()?.pages.first?.slots, [apps[2], apps[0], apps[1]].map { .item($0.identity) })

        coordinator.undo()

        XCTAssertEqual(published.last, [apps.map(ResolvedItem.item)])
        XCTAssertEqual(try store.load()?.pages.first?.slots, apps.map { .item($0.identity) })
    }

    @MainActor
    func testUndoKeepsAtMostTwentySteps() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: apps.map { .item($0.identity) })]))
        let (coordinator, published) = makeCoordinator(store, FakePrompter(), FakeLaunchpad())
        coordinator.start()
        await coordinator.catalogDidChange(apps)
        var states = [published.last]

        for _ in 0 ..< 25 {
            guard case .item(let first)? = published.last?.first?.first else {
                return XCTFail("expected app")
            }
            coordinator.apply(.move(.item(first.identity.stableKey), to: .insert(page: 0, before: nil)))
            states.append(published.last)
        }
        for _ in 0 ..< 25 {
            coordinator.undo()
        }

        XCTAssertEqual(published.last, states[5])
    }

    @MainActor
    func testEditsAreIgnoredWhenLayoutIsReadOnly() async throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: store.fileURL)
        let (coordinator, published) = makeCoordinator(store, FakePrompter(), FakeLaunchpad())
        coordinator.start()
        await coordinator.catalogDidChange(apps)
        let count = published.values.count

        coordinator.apply(.move(.item(apps[0].identity.stableKey), to: .insert(page: 0, before: nil)))

        XCTAssertFalse(coordinator.isEditable)
        XCTAssertEqual(published.values.count, count)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), Data("not json".utf8))
    }

    @MainActor
    func testImportClearsUndoHistory() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: [.item(apps[2].identity)])]))
        let snapshot = LaunchpadSnapshot(pages: [[.app(launchpadApp(apps[0]))]])
        let (coordinator, published) = makeCoordinator(store, FakePrompter(), FakeLaunchpad(snapshot: snapshot))
        coordinator.start()
        await coordinator.catalogDidChange(apps)
        coordinator.apply(.move(.item(apps[0].identity.stableKey), to: .insert(page: 0, before: nil)))

        await coordinator.importFromLaunchpad()
        let imported = published.last
        coordinator.undo()

        XCTAssertEqual(published.last, imported)
    }

    @MainActor
    func testHidingPublishesHiddenAppsAndUnhideRestores() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: apps.map { .item($0.identity) })]))
        let (coordinator, published) = makeCoordinator(store, FakePrompter(), FakeLaunchpad())
        coordinator.start()
        await coordinator.catalogDidChange(apps)

        coordinator.apply(.hide([.item(apps[1].identity.stableKey), .item(apps[2].identity.stableKey)]))
        XCTAssertEqual(published.last, [[.item(apps[0])]])
        XCTAssertEqual(coordinator.hiddenApps, [apps[1], apps[2]])
        XCTAssertEqual(try store.load()?.hiddenItems, [apps[1].identity, apps[2].identity])

        coordinator.unhide(apps[2])
        XCTAssertEqual(published.last, [[.item(apps[0]), .item(apps[2])]])

        coordinator.unhideAll()
        XCTAssertEqual(published.last, [apps.map(ResolvedItem.item)])
        XCTAssertEqual(coordinator.hiddenApps, [])

        coordinator.undo()
        XCTAssertEqual(coordinator.hiddenApps, [apps[1]])
    }

    @MainActor
    func testReimportKeepsHiddenApps() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(
            pages: [LayoutPage(slots: [.item(apps[2].identity)])],
            hiddenItems: [apps[1].identity]
        ))
        let snapshot = LaunchpadSnapshot(pages: [[.app(launchpadApp(apps[0]))]])
        let (coordinator, published) = makeCoordinator(store, FakePrompter(), FakeLaunchpad(snapshot: snapshot))
        coordinator.start()
        await coordinator.catalogDidChange(apps)

        await coordinator.importFromLaunchpad()

        XCTAssertEqual(published.last, [[.item(apps[0]), .item(apps[2])]])
        XCTAssertEqual(coordinator.hiddenApps, [apps[1]])
    }

    @MainActor
    func testEditsUseUpdatedPageCapacity() async throws {
        let store = try temporaryStore()
        let many = makeLaunchItems(count: 5)
        try store.save(LayoutDocument(pages: [LayoutPage(slots: many.map { .item($0.identity) })]))
        let (coordinator, published) = makeCoordinator(store, FakePrompter(), FakeLaunchpad())
        coordinator.start()
        await coordinator.catalogDidChange(many)

        coordinator.updatePageCapacity(2)
        coordinator.apply(.move(
            .item(many[4].identity.stableKey),
            to: .insert(page: 0, before: .item(many[0].identity.stableKey))
        ))

        XCTAssertEqual(try store.load()?.pages.map(\.slots.count), [2, 2, 1])
        XCTAssertEqual(published.last?.map(\.count), [2, 2, 1])
    }

    @MainActor
    func testExportThenImportRestoresExportedLayout() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: apps.map { .item($0.identity) })], hiddenItems: [apps[2].identity]))
        let prompter = FakePrompter()
        let (coordinator, published) = makeCoordinator(store, prompter, FakeLaunchpad())
        coordinator.start()
        await coordinator.catalogDidChange(apps)
        let exported = try coordinator.exportBackup()
        coordinator.apply(.move(.item(apps[1].identity.stableKey), to: .insert(page: 0, before: .item(apps[0].identity.stableKey))))
        let edited = try store.load()

        let summary = coordinator.importBackup(exported)

        XCTAssertEqual(summary, LaunchpadImportSummary(pageCount: 1, folderCount: 0, appCount: 3, installedCount: 3, newAppCount: 0))
        XCTAssertEqual(prompter.backupSummaries, [summary!])
        XCTAssertEqual(try store.load(), try LayoutBackup.decode(exported))
        XCTAssertEqual(published.last, [[.item(apps[0]), .item(apps[1])]])
        XCTAssertEqual(coordinator.hiddenApps, [apps[2]])
        XCTAssertTrue(coordinator.canRestore)

        coordinator.undo()
        XCTAssertEqual(try store.load(), try LayoutBackup.decode(exported))
        prompter.answer = true
        coordinator.restoreBackup()
        XCTAssertEqual(try store.load(), edited)
    }

    @MainActor
    func testDeclinedOrInvalidBackupLeavesLayout() async throws {
        let store = try temporaryStore()
        try store.save(LayoutDocument(pages: [LayoutPage(slots: apps.map { .item($0.identity) })]))
        let prompter = FakePrompter()
        let (coordinator, _) = makeCoordinator(store, prompter, FakeLaunchpad())
        coordinator.start()
        await coordinator.catalogDidChange(apps)
        let before = try store.load()
        let other = try LayoutBackup.encode(LayoutDocument(pages: [LayoutPage(slots: [.item(apps[2].identity)])]))

        prompter.answer = false
        XCTAssertNil(coordinator.importBackup(other))
        XCTAssertNil(coordinator.importBackup(Data("not json".utf8)))
        XCTAssertNil(coordinator.importBackup(Data(#"{"schemaVersion":99,"pages":[]}"#.utf8)))

        XCTAssertEqual(try store.load(), before)
        XCTAssertEqual(prompter.errors.count, 2)
        XCTAssertFalse(coordinator.canRestore)
    }

    @MainActor
    private func makeCoordinator(
        _ store: LayoutStore,
        _ prompter: FakePrompter,
        _ launchpad: FakeLaunchpad
    ) -> (LayoutCoordinator, PublishedPages) {
        let published = PublishedPages()
        // 出错分支会写日志，用临时目录，不写进真实的日志文件
        let logDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: logDirectory) }
        let log = AppLog(directory: logDirectory)
        let coordinator = LayoutCoordinator(store: store, launchpad: launchpad, prompter: prompter, log: log)
        coordinator.onLayoutChange = { published.values.append($0) }
        return (coordinator, published)
    }

    private func temporaryStore() throws -> LayoutStore {
        LayoutStore(fileURL: try makeTemporaryDirectory().appending(path: "Launch/layout.json"))
    }
}
