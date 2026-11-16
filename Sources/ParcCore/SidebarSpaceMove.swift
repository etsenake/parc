import Foundation

struct SidebarSpaceMove: Equatable {
    let source: SidebarHierarchySnapshot
    let destination: SidebarHierarchySnapshot
    let roots: [SidebarItemReference]
    let tabIDs: [UUID]
    let folderIDs: [UUID]
    let groupIDs: [UUID]
    var pinsToday = false

    init?(items: [SidebarItemReference], from source: SidebarHierarchySnapshot,
          to destination: SidebarHierarchySnapshot, state: BrowserState) {
        guard source.spaceID != destination.spaceID,
              source.profileID == destination.profileID
                || InterProfileMove.profilesAvailable(source.profileID, destination.profileID, in: state),
              SidebarHierarchySnapshot(state: state, spaceID: source.spaceID, profileID: source.profileID, includesFavorites: source.includesFavorites) == source,
              SidebarHierarchySnapshot(state: state, spaceID: destination.spaceID, profileID: destination.profileID, includesFavorites: destination.includesFavorites) == destination,
              let roots = SidebarHierarchy.roots(items, state: state, spaceID: source.spaceID), !roots.isEmpty else { return nil }
        var tabs: [UUID] = [], folders: [UUID] = [], groups: [UUID] = []
        func collect(_ item: SidebarItemReference) -> Bool {
            guard let location = SidebarHierarchy.location(of: item, state: state, spaceID: source.spaceID) else { return false }
            switch item {
            case .folder(let id):
                guard !folders.contains(id) else { return false }
                folders.append(id)
                for child in SidebarHierarchy.children(in: .init(spaceID: source.spaceID, folderID: id, section: .pinned), state: state) {
                    guard collect(child) else { return false }
                }
            case .tab(let id): tabs.append(id)
            case .split(let id):
                guard let group = source.groups.first(where: { $0.id == id }),
                      let anchor = group.sidebarAnchorID, group.tabIDs.contains(anchor), group.tabIDs.count > 1,
                      Set(group.tabIDs).count == group.tabIDs.count,
                      BrowserSplitLayout.normalized(group.widthFactors, count: group.tabIDs.count) != nil,
                      group.tabIDs.allSatisfy({ child in source.tabs.contains {
                          $0.id == child && $0.profileID == source.profileID &&
                              (location.section == .favorite
                                  ? $0.kind == .favorite && $0.folderID == nil
                                  : $0.kind != .favorite && $0.spaceID == source.spaceID)
                      } }) else { return false }
                groups.append(id); tabs += group.tabIDs
            }
            return true
        }
        guard roots.allSatisfy(collect), Set(tabs).count == tabs.count,
              tabs.allSatisfy({ id in source.tabs.contains { $0.id == id } }),
              source.tabs.filter({ $0.folderID.map(folders.contains) == true }).allSatisfy({ tabs.contains($0.id) }),
              source.groups.filter({ !$0.tabIDs.allSatisfy { !tabs.contains($0) } }).count == groups.count else { return nil }
        if source.profileID != destination.profileID {
            guard tabs.allSatisfy({ id in state.tab(id).map(InterProfileMove.admits) == true }) else { return nil }
        }
        self.source = source; self.destination = destination; self.roots = roots
        tabIDs = tabs; folderIDs = folders; groupIDs = groups
    }

    var crossesProfiles: Bool { source.profileID != destination.profileID }

    func permitsSplitOwners(_ owners: [UUID: UUID], in windowID: UUID) -> Bool {
        source.groups.filter { groupIDs.contains($0.id) }.allSatisfy { group in
            group.tabIDs.allSatisfy { owners[$0] == nil || owners[$0] == windowID }
        }
    }

    func applying(to state: BrowserState) -> BrowserState? {
        guard var current = SidebarSpaceMove(items: roots, from: source, to: destination, state: state) else { return nil }
        current.pinsToday = pinsToday
        guard current == self else { return nil }
        var next = state
        let movedTabs = Set(tabIDs), movedFolders = Set(folderIDs)
        func stored(_ item: SidebarItemReference) -> SidebarItemReference {
            if case .split(let id) = item, let anchor = state.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
            return item
        }
        let movedGroups = Set(groupIDs)
        for key in next.sidebarItemOrder.keys where key.hasPrefix(source.spaceID.uuidString + ":") {
            next.sidebarItemOrder[key]?.removeAll { item in
                switch item {
                case .tab(let id): return movedTabs.contains(id)
                case .folder(let id): return movedFolders.contains(id)
                case .split(let id): return movedGroups.contains(id)
                }
            }
        }
        var sections: [TabKind: [SidebarItemReference]] = [:]
        for root in roots {
            guard let location = SidebarHierarchy.location(of: root, state: state, spaceID: source.spaceID) else { return nil }
            sections[pinsToday && location.section == .today ? .pinned : location.section, default: []].append(root)
            next.sidebarItemOrder[location.key] = SidebarHierarchy.children(in: location, state: state)
                .filter { !roots.contains($0) }.map(stored)
            switch root {
            case .folder(let id):
                next.folders[next.folders.firstIndex(where: { $0.id == id })!].parentID = nil
            case .tab, .split:
                for id in SidebarHierarchy.tabIDs(in: root, state: state, spaceID: source.spaceID) {
                    next.tabs[next.tabIndex(id)!].folderID = nil
                }
            }
        }
        for id in folderIDs {
            let old = SidebarContainerLocation(spaceID: source.spaceID, folderID: id, section: .pinned)
            let new = SidebarContainerLocation(spaceID: destination.spaceID, folderID: id, section: .pinned)
            next.sidebarItemOrder.removeValue(forKey: old.key)
            next.sidebarItemOrder[new.key] = SidebarHierarchy.children(in: old, state: state).map(stored)
        }
        for (kind, items) in sections {
            let target = SidebarContainerLocation(spaceID: destination.spaceID, folderID: nil, section: kind,
                profileID: kind == .favorite ? destination.profileID : nil)
            next.sidebarItemOrder[target.key] = (SidebarHierarchy.children(in: target, state: state).filter { !items.contains($0) } + items).map(stored)
        }
        for groupID in groupIDs {
            guard let group = source.groups.first(where: { $0.id == groupID }),
                  let location = SidebarHierarchy.location(of: .split(groupID), state: state,
                      spaceID: source.spaceID) else { return nil }
            let parent = location.folderID.flatMap { movedFolders.contains($0) ? $0 : nil }
            for i in next.tabs.indices where group.tabIDs.contains(next.tabs[i].id) {
                next.tabs[i].folderID = parent
                next.tabs[i].kind = location.section
            }
        }
        for i in next.tabs.indices where movedTabs.contains(next.tabs[i].id) {
            next.tabs[i].spaceID = destination.spaceID; next.tabs[i].profileID = destination.profileID
            if pinsToday && next.tabs[i].kind == .today {
                next.tabs[i].kind = .pinned
                next.tabs[i].savedURL = next.tabs[i].url; next.tabs[i].savedTitle = next.tabs[i].title
            }
        }
        for i in next.folders.indices where movedFolders.contains(next.folders[i].id) { next.folders[i].spaceID = destination.spaceID }
        for i in next.splitLayouts.indices where groupIDs.contains(next.splitLayouts[i].id) { next.splitLayouts[i].spaceID = destination.spaceID }
        for key in next.selectionBySpace.keys where key != destination.spaceID.uuidString {
            next.selectionBySpace[key]?.removeAll { movedTabs.contains($0) }
        }
        if next.activeSpaceID != destination.spaceID { next.selectedTabIDs.removeAll { movedTabs.contains($0) } }
        return next
    }
}

struct SidebarItemReveal: Equatable {
    let item: SidebarItemReference
    let spaceID: UUID
    let profileID: UUID
    let expandedFolderIDs: Set<UUID>

    init?(item: SidebarItemReference, spaceID: UUID, profileID: UUID, state: BrowserState) {
        guard state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              let location = SidebarHierarchy.location(of: item, state: state, spaceID: spaceID),
              location.section != .favorite else { return nil }
        var expanded = Set<UUID>(), parent = location.folderID
        if case .folder(let id) = item,
           !SidebarHierarchy.children(in: .init(spaceID: spaceID, folderID: id, section: .pinned), state: state).isEmpty {
            expanded.insert(id)
        }
        while let id = parent {
            guard expanded.insert(id).inserted,
                  let folder = state.folders.first(where: { $0.id == id && $0.spaceID == spaceID }) else { return nil }
            parent = folder.parentID
        }
        self.item = item; self.spaceID = spaceID; self.profileID = profileID; expandedFolderIDs = expanded
    }

    func applying(to state: BrowserState) -> BrowserState? {
        guard SidebarItemReveal(item: item, spaceID: spaceID, profileID: profileID, state: state) == self else { return nil }
        var next = state
        for index in next.folders.indices where expandedFolderIDs.contains(next.folders[index].id) {
            next.folders[index].isExpanded = true
        }
        return next
    }
}


enum SidebarSpaceInsertion: Equatable {
    case after(UUID)
    case absolute(Int)

    func index(in state: BrowserState) -> Int? {
        switch self {
        case .after(let id): return state.spaces.firstIndex { $0.id == id }.map { $0 + 1 }
        case .absolute(let index): return (0...state.spaces.count).contains(index) ? index : nil
        }
    }
}

struct SidebarNewSpaceDraft: Equatable {
    let source: SidebarHierarchySnapshot
    let spaceID: UUID
    let insertion: SidebarSpaceInsertion
    let roots: [SidebarItemReference]
    let tabIDs: [UUID]
    let folderIDs: [UUID]
    let groupIDs: [UUID]
    var name: String
    var profileID: UUID
    var customIcon: SidebarGroupIcon?
    var theme: SpaceTheme
    private(set) var separateProfileID: UUID?
    private var acceptsProfileChange = false

    init?(items: [SidebarItemReference] = [], from source: SidebarHierarchySnapshot,
          state: BrowserState, spaceID: UUID = UUID(), insertion: SidebarSpaceInsertion? = nil,
          theme: SpaceTheme? = nil) {
        guard SidebarHierarchySnapshot(state: state, spaceID: source.spaceID,
                  profileID: source.profileID, includesFavorites: source.includesFavorites) == source,
              let sourceSpace = state.spaces.first(where: { $0.id == source.spaceID }),
              !state.spaces.contains(where: { $0.id == spaceID }),
              let roots = items.isEmpty ? [] : SidebarHierarchy.roots(items, state: state, spaceID: source.spaceID),
              roots.allSatisfy({ SidebarHierarchy.location(of: $0, state: state,
                  spaceID: source.spaceID)?.section != .favorite }) else { return nil }
        let insertion = insertion ?? .after(source.spaceID)
        let theme = theme ?? sourceSpace.theme
        guard insertion.index(in: state) != nil, theme.isValid else { return nil }
        self.source = source; self.spaceID = spaceID; self.insertion = insertion
        self.roots = roots; name = ""; profileID = source.profileID
        customIcon = nil; self.theme = theme
        if roots.isEmpty {
            tabIDs = []; folderIDs = []; groupIDs = []
        } else {
            var preview = state
            preview.spaces.append(BrowserSpace(id: spaceID, name: "", symbol: "circle",
                                              color: "B9B5D4", profileID: source.profileID))
            guard let destination = SidebarHierarchySnapshot(state: preview, spaceID: spaceID,
                        profileID: source.profileID),
                  let move = SidebarSpaceMove(items: roots, from: source, to: destination, state: preview) else { return nil }
            tabIDs = move.tabIDs; folderIDs = move.folderIDs; groupIDs = move.groupIDs
        }
    }

    func canUseProfile(_ id: UUID, in state: BrowserState) -> Bool {
        state.profiles.contains { $0.id == id } &&
        !state.profileRemovals.contains { $0.profileID == id } &&
        (roots.isEmpty || id == source.profileID)
    }

    var keepsSeparate: Bool { separateProfileID != nil }
    var movesItemsAcrossProfiles: Bool { !tabIDs.isEmpty && profileID != source.profileID }

    @discardableResult
    mutating func shareData(withSpace id: UUID, in state: BrowserState) -> Bool {
        guard let space = state.spaces.first(where: { $0.id == id }),
              state.profiles.contains(where: { $0.id == space.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == space.profileID }) else { return false }
        separateProfileID = nil; acceptsProfileChange = true; profileID = space.profileID
        return true
    }

    mutating func keepSeparate(profileID id: UUID = UUID()) {
        let id = separateProfileID ?? id
        separateProfileID = id; acceptsProfileChange = true; profileID = id
    }

    private func profileIsUsable(in state: BrowserState) -> Bool {
        if let separateProfileID {
            return profileID == separateProfileID && !state.profiles.contains { $0.id == separateProfileID }
        }
        return state.profiles.contains { $0.id == profileID }
            && !state.profileRemovals.contains { $0.profileID == profileID }
            && (roots.isEmpty || profileID == source.profileID || acceptsProfileChange)
    }

    private func stagedState(in state: BrowserState) -> BrowserState? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !state.spaces.contains(where: { $0.id == spaceID }),
              state.spaces.contains(where: { $0.id == source.spaceID && $0.profileID == source.profileID }),
              state.profiles.contains(where: { $0.id == source.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == source.profileID }),
              profileIsUsable(in: state), !trimmed.isEmpty,
              customIcon?.isValid != false, theme.isValid,
              let index = insertion.index(in: state) else { return nil }
        var next = state
        let hours = state.resolvedAutoArchiveHours(forSpace: source.spaceID)
        if let separateProfileID {
            next.profiles.append(BrowserProfile(id: separateProfileID, name: trimmed, autoArchiveHours: hours))
        }
        var space = BrowserSpace(id: spaceID, name: name, symbol: "circle", color: "B9B5D4", profileID: profileID)
        space.customIcon = customIcon; space.theme = theme; space.autoArchiveHours = hours
        next.spaces.insert(space, at: index)
        for position in next.spaces.indices { next.spaces[position].updateDisplayName(position: position) }
        return next
    }

    func move(in state: BrowserState) -> SidebarSpaceMove? {
        guard !roots.isEmpty, let next = stagedState(in: state),
              let destination = SidebarHierarchySnapshot(state: next, spaceID: spaceID, profileID: profileID),
              let move = SidebarSpaceMove(items: roots, from: source, to: destination, state: next),
              move.roots == roots, move.tabIDs == tabIDs,
              move.folderIDs == folderIDs, move.groupIDs == groupIDs else { return nil }
        return move
    }

    func applying(to state: BrowserState) -> BrowserState? {
        guard let next = stagedState(in: state) else { return nil }
        if roots.isEmpty { return next }
        return move(in: state)?.applying(to: next)
    }
}
