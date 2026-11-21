import Foundation

package struct TabSelectionHistory {
    package static let isEnabled = false

    private struct Stack {
        var items: [RecentTabOrder.Item] = []
        var index: Int = -1
    }
    private var spaces: [UUID: Stack] = [:]

    package init() {}

    package mutating func record(_ item: RecentTabOrder.Item) {
        var stack = spaces[item.spaceID] ?? Stack()
        if stack.items.indices.contains(stack.index), stack.items[stack.index].id == item.id,
           stack.items[stack.index].profileID == item.profileID {
            stack.items[stack.index] = item
        } else {
            stack.items = Array(stack.items.prefix(max(0, stack.index + 1)))
            stack.items.append(item)
            stack.index = stack.items.count - 1
        }
        spaces[item.spaceID] = stack
    }

    package func destination(in space: UUID, forward: Bool,
                     available: (RecentTabOrder.Item) -> Bool) -> RecentTabOrder.Item? {
        guard let stack = spaces[space] else { return nil }
        let step = forward ? 1 : -1
        var index = stack.index + step
        while stack.items.indices.contains(index) {
            let item = stack.items[index]
            if available(item) { return item }
            index += step
        }
        return nil
    }

    package mutating func move(in space: UUID, forward: Bool,
                       available: (RecentTabOrder.Item) -> Bool) -> RecentTabOrder.Item? {
        guard var stack = spaces[space] else { return nil }
        let step = forward ? 1 : -1
        var index = stack.index + step
        while stack.items.indices.contains(index) {
            let item = stack.items[index]
            if available(item) {
                stack.index = index; spaces[space] = stack
                return item
            }
            index += step
        }
        return nil
    }
}

package enum PositionalTabNavigation {
    package static func items(state: BrowserState, spaceID: UUID, selected: [UUID],
                      focused: UUID?, includeFavorites: Bool = true,
                      available: (UUID) -> Bool) -> [RecentTabOrder.Item] {
        guard let space = state.spaces.first(where: { $0.id == spaceID }) else { return [] }
        let tabs = state.openTabs(where: { $0.profileID == space.profileID && ($0.kind == .favorite || $0.spaceID == spaceID) })
        let folders = state.folders.filter { $0.spaceID == spaceID }
        let groups = SidebarSplitItems.groups(in: state, spaceID: spaceID)
        var ordered: [BrowserTab] = []
        var visited = Set<UUID>()
        func appendItems(_ parent: UUID?, section: TabKind = .pinned) {
            for item in SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: parent, section: section, profileID: section == .favorite ? space.profileID : nil), state: state) {
                switch item {
                case .folder(let id):
                    guard visited.insert(id).inserted, folders.first(where: { $0.id == id })?.isExpanded == true else { continue }
                    appendItems(id)
                case .tab(let id):
                    if let tab = tabs.first(where: { $0.id == id }) { ordered.append(tab) }
                case .split(let id):
                    if let group = state.splitLayouts.first(where: { $0.id == id }), let tab = tabs.first(where: { $0.id == group.sidebarAnchorID }) { ordered.append(tab) }
                }
            }
        }
        if includeFavorites { appendItems(nil, section: .favorite) }
        appendItems(nil); appendItems(nil, section: .today)
        let usable = Dictionary(uniqueKeysWithValues: tabs.filter { available($0.id) }.map { ($0.id, $0) })
        var layouts = groups.reversed().map { $0.tabIDs }
        if selected.count > 1 { layouts.insert(selected, at: 0) }
        var assigned = Set<UUID>(), result: [RecentTabOrder.Item] = []
        for tab in ordered where !assigned.contains(tab.id) && usable[tab.id] != nil {
            let group = layouts.first { $0.contains(tab.id) }
            if let group, let saved = groups.first(where: { $0.tabIDs == group }),
               saved.sidebarAnchorID != tab.id { continue }
            let ids = group ?? [tab.id]
            guard ids.allSatisfy({ usable[$0] != nil && !assigned.contains($0) }) else { continue }
            let orientation = groups.first { $0.tabIDs == ids }?.orientation ?? .horizontal
            result.append(.init(tabIDs: ids, focusedTabID: focused.flatMap { ids.contains($0) ? $0 : nil } ?? ids[0],
                                spaceID: spaceID, profileID: space.profileID, orientation: orientation))
            assigned.formUnion(ids)
        }
        return result
    }

    package static func destination(_ items: [RecentTabOrder.Item], selected: [UUID],
                            forward: Bool) -> RecentTabOrder.Item? {
        guard !items.isEmpty else { return nil }
        guard let index = items.firstIndex(where: { $0.tabIDs == selected }) else {
            return forward ? items.first : items.last
        }
        return items[(index + (forward ? 1 : items.count - 1)) % items.count]
    }
}
