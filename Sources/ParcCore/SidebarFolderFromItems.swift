import Foundation

package struct SidebarFolderFromItems: Equatable {
    package static let defaultName = "Untitled"
    package static let undoName = "New Folder…"

    package struct Placement: Equatable { package let id: UUID, spaceID: UUID, kind: TabKind, folderID: UUID? }
    package struct Parts: Equatable {
        package var tabs: [Placement]
        package var folder: Placement?
        package var order: [String: [SidebarItemReference]]
    }
    package let folderID: UUID
    package let spaceID: UUID
    package let profileID: UUID
    package let tabIDs: [UUID]
    package var folder: BrowserFolder
    package let orderKeys: [String]
    package let before: Parts
    package let after: Parts

    package init(folderID: UUID, spaceID: UUID, profileID: UUID, tabIDs: [UUID], folder: BrowserFolder, orderKeys: [String], before: Parts, after: Parts) {
        self.folderID = folderID
        self.spaceID = spaceID
        self.profileID = profileID
        self.tabIDs = tabIDs
        self.folder = folder
        self.orderKeys = orderKeys
        self.before = before
        self.after = after
    }

    package static func make(items: [SidebarItemReference], folderID: UUID, name: String = defaultName,
                     expected: SidebarHierarchySnapshot, state: BrowserState) -> (Self, BrowserState)? {
        let spaceID = expected.spaceID, profileID = expected.profileID
        guard !items.isEmpty, !state.folders.contains(where: { $0.id == folderID }),
              SidebarHierarchySnapshot(state: state, spaceID: spaceID, profileID: profileID,
                  includesFavorites: expected.includesFavorites) == expected else { return nil }
        let locations = items.map { SidebarHierarchy.location(of: $0, state: state, spaceID: spaceID) }
        guard locations.allSatisfy({ $0 != nil && $0?.section != .favorite }) else { return nil }
        let first = locations[0]!
        let parentID = locations.allSatisfy({ $0 == first }) && first.section == .pinned ? first.folderID : nil
        let folder = BrowserFolder(id: folderID, spaceID: spaceID, name: name.isEmpty ? defaultName : name, parentID: parentID)
        var created = state
        created.folders.append(folder)
        var ancestor = parentID, visited = Set<UUID>()
        while let id = ancestor, visited.insert(id).inserted,
              let index = created.folders.firstIndex(where: { $0.id == id && $0.spaceID == spaceID }) {
            created.folders[index].isExpanded = true
            ancestor = created.folders[index].parentID
        }
        guard let current = SidebarHierarchySnapshot(state: created, spaceID: spaceID, profileID: profileID,
                  includesFavorites: expected.includesFavorites),
              let next = SidebarHierarchy.moving(items, to: SidebarContainerLocation(spaceID: spaceID,
                  folderID: folderID, section: .pinned), before: nil, expected: current, state: created) else { return nil }
        let tabIDs = items.flatMap { SidebarHierarchy.tabIDs(in: $0, state: state, spaceID: spaceID) }
        let keys = Set(state.sidebarItemOrder.keys).union(next.sidebarItemOrder.keys)
            .filter { state.sidebarItemOrder[$0] != next.sidebarItemOrder[$0] }.sorted()
        var receipt = Self(folderID: folderID, spaceID: spaceID, profileID: profileID, tabIDs: tabIDs, folder: folder,
                           orderKeys: keys, before: Parts(tabs: [], folder: nil, order: [:]),
                           after: Parts(tabs: [], folder: nil, order: [:]))
        receipt = Self(folderID: folderID, spaceID: spaceID, profileID: profileID, tabIDs: tabIDs, folder: folder,
                       orderKeys: keys, before: receipt.parts(of: state), after: receipt.parts(of: next))
        return (receipt, next)
    }

    package func parts(of state: BrowserState) -> Parts {
        let tabs = tabIDs.compactMap { id in state.tab(id, where: { $0.archivedAt == nil }) }
            .map { Placement(id: $0.id, spaceID: $0.spaceID, kind: $0.kind, folderID: $0.folderID) }
        let folder = state.folders.first { $0.id == folderID }
            .map { Placement(id: $0.id, spaceID: $0.spaceID, kind: .pinned, folderID: $0.parentID) }
        var order: [String: [SidebarItemReference]] = [:]
        for key in orderKeys { order[key] = state.sidebarItemOrder[key] }
        return Parts(tabs: tabs, folder: folder, order: order)
    }

    package func reverting(_ state: BrowserState, undo: Bool) -> BrowserState? {
        guard parts(of: state) == (undo ? after : before) else { return nil }
        if undo {
            let moved = Set(tabIDs)
            guard !state.containsOpenTab(where: { $0.folderID == folderID && !moved.contains($0.id) }),
                  !state.folders.contains(where: { $0.parentID == folderID }) else { return nil }
        }
        let target = undo ? before : after
        var next = state
        for placement in target.tabs {
            guard let index = next.tabIndex(placement.id) else { return nil }
            next.tabs[index].spaceID = placement.spaceID; next.tabs[index].kind = placement.kind
            next.tabs[index].folderID = placement.folderID
        }
        if undo { next.folders.removeAll { $0.id == folderID } }
        else if !next.folders.contains(where: { $0.id == folderID }) { next.folders.append(folder) }
        for key in orderKeys { next.sidebarItemOrder[key] = target.order[key] }
        return next
    }
}

package enum SidebarTodayArchive {
    package static func order(in state: BrowserState, spaceID: UUID) -> [UUID] {
        SidebarHierarchy.children(in: SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .today), state: state)
            .flatMap { SidebarHierarchy.tabIDs(in: $0, state: state, spaceID: spaceID) }
    }

    package static func admits(anchorID: UUID, order: [UUID], ids: Set<UUID>, state: BrowserState,
                       spaceID: UUID, profileID: UUID) -> Bool {
        guard !ids.isEmpty, ids.isSubset(of: Set(order)), order.contains(anchorID),
              let anchor = state.tab(anchorID, where: { $0.archivedAt == nil }),
              anchor.kind == .today, anchor.folderID == nil, anchor.spaceID == spaceID, anchor.profileID == profileID
        else { return false }
        return self.order(in: state, spaceID: spaceID) == order
    }
}
