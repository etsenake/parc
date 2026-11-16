import Foundation

enum OriginalSplitDrop {
    static func savedHomes(source: UUID, state: BrowserState, selection: [UUID],
                           layout: BrowserSplitLayout?, target: SplitDropTarget,
                           orientation: SplitOrientation, spaceID: UUID) -> [BrowserTab]? {
        guard let group = SplitDropTransaction.make(source: source, selection: selection,
            layout: layout, target: target, orientation: orientation, spaceID: layout?.spaceID ?? spaceID) else { return nil }
        return SplitMembership.savedHomeSources(joining: group.tabIDs, existing: layout, added: nil, state: state)
    }

    static func proposal(source: UUID, state: BrowserState, selection: [UUID],
                         layout: BrowserSplitLayout?, target: SplitDropTarget,
                         orientation: SplitOrientation, spaceID: UUID, profileID: UUID,
                         now: Date, savedHomeIDs: [UUID: UUID],
                         creation: TabCreationProvenance?) -> BrowserState? {
        guard state.activeSpaceID == spaceID, state.selectedTabIDs == selection,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              SidebarHierarchySnapshot(state: state, spaceID: spaceID, profileID: profileID, includesFavorites: true) != nil,
              state.containsTab(source, where: { $0.archivedAt == nil && $0.profileID == profileID
                  && ($0.kind == .favorite || $0.spaceID == spaceID) }) else { return nil }
        let originals = selection.compactMap { id in state.tab(id, where: { $0.archivedAt == nil
            && $0.profileID == profileID && ($0.kind == .favorite || $0.spaceID == spaceID) }) }
        let actual = SidebarSplitItems.groups(in: state, spaceID: spaceID).first { $0.tabIDs == selection }
        guard originals.count == selection.count, actual == layout,
              layout != nil || !state.splitLayouts.contains(where: { !$0.tabIDs.allSatisfy { !selection.contains($0) } }),
              let group = SplitDropTransaction.make(source: source, selection: selection, layout: layout,
                  target: target, orientation: orientation, spaceID: layout?.spaceID ?? spaceID) else { return nil }
        let receipt = creation?.validated(profileID: profileID, state: state)
        guard var next = SplitMembership.admitting(group, existing: layout, added: nil, state: state,
            spaceID: spaceID, homeIDs: savedHomeIDs, now: now,
            activeTabBeforeCreationID: receipt?.activeTabBeforeCreationID) else { return nil }
        next.selectedTabIDs = group.tabIDs; next.selectionBySpace[spaceID.uuidString] = group.tabIDs
        for index in next.tabs.indices where group.tabIDs.contains(next.tabs[index].id) {
            next.tabs[index].lastAccessed = now; next.tabs[index].isUnread = false
        }
        return next
    }
}

enum SplitMembership {
    static func isSaved(_ tab: BrowserTab) -> Bool { tab.kind == .pinned || tab.kind == .favorite }

    static func container(of group: BrowserSplitLayout, in state: BrowserState) -> SidebarContainerLocation? {
        guard let anchorID = group.sidebarAnchorID ?? group.tabIDs.first, group.tabIDs.contains(anchorID),
              let anchor = state.tab(anchorID, where: { $0.archivedAt == nil }) else { return nil }
        return placement(of: anchor, groupSpaceID: group.spaceID)
    }

    static func placement(of tab: BrowserTab, groupSpaceID: UUID) -> SidebarContainerLocation {
        if tab.kind == .favorite {
            return .init(spaceID: groupSpaceID, folderID: nil, section: .favorite, profileID: tab.profileID)
        }
        return .init(spaceID: tab.spaceID, folderID: tab.folderID, section: tab.folderID == nil ? tab.kind : .pinned)
    }

    static func conforms(_ tab: BrowserTab, to container: SidebarContainerLocation) -> Bool {
        guard tab.archivedAt == nil else { return false }
        if container.section == .favorite {
            return tab.kind == .favorite && tab.folderID == nil && tab.profileID == container.profileID
        }
        return tab.kind != .favorite && tab.spaceID == container.spaceID && tab.folderID == container.folderID
            && tab.kind == (container.folderID == nil ? container.section : .pinned)
    }

    static func convert(_ tab: inout BrowserTab, to container: SidebarContainerLocation) {
        if container.section == .favorite {
            tab.kind = .favorite; tab.folderID = nil; tab.spaceID = container.spaceID
        } else {
            tab.kind = container.folderID == nil ? container.section : .pinned
            tab.folderID = container.folderID; tab.spaceID = container.spaceID
        }
    }

    static func savedHomeSources(joining ids: [UUID], existing: BrowserSplitLayout?, added: UUID?,
                                 state: BrowserState) -> [BrowserTab] {
        guard ids.count > 1 else { return [] }
        let kept = Set(existing?.tabIDs ?? [])
        return ids.compactMap { id in
            guard !kept.contains(id), id != added else { return nil }
            return state.tab(id, where: { $0.archivedAt == nil && isSaved($0) })
        }
    }

    @MainActor static func homePlan(_ homes: [BrowserTab],
                                    resolve: ([BrowserTab]) -> [UUID: SidebarDocumentReference]?)
        -> (ids: [UUID: UUID], documents: [UUID: SidebarDocumentReference])? {
        let ids = Dictionary(uniqueKeysWithValues: homes.map { ($0.id, UUID()) })
        let typed = homes.filter { InternalPage(urlString: $0.savedURL) != nil }
        let documents = typed.isEmpty ? [:] : resolve(typed) ?? [:]
        guard SidebarDocumentReference.validates(homes, references: documents) else { return nil }
        return (ids, documents)
    }

    static func makeHome(of original: BrowserTab, id: UUID, now: Date, activeTabBeforeCreationID: UUID?) -> BrowserTab {
        var home = original
        home.id = id; home.url = original.savedURL; home.title = original.savedTitle
        home.createdAt = now; home.lastAccessed = now; home.isUnread = false
        home.referrerID = nil; home.activeTabBeforeCreationID = activeTabBeforeCreationID
        home.archiveProvenance = nil
        return home
    }

    static func admitting(_ group: BrowserSplitLayout, existing: BrowserSplitLayout?, added: UUID?,
                          state: BrowserState, spaceID: UUID, homeIDs: [UUID: UUID], now: Date,
                          activeTabBeforeCreationID: UUID? = nil) -> BrowserState? {
        let ids = group.tabIDs
        guard (1...4).contains(ids.count), Set(ids).count == ids.count,
              let space = state.spaces.first(where: { $0.id == spaceID }),
              ids.allSatisfy({ id in state.containsTab(id, where: { $0.archivedAt == nil
                  && $0.profileID == space.profileID && ($0.kind == .favorite || $0.spaceID == spaceID) }) }) else { return nil }
        let visible = SidebarSplitItems.groups(in: state, spaceID: spaceID)
        let target: SidebarContainerLocation
        if let existing {
            guard existing.id == group.id, visible.contains(existing),
                  let found = container(of: existing, in: state),
                  existing.tabIDs.allSatisfy({ id in state.tab(id).map { conforms($0, to: found) } ?? false })
            else { return nil }
            guard found.folderID.map({ id in state.folders.contains { $0.id == id && $0.spaceID == found.spaceID } }) ?? true
            else { return nil }
            target = found
        } else {
            target = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .today)
        }
        let joining = ids.filter { !(existing?.tabIDs.contains($0) ?? false) }
        let homes = savedHomeSources(joining: ids, existing: existing, added: added, state: state)
        let newIDs = homes.compactMap { homeIDs[$0.id] }
        guard newIDs.count == homes.count, Set(newIDs).count == newIDs.count,
              newIDs.allSatisfy({ id in !ids.contains(id) && !state.containsTab(id) }) else { return nil }
        for id in joining {
            let parents = state.splitLayouts.filter { $0.id != existing?.id && $0.tabIDs.contains(id) }
            guard parents.count <= 1, parents.allSatisfy({ visible.contains($0) }) else { return nil }
        }
        let ordinary = existing == nil ? ids.first { id in
            state.containsTab(id, where: { $0.kind == .today && $0.folderID == nil && $0.spaceID == spaceID })
                && !state.splitLayouts.contains { $0.tabIDs.contains(id) }
        } : nil
        var next = state
        for source in homes {
            guard FolderDuplicateTarget.validSource(source.savedURL), let homeID = homeIDs[source.id] else { return nil }
            let home = makeHome(of: source, id: homeID, now: now, activeTabBeforeCreationID: activeTabBeforeCreationID)
            if let parent = next.splitLayouts.firstIndex(where: { $0.id != existing?.id && $0.tabIDs.contains(source.id) }) {
                let child = next.splitLayouts[parent].tabIDs.firstIndex(of: source.id)!
                next.splitLayouts[parent].tabIDs[child] = homeID
                if next.splitLayouts[parent].sidebarAnchorID == source.id { next.splitLayouts[parent].sidebarAnchorID = homeID }
                next.tabs.append(home)
            } else {
                guard let location = SidebarHierarchy.location(of: .tab(source.id), state: next, spaceID: spaceID),
                      location.folderID.map({ id in next.folders.contains { $0.id == id && $0.spaceID == location.spaceID } }) ?? true
                else { return nil }
                next.tabs.append(home)
                var items = SidebarHierarchy.children(in: location, state: next).filter { $0 != .tab(homeID) }
                guard let slot = items.firstIndex(of: .tab(source.id)) else { return nil }
                items[slot] = .tab(homeID)
                next.sidebarItemOrder[location.key] = items.map { stored($0, state: next) }
            }
            for key in Array(next.sidebarItemOrder.keys) {
                next.sidebarItemOrder[key] = next.sidebarItemOrder[key]?.map { $0 == .tab(source.id) ? .tab(homeID) : $0 }
            }
            for key in Array(next.selectionBySpace.keys) where key != spaceID.uuidString {
                next.selectionBySpace[key] = next.selectionBySpace[key]?.map { $0 == source.id ? homeID : $0 }
            }
        }
        next.splitLayouts = next.splitLayouts.compactMap { old in
            guard old.id != existing?.id, old.tabIDs.contains(where: { joining.contains($0) }) else { return old }
            var kept = old
            for index in kept.tabIDs.indices.reversed() where joining.contains(kept.tabIDs[index]) {
                kept.tabIDs.remove(at: index); kept.widthFactors.remove(at: index)
            }
            guard let factors = BrowserSplitLayout.normalized(kept.widthFactors, count: kept.tabIDs.count) else { return nil }
            kept.widthFactors = factors
            if kept.sidebarAnchorID.map({ kept.tabIDs.contains($0) }) != true { kept.sidebarAnchorID = kept.tabIDs.first }
            return kept
        }
        if ids.count > 1 {
            for id in joining {
                guard let index = next.tabIndex(id) else { return nil }
                convert(&next.tabs[index], to: target)
            }
            var result = group
            if let existing {
                result.spaceID = existing.spaceID
                result.sidebarAnchorID = existing.sidebarAnchorID.flatMap { ids.contains($0) ? $0 : nil }
                    ?? ids.first { existing.tabIDs.contains($0) } ?? ids.first
            } else {
                result.spaceID = spaceID
                result.sidebarAnchorID = ordinary ?? ids.first
            }
            next.splitLayouts.removeAll { $0.id == result.id }
            next.splitLayouts.append(result)
            preservingSlots(before: state, after: &next)
            if existing == nil && ordinary == nil {
                place([.split(result.id)], atSlotOf: nil, in: target, before: state, after: &next)
            }
        } else {
            if let existing { next.splitLayouts.removeAll { $0.id == existing.id } }
            preservingSlots(before: state, after: &next)
        }
        let tray = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .favorite, profileID: space.profileID)
        let roots = SidebarHierarchy.children(in: tray, state: next).count
        guard roots <= 12 || roots <= SidebarHierarchy.children(in: tray, state: state).count else { return nil }
        return next
    }

    static func preservingSlots(before: BrowserState, after next: inout BrowserState) {
        for old in before.splitLayouts where old.tabIDs.count > 1 {
            let current = next.splitLayouts.first { $0.id == old.id }
            if current == old { continue }
            guard let holder = container(of: old, in: before),
                  SidebarHierarchy.children(in: holder, state: before).contains(.split(old.id)) else { continue }
            let survives: Bool
            if let current, current.tabIDs.count > 1 {
                guard container(of: current, in: next) == holder else { continue }
                survives = true
            } else { survives = false }
            let leaving = old.tabIDs.filter { !(current?.tabIDs.contains($0) ?? false) }
            let items: [SidebarItemReference] = survives ? [.split(old.id)] + leaving.map { .tab($0) } : old.tabIDs.map { .tab($0) }
            place(items, atSlotOf: .split(old.id), in: holder, before: before, after: &next)
        }
    }

    static func place(_ items: [SidebarItemReference], atSlotOf slot: SidebarItemReference?,
                      in container: SidebarContainerLocation, before: BrowserState, after next: inout BrowserState) {
        let current = SidebarHierarchy.children(in: container, state: next)
        let moving = items.filter { current.contains($0) }
        guard !moving.isEmpty else { return }
        var result = current.filter { !moving.contains($0) }
        var index = 0
        if let slot {
            let old = SidebarHierarchy.children(in: container, state: before)
            guard let position = old.firstIndex(of: slot) else { return }
            if let previous = old[..<position].reversed().first(where: { result.contains($0) }),
               let found = result.firstIndex(of: previous) { index = found + 1 }
        }
        result.insert(contentsOf: moving, at: index)
        next.sidebarItemOrder[container.key] = result.map { stored($0, state: next) }
    }

    static func normalizingLegacyContainers(_ state: BrowserState, now: Date) -> BrowserState {
        var next = state
        for group in state.splitLayouts where group.tabIDs.count > 1 {
            guard let target = container(of: group, in: next) else { continue }
            for id in group.tabIDs {
                guard let index = next.tabIndex(id),
                      next.tabs[index].archivedAt == nil, !conforms(next.tabs[index], to: target) else { continue }
                let original = next.tabs[index]
                if isSaved(original) {
                    let home = makeHome(of: original, id: UUID(), now: now, activeTabBeforeCreationID: nil)
                    next.tabs.append(home)
                    let own = placement(of: original, groupSpaceID: group.spaceID)
                    if let slot = next.sidebarItemOrder[own.key]?.firstIndex(of: .tab(id)) {
                        next.sidebarItemOrder[own.key]?[slot] = .tab(home.id)
                    }
                    if original.kind == .favorite && target.section != .favorite {
                        for key in Array(next.selectionBySpace.keys) where key != target.spaceID.uuidString {
                            next.selectionBySpace[key] = next.selectionBySpace[key]?.map { $0 == id ? home.id : $0 }
                        }
                        if next.activeSpaceID != target.spaceID {
                            next.selectedTabIDs = next.selectedTabIDs.map { $0 == id ? home.id : $0 }
                        }
                    }
                }
                convert(&next.tabs[index], to: target)
            }
        }
        return next
    }

    static func resolvingSharedLegacyFavorites(_ state: BrowserState) -> BrowserState {
        var next = state
        let favorites = state.openTabs(where: { $0.kind == .favorite }).map(\.id)
        let visible = SidebarSplitItems.groups(in: state, spaceID: state.activeSpaceID).map(\.id)
        for favorite in favorites {
            let holders = next.splitLayouts.indices.filter { next.splitLayouts[$0].tabIDs.contains(favorite) }
            guard holders.count > 1 else { continue }
            func rank(_ index: Int) -> (Int, Int, Int) {
                let group = next.splitLayouts[index]
                return (container(of: group, in: next)?.section == .favorite ? 1 : 0,
                        group.tabIDs == state.selectedTabIDs && visible.contains(group.id) ? 1 : 0, index)
            }
            guard let winner = holders.max(by: { rank($0) < rank($1) }) else { continue }
            for index in holders where index != winner {
                guard let position = next.splitLayouts[index].tabIDs.firstIndex(of: favorite) else { continue }
                next.splitLayouts[index].tabIDs.remove(at: position)
                next.splitLayouts[index].widthFactors.remove(at: position)
                if next.splitLayouts[index].sidebarAnchorID == favorite {
                    next.splitLayouts[index].sidebarAnchorID = next.splitLayouts[index].tabIDs.first
                }
            }
        }
        return next
    }

    private static func stored(_ item: SidebarItemReference, state: BrowserState) -> SidebarItemReference {
        if case .split(let id) = item, let anchor = state.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
        return item
    }
}
