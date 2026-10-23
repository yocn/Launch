import Foundation

extension LayoutDocument {
    public var pinnedIdentities: Set<ItemIdentity> {
        Set(pages.flatMap(\.slots).flatMap { slot -> [ItemIdentity] in
            switch slot {
            case .item(let id): [id]
            case .folder(let folder): folder.items
            case .empty: []
            }
        })
    }

    /// Removing an entry is a layout operation, never a filesystem operation.
    public func removingEntry(_ identity: ItemIdentity, removeDefinition: Bool) -> LayoutDocument {
        guard identity.applicationIdentity == nil else { return self }
        let updated = pages.map { page in
            LayoutPage(slots: page.slots.compactMap { slot -> LayoutSlot? in
                switch slot {
                case .item(let id): return id == identity ? nil : slot
                case .folder(let folder):
                    guard folder.items.contains(identity) else { return slot }
                    let members = folder.items.filter { $0 != identity }
                    guard !members.isEmpty else { return nil }
                    if members.count == 1 { return .item(members[0]) }
                    return .folder(LayoutFolder(id: folder.id, name: folder.name, items: members))
                case .empty: return slot
                }
            })
        }.filter { $0.slots.contains { $0 != .empty } }
        return LayoutDocument(pages: updated, hiddenItems: hiddenItems.filter { $0 != identity },
                              extraItems: removeDefinition ? extraItems.filter { $0.identity != identity } : extraItems)
    }
}
