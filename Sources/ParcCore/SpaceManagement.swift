import Foundation

package struct SpaceDeletionTarget: Equatable {
    package let space: BrowserSpace
    package let tabs: [BrowserTab]
    package let folders: [BrowserFolder]
    package let groups: [BrowserSplitLayout]
    package let order: [String: [SidebarItemReference]]

    package init?(spaceID: UUID, state: BrowserState) {
        guard state.spaces.count > 1,
              let space = state.spaces.first(where: { $0.id == spaceID }),
              state.profiles.contains(where: { $0.id == space.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == space.profileID }) else { return nil }
        let tabs = state.openTabs(where: { $0.spaceID == spaceID && $0.kind != .favorite })
        guard tabs.allSatisfy({ $0.profileID == space.profileID && FolderDuplicateTarget.validSource($0.savedURL) }) else { return nil }
        let folders = state.folders.filter { $0.spaceID == spaceID }
        let ids = Set(tabs.map(\.id)), folderIDs = Set(folders.map(\.id))
        let groups = state.splitLayouts.filter { $0.spaceID == spaceID && !Self.isProfileFavorite($0, in: state) }
        guard groups.allSatisfy({ Set($0.tabIDs).isSubset(of: ids) }),
              tabs.allSatisfy({ $0.folderID == nil || folderIDs.contains($0.folderID!) }) else { return nil }
        self.space = space; self.tabs = tabs; self.folders = folders; self.groups = groups
        order = state.sidebarItemOrder.filter { $0.key.hasPrefix(spaceID.uuidString + ":") }
    }
    package var tabIDs: Set<UUID> { Set(tabs.map(\.id)) }
    package static func isProfileFavorite(_ group: BrowserSplitLayout, in state: BrowserState) -> Bool {
        guard let first = group.tabIDs.first.flatMap({ id in state.tab(id) }) else { return false }
        return SidebarSplitItems.isFavorite(group, in: state, profileID: first.profileID)
    }
}

package struct SpaceDeletionUndo {
    package let target: SpaceDeletionTarget
    package let index: Int
    package let neighboringSpaces: [UUID]
    package let originals: [BrowserTab]
    package let afterimages: [BrowserTab]
    package let favoriteMoves: [(id: UUID, profile: UUID, before: UUID, after: UUID)]
    package let favoriteGroups: [(before: BrowserSplitLayout, after: BrowserSplitLayout)]
    package let sourceSelection: [UUID]
    package let replacementSpaceID: UUID
    package let documents: [UUID: SidebarDocumentReference]

    @MainActor package var documentsAreAvailable: Bool { SidebarDocumentReference.validates(target.tabs, references: documents) }

    package init(target: SpaceDeletionTarget, index: Int, neighboringSpaces: [UUID], originals: [BrowserTab], afterimages: [BrowserTab], favoriteMoves: [(id: UUID, profile: UUID, before: UUID, after: UUID)], favoriteGroups: [(before: BrowserSplitLayout, after: BrowserSplitLayout)], sourceSelection: [UUID], replacementSpaceID: UUID, documents: [UUID: SidebarDocumentReference]) {
        self.target = target
        self.index = index
        self.neighboringSpaces = neighboringSpaces
        self.originals = originals
        self.afterimages = afterimages
        self.favoriteMoves = favoriteMoves
        self.favoriteGroups = favoriteGroups
        self.sourceSelection = sourceSelection
        self.replacementSpaceID = replacementSpaceID
        self.documents = documents
    }

    package static func make(target: SpaceDeletionTarget, state: BrowserState, now: Date,
                     documents: [UUID: SidebarDocumentReference]) -> (Self, BrowserState)? {
        guard SpaceDeletionTarget(spaceID: target.space.id, state: state) == target,
              let index = state.spaces.firstIndex(where: { $0.id == target.space.id }) else { return nil }
        let remaining = state.spaces.filter { $0.id != target.space.id }
        guard let fallback = remaining.first(where: { $0.profileID == target.space.profileID })
                ?? remaining[safeSpaceIndex: min(index, remaining.count - 1)] else { return nil }
        let ids = target.tabIDs
        var next = state
        var provenance = Dictionary(uniqueKeysWithValues: target.tabs.map {
            ($0.id, ArchiveProvenance(reason: .manual, spaceID: target.space.id, spaceName: target.space.name))
        })
        for group in target.groups {
            let archivedGroup = UUID()
            for id in group.tabIDs { provenance[id]?.groupID = archivedGroup; provenance[id]?.split = group }
        }
        let originals = state.tabs.filter { $0.spaceID == target.space.id && $0.kind != .favorite }
        var moves: [(id: UUID, profile: UUID, before: UUID, after: UUID)] = []
        for i in next.tabs.indices where next.tabs[i].spaceID == target.space.id {
            if next.tabs[i].kind == .favorite {
                moves.append((next.tabs[i].id, next.tabs[i].profileID, target.space.id, fallback.id))
            } else {
                if ids.contains(next.tabs[i].id) {
                    next.tabs[i].archivedAt = now; next.tabs[i].archiveProvenance = provenance[next.tabs[i].id]
                } else if next.tabs[i].archiveProvenance == nil {
                    next.tabs[i].archiveProvenance = ArchiveProvenance(reason: .manual, spaceID: target.space.id, spaceName: target.space.name)
                }
                next.tabs[i].folderID = nil
            }
            next.tabs[i].spaceID = fallback.id
        }
        let removedGroups = Set(target.groups.map(\.id))
        next.splitLayouts.removeAll { removedGroups.contains($0.id) }
        var favoriteGroups: [(before: BrowserSplitLayout, after: BrowserSplitLayout)] = []
        for i in next.splitLayouts.indices where next.splitLayouts[i].spaceID == target.space.id {
            guard SpaceDeletionTarget.isProfileFavorite(next.splitLayouts[i], in: state) else { return nil }
            let before = next.splitLayouts[i]; next.splitLayouts[i].spaceID = fallback.id
            favoriteGroups.append((before, next.splitLayouts[i]))
        }
        next.folders.removeAll { $0.spaceID == target.space.id }
        next.spaces.remove(at: index)
        for i in next.spaces.indices { next.spaces[i].updateDisplayName(position: i) }
        for key in target.order.keys { next.sidebarItemOrder.removeValue(forKey: key) }
        next.selectionBySpace.removeValue(forKey: target.space.id.uuidString)
        for key in next.selectionBySpace.keys { next.selectionBySpace[key]?.removeAll { ids.contains($0) } }
        if next.activeSpaceID == target.space.id {
            next.activeSpaceID = fallback.id
            next.selectedTabIDs = next.selectionBySpace[fallback.id.uuidString] ?? []
        } else { next.selectedTabIDs.removeAll { ids.contains($0) } }
        next.recentlyClosedIDs.removeAll { ids.contains($0) }
        next.recentlyClosedIDs += target.tabs.map(\.id)
        let afterimages = originals.compactMap { original in next.tab(original.id) }
        let undo = Self(target: target, index: index, neighboringSpaces: state.spaces.map(\.id), originals: originals,
            afterimages: afterimages, favoriteMoves: moves, favoriteGroups: favoriteGroups,
            sourceSelection: state.selectionBySpace[target.space.id.uuidString] ?? [], replacementSpaceID: fallback.id, documents: documents)
        return (undo, next)
    }

    package func restoring(in state: BrowserState) -> BrowserState? {
        let space = target.space, ids = target.tabIDs
        guard !state.spaces.contains(where: { $0.id == space.id }),
              state.profiles.contains(where: { $0.id == space.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == space.profileID }),
              target.folders.allSatisfy({ original in !state.folders.contains { $0.id == original.id } }),
              target.groups.allSatisfy({ original in !state.splitLayouts.contains { $0.id == original.id || !$0.tabIDs.allSatisfy { !ids.contains($0) } } }),
              afterimages.count == originals.count,
              afterimages.allSatisfy({ expected in state.tab(expected.id) == expected }),
              favoriteGroups.allSatisfy({ pair in state.splitLayouts.first { $0.id == pair.after.id } == pair.after }),
              target.order.keys.allSatisfy({ state.sidebarItemOrder[$0] == nil }) else { return nil }
        var next = state
        let following = neighboringSpaces.dropFirst(index + 1).first { id in next.spaces.contains { $0.id == id } }
        let position = following.flatMap { id in next.spaces.firstIndex { $0.id == id } } ?? min(index, next.spaces.count)
        next.spaces.insert(space, at: position)
        for i in next.spaces.indices { next.spaces[i].updateDisplayName(position: i) }
        for original in originals {
            guard let i = next.tabIndex(original.id) else { return nil }
            next.tabs[i] = original
        }
        for move in favoriteMoves {
            if let i = next.tabIndex(move.id, where: { $0.profileID == move.profile && $0.kind == .favorite && $0.spaceID == move.after }) {
                next.tabs[i].spaceID = move.before
            }
        }
        for pair in favoriteGroups {
            guard let i = next.splitLayouts.firstIndex(where: { $0.id == pair.after.id }) else { return nil }
            next.splitLayouts[i] = pair.before
        }
        next.folders += target.folders; next.splitLayouts += target.groups
        for (key, items) in target.order { next.sidebarItemOrder[key] = items }
        next.selectionBySpace[space.id.uuidString] = sourceSelection
        next.recentlyClosedIDs.removeAll { ids.contains($0) }
        return next
    }

    package func redoTarget(in state: BrowserState) -> SpaceDeletionTarget? {
        guard let current = SpaceDeletionTarget(spaceID: target.space.id, state: state),
              current.space.profileID == target.space.profileID,
              current.tabIDs == target.tabIDs, current.folders == target.folders,
              current.groups == target.groups, current.order == target.order,
              current.tabs.allSatisfy({ tab in target.tabs.contains { $0.id == tab.id && $0.kind == tab.kind && $0.folderID == tab.folderID } }) else { return nil }
        return current
    }
}

private extension Array {
    subscript(safeSpaceIndex index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

package struct SpaceFolderConversion {
    package let target: SpaceDeletionTarget
    package let destination: SidebarHierarchySnapshot
    package let folderID: UUID
    package let todayFolderID: UUID
    package let documents: [UUID: SidebarDocumentReference]
    package var crossesProfiles: Bool { target.space.profileID != destination.profileID }
    package var tabIDs: Set<UUID> { target.tabIDs }

    package init?(source: UUID, destination: UUID, state: BrowserState,
          documents: [UUID: SidebarDocumentReference], folderID: UUID = UUID(), todayFolderID: UUID = UUID()) {
        guard source != destination, let target = SpaceDeletionTarget(spaceID: source, state: state),
              let space = state.spaces.first(where: { $0.id == destination }),
              let hierarchy = SidebarHierarchySnapshot(state: state, spaceID: destination, profileID: space.profileID),
              folderID != todayFolderID, !state.folders.contains(where: { $0.id == folderID || $0.id == todayFolderID }) else { return nil }
        self.target = target; self.destination = hierarchy; self.folderID = folderID
        self.todayFolderID = todayFolderID; self.documents = documents
    }
    package func applying(to state: BrowserState) -> (BrowserState, SpaceFolderUndo)? {
        guard SpaceDeletionTarget(spaceID: target.space.id, state: state) == target,
              SidebarHierarchySnapshot(state: state, spaceID: destination.spaceID, profileID: destination.profileID) == destination,
              !state.folders.contains(where: { $0.id == folderID || $0.id == todayFolderID }) else { return nil }
        let sourceID = target.space.id, destinationID = destination.spaceID
        let pinned = SidebarContainerLocation(spaceID: sourceID, folderID: nil, section: .pinned)
        let today = SidebarContainerLocation(spaceID: sourceID, folderID: nil, section: .today)
        let pinnedItems = SidebarHierarchy.children(in: pinned, state: state)
        let todayItems = SidebarHierarchy.children(in: today, state: state)
        func stored(_ item: SidebarItemReference) -> SidebarItemReference {
            if case .split(let id) = item, let anchor = target.groups.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
            return item
        }
        var next = state
        let main = BrowserFolder(id: folderID, spaceID: destinationID, name: target.space.name)
        var created = [main]
        if !todayItems.isEmpty { created.append(BrowserFolder(id: todayFolderID, spaceID: destinationID, name: "Today", parentID: folderID, isExpanded: false)) }
        for i in next.tabs.indices where tabIDs.contains(next.tabs[i].id) {
            let wasToday = next.tabs[i].kind == .today && next.tabs[i].folderID == nil
            next.tabs[i].spaceID = destinationID; next.tabs[i].profileID = destination.profileID
            next.tabs[i].folderID = next.tabs[i].folderID ?? (wasToday ? todayFolderID : folderID)
            next.tabs[i].kind = .pinned
        }
        for i in next.folders.indices where next.folders[i].spaceID == sourceID {
            next.folders[i].spaceID = destinationID
            if next.folders[i].parentID == nil { next.folders[i].parentID = folderID }
        }
        let groups = Set(target.groups.map(\.id))
        for i in next.splitLayouts.indices where groups.contains(next.splitLayouts[i].id) { next.splitLayouts[i].spaceID = destinationID }
        next.folders += created
        for folder in target.folders {
            let old = SidebarContainerLocation(spaceID: sourceID, folderID: folder.id, section: .pinned)
            let new = SidebarContainerLocation(spaceID: destinationID, folderID: folder.id, section: .pinned)
            next.sidebarItemOrder[new.key] = SidebarHierarchy.children(in: old, state: state).map(stored)
        }
        let root = SidebarContainerLocation(spaceID: destinationID, folderID: nil, section: .pinned)
        next.sidebarItemOrder[root.key] = SidebarHierarchy.children(in: root, state: state).map(stored) + [.folder(folderID)]
        next.sidebarItemOrder[SidebarContainerLocation(spaceID: destinationID, folderID: folderID, section: .pinned).key]
            = pinnedItems.map(stored) + (todayItems.isEmpty ? [] : [.folder(todayFolderID)])
        if !todayItems.isEmpty {
            next.sidebarItemOrder[SidebarContainerLocation(spaceID: destinationID, folderID: todayFolderID, section: .pinned).key] = todayItems.map(stored)
        }
        guard let shell = SpaceDeletionTarget(spaceID: sourceID, state: next), shell.tabs.isEmpty, shell.folders.isEmpty,
              let (deletion, removed) = SpaceDeletionUndo.make(target: shell, state: next, now: Date(), documents: [:]) else { return nil }
        next = removed
        let movedFolderIDs = Set(target.folders.map(\.id)).union(created.map(\.id))
        let afterFolders = next.folders.filter { movedFolderIDs.contains($0.id) }
        let afterTabs = next.tabs.filter { tabIDs.contains($0.id) }
        let afterGroups = next.splitLayouts.filter { groups.contains($0.id) }
        let keys = Set(movedFolderIDs.map { SidebarContainerLocation(spaceID: destinationID, folderID: $0, section: .pinned).key })
        let orders = next.sidebarItemOrder.filter { keys.contains($0.key) }
        return (next, SpaceFolderUndo(conversion: self, deletion: deletion, afterTabs: afterTabs,
            afterFolders: afterFolders, afterGroups: afterGroups, afterOrders: orders))
    }
}

package struct SpaceFolderUndo {
    package let conversion: SpaceFolderConversion
    package let deletion: SpaceDeletionUndo
    package let afterTabs: [BrowserTab]
    package let afterFolders: [BrowserFolder]
    package let afterGroups: [BrowserSplitLayout]
    package let afterOrders: [String: [SidebarItemReference]]
    @MainActor package var documentsAreAvailable: Bool { SidebarDocumentReference.validates(conversion.target.tabs, references: conversion.documents) }

    package init(conversion: SpaceFolderConversion, deletion: SpaceDeletionUndo, afterTabs: [BrowserTab], afterFolders: [BrowserFolder], afterGroups: [BrowserSplitLayout], afterOrders: [String: [SidebarItemReference]]) {
        self.conversion = conversion
        self.deletion = deletion
        self.afterTabs = afterTabs
        self.afterFolders = afterFolders
        self.afterGroups = afterGroups
        self.afterOrders = afterOrders
    }

    package func redo(in state: BrowserState) -> SpaceFolderConversion? {
        guard let current = SpaceDeletionTarget(spaceID: conversion.target.space.id, state: state),
              current.space.profileID == conversion.target.space.profileID,
              current.tabIDs == conversion.tabIDs, current.folders == conversion.target.folders,
              current.groups == conversion.target.groups, current.order == conversion.target.order,
              current.tabs.allSatisfy({ tab in conversion.target.tabs.contains { $0.id == tab.id && $0.kind == tab.kind && $0.folderID == tab.folderID } }) else { return nil }
        return SpaceFolderConversion(source: current.space.id, destination: conversion.destination.spaceID, state: state,
            documents: conversion.documents, folderID: conversion.folderID, todayFolderID: conversion.todayFolderID)
    }

    package func restoring(in state: BrowserState) -> BrowserState? {
        let target = conversion.target, ids = conversion.tabIDs, folders = Set(afterFolders.map(\.id))
        guard !conversion.crossesProfiles,
              state.spaces.contains(where: { $0.id == conversion.destination.spaceID && $0.profileID == conversion.destination.profileID }),
              afterTabs.allSatisfy({ expected in state.tab(expected.id).map {
                  $0.spaceID == expected.spaceID && $0.profileID == expected.profileID && $0.folderID == expected.folderID
                    && $0.kind == expected.kind && $0.archivedAt == nil
              } == true }),
              state.tabs.filter({ $0.folderID.map(folders.contains) == true }).allSatisfy({ ids.contains($0.id) }),
              afterFolders.allSatisfy({ state.folders.contains($0) }),
              state.folders.filter({ $0.parentID.map(folders.contains) == true }).allSatisfy({ folders.contains($0.id) }),
              afterGroups.allSatisfy({ state.splitLayouts.contains($0) }),
              afterOrders.allSatisfy({ state.sidebarItemOrder[$0.key] == $0.value }),
              var next = deletion.restoring(in: state) else { return nil }
        for original in target.tabs {
            guard let i = next.tabIndex(original.id) else { return nil }
            next.tabs[i].spaceID = original.spaceID; next.tabs[i].profileID = original.profileID
            next.tabs[i].kind = original.kind; next.tabs[i].folderID = original.folderID
        }
        next.folders.removeAll { folders.contains($0.id) }; next.folders += target.folders
        let groups = Set(target.groups.map(\.id))
        next.splitLayouts.removeAll { groups.contains($0.id) }; next.splitLayouts += target.groups
        for key in afterOrders.keys { next.sidebarItemOrder.removeValue(forKey: key) }
        for key in next.sidebarItemOrder.keys { next.sidebarItemOrder[key]?.removeAll { $0 == .folder(conversion.folderID) } }
        for (key, order) in target.order { next.sidebarItemOrder[key] = order }
        return next
    }
}
