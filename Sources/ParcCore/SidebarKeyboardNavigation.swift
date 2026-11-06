import Foundation

/// The sidebar command input traverses original container identities as well as
/// pages. Positional tab commands intentionally retain their selectable-only list.
enum SidebarKeyboardNavigation {
    struct Item {
        let reference: SidebarItemReference
        let selection: RecentTabOrder.Item?
        let folder: BrowserFolder?
        var id: String {
            switch reference {
            case .tab(let id): return "tab:" + id.uuidString
            case .folder(let id): return "folder:" + id.uuidString
            case .split(let id): return "split:" + id.uuidString
            }
        }
    }

    /// `peeks` lists the items each collapsed folder still shows under it.
    static func items(state: BrowserState, spaceID: UUID, selected: [UUID],
                      focused: UUID?, peeks: [UUID: [SidebarItemReference]] = [:], available: (UUID) -> Bool) -> [Item] {
        guard let space = state.spaces.first(where: { $0.id == spaceID }),
              state.profiles.contains(where: { $0.id == space.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == space.profileID }) else { return [] }
        let selections = PositionalTabNavigation.items(state: state, spaceID: spaceID,
            selected: selected, focused: focused, available: available)
        let groups = SidebarSplitItems.groups(in: state, spaceID: spaceID)
        var pages: [SidebarItemReference: RecentTabOrder.Item] = [:]
        for selection in selections {
            if let group = groups.first(where: { $0.tabIDs == selection.tabIDs }) {
                pages[.split(group.id)] = selection
            } else if selection.tabIDs.count == 1, let id = selection.tabIDs.first {
                pages[.tab(id)] = selection
            }
        }
        var result: [Item] = [], visited = Set<SidebarItemReference>()
        func appendPage(_ item: SidebarItemReference) {
            guard let selection = pages[item], visited.insert(item).inserted else { return }
            result.append(.init(reference: item, selection: selection, folder: nil))
        }
        SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: nil, section: .favorite, profileID: space.profileID), state: state).forEach(appendPage)
        func appendChildren(_ parent: UUID?, section: TabKind = .pinned, only: [SidebarItemReference]? = nil) {
            for item in SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: parent, section: section), state: state)
            where only?.contains(item) ?? true {
                if case .folder(let id) = item {
                    guard visited.insert(item).inserted,
                          let folder = state.folders.first(where: { $0.id == id && $0.spaceID == spaceID }) else { continue }
                    result.append(.init(reference: item, selection: nil, folder: folder))
                    if folder.isExpanded { appendChildren(id) }
                    else if let peeked = peeks[id], !peeked.isEmpty { appendChildren(id, only: peeked) }
                } else { appendPage(item) }
            }
        }
        appendChildren(nil); appendChildren(nil, section: .today)
        return result
    }
}
