import Foundation

package struct SidebarMoveCollection: Equatable {
    package let hierarchy: SidebarHierarchySnapshot
    package let roots: [SidebarItemReference]
    package let tabIDs: [UUID]
    package let tabs: [BrowserTab]
    package let folderIDs: [UUID]

    package init?(items: [SidebarItemReference], spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard let hierarchy = SidebarHierarchySnapshot(state: state, spaceID: spaceID, profileID: profileID, includesFavorites: true),
              let roots = SidebarHierarchy.roots(items, state: state, spaceID: spaceID), !roots.isEmpty else { return nil }
        var ids: [UUID] = [], folders: [UUID] = [], groups: [UUID] = []
        func collect(_ item: SidebarItemReference) -> Bool {
            guard let location = SidebarHierarchy.location(of: item, state: state, spaceID: spaceID) else { return false }
            switch item {
            case .folder(let id):
                guard !folders.contains(id) else { return false }
                folders.append(id)
                return SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: id, section: .pinned), state: state).allSatisfy(collect)
            case .tab(let id): ids.append(id)
            case .split(let id):
                guard let group = hierarchy.groups.first(where: { $0.id == id }),
                      let anchor = group.sidebarAnchorID, group.tabIDs.contains(anchor), group.tabIDs.count > 1,
                      Set(group.tabIDs).count == group.tabIDs.count,
                      BrowserSplitLayout.normalized(group.widthFactors, count: group.tabIDs.count) != nil,
                      group.tabIDs.allSatisfy({ child in hierarchy.tabs.contains {
                          $0.id == child && $0.profileID == profileID &&
                          (location.section == .favorite
                            ? $0.kind == .favorite && $0.folderID == nil
                            : $0.kind != .favorite && $0.spaceID == spaceID)
                      } }) else { return false }
                groups.append(id); ids += group.tabIDs
            }
            return true
        }
        guard roots.allSatisfy(collect), Set(ids).count == ids.count,
              ids.allSatisfy({ id in hierarchy.tabs.contains { $0.id == id } }),
              hierarchy.tabs.filter({ $0.folderID.map(folders.contains) == true }).allSatisfy({ ids.contains($0.id) }),
              hierarchy.groups.filter({ !$0.tabIDs.allSatisfy { !ids.contains($0) } }).count == groups.count else { return nil }
        self.hierarchy = hierarchy; self.roots = roots; tabIDs = ids; folderIDs = folders
        tabs = ids.compactMap { id in state.tab(id) }
    }
}

package struct SidebarWindowMove: Equatable {
    package let collection: SidebarMoveCollection
    package let destination: SidebarHierarchySnapshot
    package let location: SidebarContainerLocation
    package let before: SidebarItemReference?
    package var tabIDs: [UUID] { collection.tabIDs }
    package var roots: [SidebarItemReference] { collection.roots }
    package var source: SidebarHierarchySnapshot { collection.hierarchy }
    package var crossesProfiles: Bool { source.profileID != destination.profileID }

    package init?(items: [SidebarItemReference], sourceSpaceID: UUID, profileID: UUID, destinationProfileID: UUID? = nil,
          to location: SidebarContainerLocation, before: SidebarItemReference?, state: BrowserState) {
        guard let collection = SidebarMoveCollection(items: items, spaceID: sourceSpaceID, profileID: profileID, state: state),
              let destination = SidebarHierarchySnapshot(state: state, spaceID: location.spaceID,
                  profileID: destinationProfileID ?? profileID, includesFavorites: true),
              destination.profileID == profileID || sourceSpaceID != location.spaceID else { return nil }
        self.collection = collection; self.destination = destination; self.location = location; self.before = before
        guard proposal(in: state) != nil else { return nil }
    }

    package func applying(to state: BrowserState) -> BrowserState? {
        guard SidebarMoveCollection(items: roots, spaceID: source.spaceID, profileID: source.profileID, state: state) == collection,
              SidebarHierarchySnapshot(state: state, spaceID: destination.spaceID, profileID: destination.profileID, includesFavorites: true) == destination else { return nil }
        return proposal(in: state)
    }

    private func proposal(in state: BrowserState) -> BrowserState? {
        var next = state
        if source.spaceID != destination.spaceID {
            guard let relocation = SidebarSpaceMove(items: roots, from: source, to: destination, state: next),
                  let moved = relocation.applying(to: next) else { return nil }
            next = moved
        }
        guard let expected = SidebarHierarchySnapshot(state: next, spaceID: destination.spaceID, profileID: destination.profileID, includesFavorites: true) else { return nil }
        return SidebarHierarchy.moving(roots, to: location, before: before, expected: expected, state: next)
    }
}
