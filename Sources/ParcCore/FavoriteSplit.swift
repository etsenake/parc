import Foundation

package enum FavoriteOptionRoute: Equatable {
    case split
    case present
    case paneLimit
    case unchanged

    package init(favoriteID: UUID, selection: [UUID], focusedID: UUID?) {
        guard let focusedID, selection.contains(focusedID) else { self = .present; return }
        if selection.contains(favoriteID) {
            self = favoriteID == focusedID && selection.count >= 4 ? .unchanged : .split
        } else {
            self = selection.count < 4 ? .split : .paneLimit
        }
    }
}

package struct FavoriteSplitRequest {
    package let favorite: BrowserTab
    package let spaceID: UUID
    package let selection: [UUID]
    package let focusedID: UUID
    package let members: [BrowserTab]
    package let layouts: [BrowserSplitLayout]
    package let layout: BrowserSplitLayout?
    package let duplicateURL: String?
    package let duplicateTitle: String?
    package let newID: UUID
    package let homeIDs: [UUID: UUID]

    package init?(favorite: BrowserTab, spaceID: UUID, selection: [UUID], focusedID: UUID,
          state: BrowserState, duplicateURL: String? = nil, duplicateTitle: String? = nil,
          newID: UUID = UUID(), homeIDs: [UUID: UUID] = [:]) {
        guard favorite.kind == .favorite, favorite.archivedAt == nil,
              state.tabs.contains(favorite), !selection.isEmpty,
              Set(selection).count == selection.count, selection.contains(focusedID),
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == favorite.profileID }) else { return nil }
        let members = selection.compactMap { id in state.tab(id, where: { $0.archivedAt == nil
            && $0.profileID == favorite.profileID && ($0.kind == .favorite || $0.spaceID == spaceID) }) }
        let layout = SidebarSplitItems.groups(in: state, spaceID: spaceID).first { $0.tabIDs == selection }
        guard members.count == selection.count, selection.count == 1 || layout != nil,
              (selection.contains(favorite.id) && focusedID != favorite.id) || selection.count < 4 else { return nil }
        if favorite.id == focusedID {
            guard let duplicateURL, let url = URL(string: duplicateURL), url.scheme != nil,
                  !InternalPage.isInternal(duplicateURL), !state.containsTab(newID) else { return nil }
        }
        self.favorite = favorite; self.spaceID = spaceID; self.selection = selection
        self.focusedID = focusedID; self.members = members; self.layout = layout
        layouts = state.splitLayouts
        self.duplicateURL = duplicateURL; self.duplicateTitle = duplicateTitle; self.newID = newID
        self.homeIDs = homeIDs
    }

    package var targetID: UUID { favorite.id == focusedID ? newID : favorite.id }

    package var paneIDs: [UUID] {
        var ids = selection
        if !ids.contains(targetID), let index = ids.firstIndex(of: focusedID) {
            ids.insert(targetID, at: layout?.mainRowInsertionIndex(after: focusedID) ?? index + 1)
        }
        return ids
    }

    package func savedHomeSources(in state: BrowserState) -> [BrowserTab] {
        guard paneIDs != selection else { return [] }
        return SplitMembership.savedHomeSources(joining: paneIDs, existing: layout,
            added: favorite.id == focusedID ? newID : nil, state: state)
    }

    package func applying(to state: BrowserState, retiring: Set<UUID>, now: Date) -> BrowserState? {
        guard state.activeSpaceID == spaceID, state.selectedTabIDs == selection,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == favorite.profileID }),
              state.profiles.contains(where: { $0.id == favorite.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == favorite.profileID }),
              state.tabs.contains(favorite), members.allSatisfy({ state.tabs.contains($0) }),
              retiring.isDisjoint(with: Set(selection + [favorite.id, targetID] + Array(homeIDs.values))),
              state.splitLayouts == layouts else { return nil }
        var next = state
        if favorite.id == focusedID {
            guard let url = duplicateURL, !state.containsTab(newID) else { return nil }
            let away = SavedTabURLComparison.isAway(current: URL(string: url), saved: URL(string: favorite.savedURL))
            let title = away ? (duplicateTitle?.isEmpty == false ? duplicateTitle! : favorite.title) : favorite.savedTitle
            next.tabs.append(BrowserTab(id: newID, spaceID: spaceID, profileID: favorite.profileID,
                url: url, title: title, kind: .today, createdAt: now, lastAccessed: now,
                savedURL: url, savedTitle: title, customTitle: away ? nil : favorite.customTitle))
            SidebarHierarchy.placingCreatedTab(newID, insertion: .automatic, in: &next)
        }
        let ids = paneIDs
        guard ids.count <= 4 else { return nil }
        if ids != selection {
            let weights = ids.map { id in
                layout.flatMap { group in group.tabIDs.firstIndex(of: id).map { group.widthFactors[$0] } }
                    ?? (1 / Double(selection.count))
            }
            guard let factors = BrowserSplitLayout.normalized(weights, count: ids.count) else { return nil }
            var group = BrowserSplitLayout(id: layout?.id ?? UUID(),
                sidebarAnchorID: layout?.sidebarAnchorID, customTitle: layout?.customTitle, customIcon: layout?.customIcon,
                spaceID: layout?.spaceID ?? spaceID, tabIDs: ids, orientation: layout?.orientation ?? .horizontal,
                widthFactors: factors, stacks: nil)
            if let layout { group.restack(from: layout) }
            let homes = savedHomeSources(in: next)
            guard homes.allSatisfy({ homeIDs[$0.id] != nil }),
                  let admitted = SplitMembership.admitting(group, existing: layout,
                      added: favorite.id == focusedID ? newID : nil, state: next, spaceID: spaceID,
                      homeIDs: homeIDs, now: now) else { return nil }
            next = admitted
        }
        next.selectedTabIDs = ids; next.selectionBySpace[spaceID.uuidString] = ids
        if let index = next.tabIndex(targetID) {
            next.tabs[index].lastAccessed = now; next.tabs[index].isUnread = false
        }
        return next
    }
}
