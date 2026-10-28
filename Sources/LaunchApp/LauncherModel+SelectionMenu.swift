import CoreGraphics
import Foundation
import LaunchCore

// 多选与右键菜单命令
extension LauncherModel {
    func selectAllOnPage() {
        guard canMultiSelect else {
            return
        }
        setMultiSelection(MultiSelection(items: Set(visibleItems.compactMap(\.layoutID))))
    }

    func performMenuCommand(_ command: ItemMenuCommand) {
        switch command {
        case .mergeIntoNewFolder, .mergeInto, .moveToPage, .moveToNewPage, .hideSelection:
            performSelectionCommand(command)
        case .hide(let item):
            if canEditMenuItems {
                onEdit?(.hide([item]))
            }
        case .ungroup(let folder):
            if canEditMenuItems {
                onEdit?(.ungroupFolder(folder))
            }
        case .rename(let folder):
            showFolder(id: folder)
            beginRenamingFolder()
        case .selectAll:
            selectAllOnPage()
        case .open, .revealInFinder, .showInfo, .moveToTrash, .openSettings, .unhide, .arrangeLayout,
             .sortField, .sortDescending, .sortsFolderContents, .folderPlacement, .browsingStyle, .displayMode,
             .addWebsite, .addBookmarks, .editWebsite, .editEntryAppearance, .resetEntryIcon, .refreshWebsiteIcon,
             .pinEntry, .unpinEntry, .deleteWebsite:
            break
        }
    }

    // 搜索结果里也能隐藏，所以不要求搜索框为空
    var canEditMenuItems: Bool {
        canEditLayout && layoutPages != nil && renamingFolderID == nil
    }

    private func performSelectionCommand(_ command: ItemMenuCommand) {
        let items = multiSelection.ordered(in: pages)
        guard canMultiSelect, !items.isEmpty else {
            return
        }
        let edit: LayoutEdit
        switch command {
        case .mergeIntoNewFolder:
            edit = .mergeIntoNewFolder(items)
        case .mergeInto(let folder):
            edit = .moveGroup(items, to: .merge(.folder(folder)))
        case .moveToPage(let page):
            edit = .moveGroup(items, to: .insert(page: page, before: nil))
        case .moveToNewPage:
            edit = .moveGroup(items, to: .newPage)
        case .hideSelection:
            edit = .hide(items)
        case .open, .revealInFinder, .showInfo, .hide, .moveToTrash, .rename, .ungroup, .openSettings, .unhide,
             .selectAll, .arrangeLayout, .sortField, .sortDescending, .sortsFolderContents, .folderPlacement, .browsingStyle,
             .displayMode, .addWebsite, .addBookmarks, .editWebsite, .editEntryAppearance, .resetEntryIcon,
             .refreshWebsiteIcon, .pinEntry, .unpinEntry, .deleteWebsite:
            return
        }
        clearMultiSelection()
        selectedIndex = nil
        onEdit?(edit)
    }

    func isGroupDrag(_ press: ItemPress) -> Bool {
        guard case .grid = press.origin, let item = press.item.layoutID else {
            return false
        }
        return multiSelection.count > 1 && multiSelection.contains(item)
    }

    func setMultiSelection(_ selection: MultiSelection) {
        if selection != multiSelection {
            multiSelection = selection
        }
    }

    static func groupSources(_ items: [LayoutItemID], in pages: [[ResolvedItem]]) -> [Int: [Int]] {
        let wanted = Set(items)
        var sources: [Int: [Int]] = [:]
        for (page, pageItems) in pages.enumerated() {
            for (index, item) in pageItems.enumerated() where item.layoutID.map(wanted.contains) == true {
                sources[page, default: []].append(index)
            }
        }
        return sources
    }
}
