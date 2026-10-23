import Foundation
import LaunchCore

@MainActor
protocol LayoutPrompting: AnyObject {
    func confirmFirstImport(_ summary: LaunchpadImportSummary) -> Bool
    func confirmReimport(_ summary: LaunchpadImportSummary) -> Bool
    func confirmBackupImport(_ summary: LaunchpadImportSummary) -> Bool
    func confirmRestore() -> Bool
    func showError(_ message: String)
}

protocol LaunchpadSource: Sendable {
    var isAvailable: Bool { get }
    func readSnapshot() async throws -> LaunchpadSnapshot
}

enum LayoutBackupError: LocalizedError {
    case noLayout

    var errorDescription: String? {
        "还没有可导出的布局"
    }
}

@MainActor
final class LayoutCoordinator {
    static var defaultLayoutURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Launch/layout.json")
    }

    static let undoLimit = 20

    var onLayoutChange: (([[ResolvedItem]]) -> Void)?
    var onDocumentChange: (() -> Void)?

    private let store: LayoutStore
    private let launchpad: LaunchpadSource
    private let prompter: LayoutPrompting
    private var pageCapacity: Int
    private let log: AppLog
    private var document: LayoutDocument?
    private var catalog: [LaunchItem] = []
    private var needsSetup = false
    private var isSettingUp = false
    private var isReadOnly = false
    private var hasReportedSaveError = false
    private var undoStack: [LayoutDocument] = []
    private(set) var replacementGeneration = UUID()
    private(set) var hiddenApps: [LaunchItem] = []

    init(
        store: LayoutStore,
        launchpad: LaunchpadSource,
        prompter: LayoutPrompting,
        pageCapacity: Int = GridSize.default.capacity,
        log: AppLog = .shared
    ) {
        self.store = store
        self.launchpad = launchpad
        self.prompter = prompter
        self.pageCapacity = pageCapacity
        self.log = log
    }

    // 只影响之后的编辑、导入与追加；已保存的页在下次编辑时按新容量拆分
    func updatePageCapacity(_ capacity: Int) {
        pageCapacity = capacity
    }

    var canImport: Bool {
        launchpad.isAvailable
    }

    var canRestore: Bool {
        store.hasBackup
    }

    var isEditable: Bool {
        document != nil && !isReadOnly
    }

    var extraItems: [ExtraItemDefinition] { document?.extraItems ?? [] }
    var pinnedIdentities: Set<ItemIdentity> { document?.pinnedIdentities ?? [] }

    @discardableResult
    func saveExtraItem(_ entry: ExtraItemDefinition, toPage page: Int? = nil, recordsUndo: Bool = true) -> Bool {
        guard isEditable, let document else { return false }
        var definitions = document.extraItems
        if let index = definitions.firstIndex(where: { $0.id == entry.id }) {
            guard definitions[index].identity == entry.identity else { return false }
            definitions[index] = entry
        } else { definitions.append(entry) }
        var next = LayoutDocument(pages: document.pages, hiddenItems: document.hiddenItems, extraItems: definitions)
        if let page {
            let context = catalog.filter { $0.identity != entry.identity } + [LaunchItem(definition: entry)]
            next = LayoutEditor.apply(.pin(entry.identity, page: page), to: next, catalog: context, pageCapacity: pageCapacity)
        }
        return commit(next, recordsUndo: recordsUndo)
    }

    @discardableResult
    func pin(_ identity: ItemIdentity, toPage page: Int) -> Bool {
        guard isEditable, let document else { return false }
        return commit(LayoutEditor.apply(.pin(identity, page: page), to: document, catalog: catalog, pageCapacity: pageCapacity))
    }

    @discardableResult
    func unpin(_ identity: ItemIdentity) -> Bool {
        guard isEditable, let document, identity.applicationIdentity == nil else { return false }
        return commit(document.removingEntry(identity, removeDefinition: false))
    }

    @discardableResult
    func deleteExtraItem(_ identity: ItemIdentity) -> Bool {
        guard isEditable, let document, case .website = identity else { return false }
        return commit(document.removingEntry(identity, removeDefinition: true))
    }

    func updateCachedIcon(_ data: Data?, for identity: ItemIdentity, expectedURL: URL) {
        guard var entry = extraItems.first(where: { $0.identity == identity }),
              case .website(let current) = entry.target, current == expectedURL else { return }
        entry.cachedIconData = data
        saveExtraItem(entry, recordsUndo: false)
    }

    func apply(_ edit: LayoutEdit) {
        guard isEditable, let document else {
            return
        }
        let edited = LayoutEditor.apply(edit, to: document, catalog: catalog, pageCapacity: pageCapacity)
        guard edited != document else {
            return
        }
        commit(edited)
    }

    func undo() {
        guard isEditable, let previous = undoStack.last else {
            return
        }
        if commit(previous, recordsUndo: false, invalidatesIcons: true) { undoStack.removeLast() }
    }

    func unhide(_ app: LaunchItem) {
        apply(.unhide([app.identity]))
    }

    // 未安装的隐藏应用也一并取消
    func unhideAll() {
        apply(.unhide(document?.hiddenItems ?? []))
    }

    func start() {
        do {
            document = try store.load()
            needsSetup = document == nil
        } catch {
            isReadOnly = true
            fail("布局文件无法读取，暂时按名称排列；文件保持原样。")
        }
    }

    func catalogDidChange(_ apps: [LaunchItem]) async {
        catalog = apps
        guard !isSettingUp else {
            return
        }
        if needsSetup {
            isSettingUp = true
            await runFirstSetup()
            needsSetup = false
            isSettingUp = false
        }
        publish()
    }

    func importFromLaunchpad() async {
        do {
            let snapshot = try await launchpad.readSnapshot()
            let result = LaunchpadImporter.makeImport(from: snapshot, catalog: catalog.compactMap(\.application), pageCapacity: pageCapacity)
            guard prompter.confirmReimport(result.summary) else {
                return
            }
            var document = LayoutDocument(
                schemaVersion: result.document.schemaVersion,
                pages: result.document.pages,
                hiddenItems: self.document?.hiddenItems ?? [],
                extraItems: self.document?.extraItems ?? []
            )
            let retained = self.document?.pages.flatMap(\.slots).flatMap { slot -> [ItemIdentity] in
                switch slot {
                case .item(let id): return id.applicationIdentity == nil ? [id] : []
                case .folder(let folder): return folder.items.filter { $0.applicationIdentity == nil }
                case .empty: return []
                }
            } ?? []
            document = LayoutEngine.appending(retained, to: document, pageCapacity: pageCapacity)
            try store.replace(with: document)
            self.document = document
            replacementGeneration = UUID()
            isReadOnly = false
            needsSetup = false
            undoStack.removeAll()
            publish()
        } catch {
            fail("导入失败：\(error.localizedDescription)")
        }
    }

    func exportBackup() throws -> Data {
        guard let document else {
            throw LayoutBackupError.noLayout
        }
        return try LayoutBackup.encode(document)
    }

    // 与 Launchpad 导入一样：覆盖前自动备份，可用「恢复导入前的布局」换回
    func importBackup(_ data: Data) -> LaunchpadImportSummary? {
        do {
            let result = LayoutBackup.makeImport(from: try LayoutBackup.decode(data), catalog: catalog, pageCapacity: pageCapacity)
            guard prompter.confirmBackupImport(result.summary) else {
                return nil
            }
            try store.replace(with: result.document)
            document = result.document
            replacementGeneration = UUID()
            isReadOnly = false
            needsSetup = false
            undoStack.removeAll()
            publish()
            return result.summary
        } catch {
            fail("导入失败：\(error.localizedDescription)")
            return nil
        }
    }

    func restoreBackup() {
        guard prompter.confirmRestore() else {
            return
        }
        do {
            try store.swapWithBackup()
            document = try store.load()
            replacementGeneration = UUID()
            isReadOnly = false
            needsSetup = false
            undoStack.removeAll()
            publish()
        } catch {
            fail("恢复失败：\(error.localizedDescription)")
        }
    }

    private func runFirstSetup() async {
        var imported: LayoutDocument?
        if launchpad.isAvailable {
            do {
                let snapshot = try await launchpad.readSnapshot()
                let result = LaunchpadImporter.makeImport(from: snapshot, catalog: catalog.compactMap(\.application), pageCapacity: pageCapacity)
                if prompter.confirmFirstImport(result.summary) {
                    imported = result.document
                }
            } catch {
                fail(error.localizedDescription)
            }
        }
        let document = imported ?? LayoutEngine.defaultDocument(catalog: catalog, pageCapacity: pageCapacity)
        self.document = document
        save(document)
    }

    private func publish() {
        defer { onDocumentChange?() }
        guard let document else {
            let fallback = LayoutEngine.defaultDocument(catalog: catalog, pageCapacity: pageCapacity)
            hiddenApps = []
            onLayoutChange?(LayoutEngine.reconcile(layout: fallback, catalog: catalog, pageCapacity: pageCapacity).pages)
            return
        }
        let reconciled = LayoutEngine.reconcile(layout: document, catalog: catalog, pageCapacity: pageCapacity)
        if !reconciled.appendedApps.isEmpty {
            self.document = reconciled.document
            save(reconciled.document)
        }
        hiddenApps = reconciled.hiddenItems
        onLayoutChange?(reconciled.pages)
    }

    private func fail(_ message: String) {
        log.error(message)
        prompter.showError(message)
    }

    @discardableResult
    private func commit(_ next: LayoutDocument, recordsUndo: Bool = true, invalidatesIcons: Bool = false) -> Bool {
        guard isEditable, let previous = document else { return false }
        guard next != previous else { return true }
        do { try store.save(next) }
        catch { fail("保存布局失败：\(error.localizedDescription)"); return false }
        if recordsUndo {
            undoStack.append(previous)
            if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        }
        document = next
        if invalidatesIcons { replacementGeneration = UUID() }
        publish()
        return true
    }

    private func save(_ document: LayoutDocument) {
        guard !isReadOnly else {
            return
        }
        do {
            try store.save(document)
        } catch {
            guard !hasReportedSaveError else {
                return
            }
            hasReportedSaveError = true
            fail("保存布局失败：\(error.localizedDescription)")
        }
    }
}
