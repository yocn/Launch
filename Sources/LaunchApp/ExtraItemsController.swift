import Foundation
import Observation
import LaunchCore

enum ExtraItemError: LocalizedError {
    case emptyName, saveFailed, unavailable
    var errorDescription: String? {
        switch self {
        case .emptyName: "名称不能为空"
        case .saveFailed: "条目没有保存，请检查布局是否可编辑。"
        case .unavailable: "这个快捷指令目前不可用，请刷新清单。"
        }
    }
}

// 批量添加时同时最多取 3 个网站图标
actor IconFetchGate {
    static let shared = IconFetchGate(limit: 3)
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit }

    func run(_ work: @Sendable () async -> Data?) async -> Data? {
        if running >= limit { await withCheckedContinuation { waiting.append($0) } } else { running += 1 }
        let result = await work()
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
        return result
    }
}

@MainActor @Observable
final class ExtraItemsController {
    private(set) var items: [LaunchItem] = []
    private(set) var shortcutRecords: [ShortcutRecord] = []
    private(set) var isRefreshing = false
    private(set) var runningShortcuts: Set<UUID> = []
    private(set) var fetchingIcons: Set<ItemIdentity> = []
    private(set) var lastError: String?
    private(set) var definitions: [ExtraItemDefinition] = []
    private(set) var pinnedIdentities: Set<ItemIdentity> = []
    private(set) var canEdit = false
    @ObservationIgnored var onCatalogChange: (([LaunchItem]) -> Void)?
    @ObservationIgnored private let layout: LayoutCoordinator
    @ObservationIgnored private let shortcuts: ShortcutService
    @ObservationIgnored private let fetchIcon: @Sendable (URL) async -> Data?
    @ObservationIgnored private var applications: [LaunchItem] = []
    // 应用扫描完成前不推送目录：布局会在只有条目、没有应用时跑首次设置
    @ObservationIgnored private var hasScannedApplications = false
    // 清单成功读到过才能判断指令被删；启动时还没读到或读取失败都不置灰
    @ObservationIgnored private var hasListedShortcuts = false
    @ObservationIgnored private var iconTasks: [ItemIdentity: Task<Void, Never>] = [:]
    @ObservationIgnored private var iconVersions: [ItemIdentity: UUID] = [:]
    @ObservationIgnored private var documentGeneration: UUID

    init(layout: LayoutCoordinator, shortcuts: ShortcutService = ShortcutService(),
         fetchIcon: @escaping @Sendable (URL) async -> Data? = { url in await IconFetchGate.shared.run { await WebsiteIconFetcher().fetch(for: url) } }) {
        self.layout = layout
        self.shortcuts = shortcuts
        self.fetchIcon = fetchIcon
        documentGeneration = layout.replacementGeneration
        rebuild()
    }

    func isPinned(_ identity: ItemIdentity) -> Bool { pinnedIdentities.contains(identity) }

    func setApplications(_ apps: [CatalogApp]) {
        applications = apps.map(LaunchItem.init(application:))
        hasScannedApplications = true
        rebuild()
    }

    func layoutDidChange() {
        if documentGeneration != layout.replacementGeneration {
            iconTasks.values.forEach { $0.cancel() }
            iconTasks.removeAll()
            iconVersions.removeAll()
            fetchingIcons.removeAll()
            documentGeneration = layout.replacementGeneration
        }
        let valid = Set(layout.extraItems.map(\.identity))
        for identity in Array(iconTasks.keys) where !valid.contains(identity) {
            iconTasks.removeValue(forKey: identity)?.cancel()
            iconVersions.removeValue(forKey: identity)
            fetchingIcons.remove(identity)
        }
        rebuild()
    }

    func refreshShortcuts() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            shortcutRecords = try await shortcuts.list()
            hasListedShortcuts = true
            lastError = nil
        }
        catch { lastError = error.localizedDescription }
        rebuild()
    }

    @discardableResult
    func saveWebsite(name: String, address: String, existing: ExtraItemDefinition?, toPage page: Int?,
                     customIconData: Data?) throws -> ExtraItemDefinition {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ExtraItemError.emptyName }
        let url = try WebsiteAddress.normalized(address)
        var entry = ExtraItemDefinition(id: existing?.id ?? UUID(), name: name, target: .website(url), customIconData: customIconData)
        if let current = layout.extraItems.first(where: { $0.id == entry.id }), current.target == entry.target {
            entry.cachedIconData = current.cachedIconData
        }
        guard layout.saveExtraItem(entry, toPage: page) else { throw ExtraItemError.saveFailed }
        rebuild()
        if existing?.target != entry.target, customIconData == nil { refreshWebsiteIcon(entry.identity) }
        return entry
    }

    // 书签批量添加：跳过已有的网址，整批一次撤销，图标随后逐个取
    @discardableResult
    func addWebsites(_ links: [(name: String, url: URL, icon: Data?)], toPage page: Int?) -> Int {
        var known = Set(layout.extraItems.compactMap { entry -> URL? in
            if case .website(let url) = entry.target { url } else { nil }
        })
        let entries = links.compactMap { link -> ExtraItemDefinition? in
            guard known.insert(link.url).inserted else { return nil }
            // 先用浏览器本地缓存的图标，联网取到更清晰的再替换；联网失败也有图标
            let icon = link.icon.flatMap { ItemImageData.normalized($0) }
            return ExtraItemDefinition(name: link.name, target: .website(link.url), cachedIconData: icon)
        }
        guard layout.saveExtraItems(entries, toPage: page) else { return 0 }
        rebuild()
        entries.forEach { refreshWebsiteIcon($0.identity) }
        return entries.count
    }

    func refreshWebsiteIcon(_ identity: ItemIdentity) {
        guard let entry = definitions.first(where: { $0.identity == identity }), case .website(let url) = entry.target else { return }
        iconTasks[identity]?.cancel()
        let version = UUID()
        iconVersions[identity] = version
        fetchingIcons.insert(identity)
        let fetchIcon = self.fetchIcon
        let generation = layout.replacementGeneration
        iconTasks[identity] = Task { [weak self] in
            let data = await fetchIcon(url)
            guard let self, !Task.isCancelled, iconVersions[identity] == version,
                  layout.replacementGeneration == generation else { return }
            layout.updateCachedIcon(data, for: identity, expectedURL: url)
            iconTasks.removeValue(forKey: identity)
            iconVersions.removeValue(forKey: identity)
            fetchingIcons.remove(identity)
            rebuild()
        }
    }

    @discardableResult
    func pin(_ identity: ItemIdentity, toPage page: Int) -> Bool {
        guard let item = items.first(where: { $0.identity == identity }), item.application == nil else { return false }
        let entry = definition(for: item)
        let result = layout.saveExtraItem(entry, toPage: page)
        rebuild()
        return result
    }

    @discardableResult
    func unpin(_ identity: ItemIdentity) -> Bool {
        let result = layout.unpin(identity)
        rebuild()
        return result
    }

    @discardableResult
    func deleteWebsite(_ identity: ItemIdentity) -> Bool {
        guard case .website = identity else { return false }
        iconTasks.removeValue(forKey: identity)?.cancel()
        iconVersions.removeValue(forKey: identity)
        fetchingIcons.remove(identity)
        let result = layout.deleteExtraItem(identity)
        rebuild()
        return result
    }

    func updateAppearance(of identity: ItemIdentity, name: String?, customIconData: Data?) throws {
        guard let item = items.first(where: { $0.identity == identity }), item.application == nil else { throw ExtraItemError.unavailable }
        var entry = definition(for: item)
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ExtraItemError.emptyName }
            if case .shortcut = entry.target {
                if trimmed != item.displayName { entry.nameOverride = trimmed }
            }
            else { entry.name = trimmed }
        }
        entry.customIconData = customIconData
        guard layout.saveExtraItem(entry) else { throw ExtraItemError.saveFailed }
        rebuild()
    }

    @discardableResult
    func runShortcut(id: UUID) async throws -> Bool {
        guard items.contains(where: { $0.identity == .shortcut(id) && $0.isAvailable }) else { throw ExtraItemError.unavailable }
        guard runningShortcuts.insert(id).inserted else { return false }
        defer { runningShortcuts.remove(id) }
        try await shortcuts.run(id: id)
        return true
    }

    private func definition(for item: LaunchItem) -> ExtraItemDefinition {
        if let entry = definitions.first(where: { $0.identity == item.identity }) { return entry }
        switch item.target {
        case .shortcut(let id): return ExtraItemDefinition(id: id, name: item.displayName, target: .shortcut(id))
        case .website(let url): return ExtraItemDefinition(name: item.displayName, target: .website(url))
        case .application: preconditionFailure("真实应用不能转换为自定义条目")
        }
    }

    private func rebuild() {
        let definitions = layout.extraItems
        self.definitions = definitions
        pinnedIdentities = layout.pinnedIdentities
        canEdit = layout.isEditable
        var next = applications + definitions.compactMap { entry -> LaunchItem? in
            guard case .website = entry.target else { return nil }
            return LaunchItem(definition: entry)
        }
        var seen = Set<UUID>()
        for record in shortcutRecords {
            let saved = definitions.first { $0.identity == .shortcut(record.id) }
            var definition = saved ?? ExtraItemDefinition(id: record.id, name: record.name, target: .shortcut(record.id))
            definition.name = record.name
            next.append(LaunchItem(definition: definition))
            seen.insert(record.id)
        }
        for entry in definitions {
            guard case .shortcut(let id) = entry.target, !seen.contains(id), layout.pinnedIdentities.contains(entry.identity) else { continue }
            next.append(LaunchItem(definition: entry, unavailableReason: hasListedShortcuts ? "快捷指令已删除或未同步到这台 Mac" : nil))
        }
        next.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        guard items != next else { return }
        items = next
        if hasScannedApplications {
            onCatalogChange?(next)
        }
    }
}
