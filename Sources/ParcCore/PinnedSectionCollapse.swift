import Foundation

package enum PinnedSectionCollapse {
    package static func isFolded(state: BrowserState, spaceID: UUID) -> Bool {
        state.spaces.contains { $0.id == spaceID && $0.pinnedCollapsed } && hasItems(state: state, spaceID: spaceID)
    }

    package static func hasItems(state: BrowserState, spaceID: UUID) -> Bool {
        state.spaces.contains { $0.id == spaceID }
            && !SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: nil, section: .pinned), state: state).isEmpty
    }

    package static func isEmpty(state: BrowserState, spaceID: UUID) -> Bool {
        state.spaces.contains { $0.id == spaceID } && !hasItems(state: state, spaceID: spaceID)
            && SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: nil, section: .today), state: state).isEmpty
    }

    package static func activeItem(state: BrowserState, spaceID: UUID, tabID: UUID?) -> SidebarItemReference? {
        guard let id = tabID else { return nil }
        return SidebarSplitItems.groups(in: state, spaceID: spaceID).first { $0.tabIDs.contains(id) }
            .map { .split($0.id) } ?? .tab(id)
    }

    package static func peek(state: BrowserState, spaceID: UUID, active: SidebarItemReference?) -> [SidebarItemReference] {
        guard let active, var location = SidebarHierarchy.location(of: active, state: state, spaceID: spaceID),
              location.section == .pinned else { return [] }
        var path = [active], seen = Set<UUID>()
        while let folderID = location.folderID {
            guard seen.insert(folderID).inserted,
                  let parent = SidebarHierarchy.location(of: .folder(folderID), state: state, spaceID: spaceID),
                  parent.section == .pinned else { return [] }
            path.insert(.folder(folderID), at: 0)
            location = parent
        }
        return path
    }

    package static func headerDrop(state: BrowserState, spaceID: UUID,
                           moving items: [SidebarItemReference]) -> (destination: SidebarContainerLocation, before: SidebarItemReference?) {
        let destination = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .pinned)
        return (destination, SidebarHierarchy.children(in: destination, state: state).first { !items.contains($0) })
    }

    package struct Summary: Equatable {
        static let shownIcons = 4
        package var tabs: [BrowserTab]
        package var count: Int
        package var hidden: Int { max(0, count - tabs.count) }

        package init(tabs: [BrowserTab], count: Int) {
            self.tabs = tabs
            self.count = count
        }
    }

    package static func summary(state: BrowserState, spaceID: UUID) -> Summary {
        guard let space = state.spaces.first(where: { $0.id == spaceID }) else { return Summary(tabs: [], count: 0) }
        let groups = SidebarSplitItems.groups(in: state, spaceID: spaceID)
        var shown: [BrowserTab] = [], count = 0, visited = Set<UUID>()
        func add(_ id: UUID) {
            guard let tab = state.tab(id, where: { $0.archivedAt == nil && $0.profileID == space.profileID && $0.spaceID == spaceID })
            else { return }
            count += 1
            if shown.count < Summary.shownIcons { shown.append(tab) }
        }
        func walk(_ folderID: UUID?) {
            for item in SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: folderID, section: .pinned), state: state) {
                switch item {
                case .tab(let id): add(id)
                case .split(let id): groups.first { $0.id == id }?.tabIDs.forEach(add)
                case .folder(let id): if visited.insert(id).inserted { walk(id) }
                }
            }
        }
        walk(nil)
        return Summary(tabs: shown, count: count)
    }
}

extension BrowserStore {
    private static var pinnedFoldClearFailures: [ObjectIdentifier: UInt64] = [:]

    package func clearEmptyPinnedFolds() {
        guard !isEphemeral, Self.pinnedFoldClearFailures[ObjectIdentifier(self)] != stateRevision else { return }
        var next = state, cleared = false
        for index in next.spaces.indices where next.spaces[index].pinnedCollapsed
            && !next.profileRemovals.contains(where: { $0.profileID == next.spaces[index].profileID })
            && !PinnedSectionCollapse.hasItems(state: next, spaceID: next.spaces[index].id) {
            next.spaces[index].pinnedCollapsed = false
            cleared = true
        }
        guard cleared else { return }
        do { try commitProfileSettings(next) } catch { Self.pinnedFoldClearFailures[ObjectIdentifier(self)] = stateRevision }
    }

    @discardableResult
    package func setPinnedSectionCollapsed(_ collapsed: Bool, spaceID: UUID) throws -> Bool {
        guard !isEphemeral, let index = state.spaces.firstIndex(where: { $0.id == spaceID }),
              !state.profileRemovals.contains(where: { $0.profileID == state.spaces[index].profileID }),
              !collapsed || PinnedSectionCollapse.hasItems(state: state, spaceID: spaceID) else { return false }
        guard state.spaces[index].pinnedCollapsed != collapsed else { return true }
        var next = state
        next.spaces[index].pinnedCollapsed = collapsed
        try commitProfileSettings(next)
        return true
    }
}
