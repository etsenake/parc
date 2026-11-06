import Foundation

///
/// Favorite is duplicated only while a presentation has fewer than four panes
///
/// the focused pane (disposition `0x43`), whose presentation mutation refuses a
/// fifth pane.
enum FavoriteOptionRoute: Equatable {
    /// Insert after the focused pane, focus an existing pane or duplicate the focused Favorite.
    case split
    /// No current presentation or focused pane: selection presents the Favorite itself.
    case present
    /// A fifth pane is refused and reported.
    case paneLimit
    /// The focused Favorite at capacity stays focused; nothing is duplicated.
    case unchanged

    init(favoriteID: UUID, selection: [UUID], focusedID: UUID?) {
        guard let focusedID, selection.contains(focusedID) else { self = .present; return }
        if selection.contains(favoriteID) {
            self = favoriteID == focusedID && selection.count >= 4 ? .unchanged : .split
        } else {
            self = selection.count < 4 ? .split : .paneLimit
        }
    }
}

/// One original App Tray release. Native owners retain live pages separately.
/// The release enters item selection with disposition `0x43` and selection
///
///
/// saved member, the released Favorite included, into its own slot and moves
/// the original into the split (`SplitMembership`). A focused Favorite's
///
///
struct FavoriteSplitRequest {
    let favorite: BrowserTab
    let spaceID: UUID
    let selection: [UUID]
    let focusedID: UUID
    let members: [BrowserTab]
    let layouts: [BrowserSplitLayout]
    let layout: BrowserSplitLayout?
    let duplicateURL: String?
    let duplicateTitle: String?
    let newID: UUID
    let homeIDs: [UUID: UUID]

    init?(favorite: BrowserTab, spaceID: UUID, selection: [UUID], focusedID: UUID,
          state: BrowserState, duplicateURL: String? = nil, duplicateTitle: String? = nil,
          newID: UUID = UUID(), homeIDs: [UUID: UUID] = [:]) {
        guard favorite.kind == .favorite, favorite.archivedAt == nil,
              state.tabs.contains(favorite), !selection.isEmpty,
              Set(selection).count == selection.count, selection.contains(focusedID),
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == favorite.profileID }) else { return nil }
        let members = selection.compactMap { id in state.tabs.first { $0.id == id && $0.archivedAt == nil
            && $0.profileID == favorite.profileID && ($0.kind == .favorite || $0.spaceID == spaceID) } }
        let layout = SidebarSplitItems.groups(in: state, spaceID: spaceID).first { $0.tabIDs == selection }
        guard members.count == selection.count, selection.count == 1 || layout != nil,
              (selection.contains(favorite.id) && focusedID != favorite.id) || selection.count < 4 else { return nil }
        if favorite.id == focusedID {
            guard let duplicateURL, let url = URL(string: duplicateURL), url.scheme != nil,
                  !InternalPage.isInternal(duplicateURL), !state.tabs.contains(where: { $0.id == newID }) else { return nil }
        }
        self.favorite = favorite; self.spaceID = spaceID; self.selection = selection
        self.focusedID = focusedID; self.members = members; self.layout = layout
        layouts = state.splitLayouts
        self.duplicateURL = duplicateURL; self.duplicateTitle = duplicateTitle; self.newID = newID
        self.homeIDs = homeIDs
    }

    var targetID: UUID { favorite.id == focusedID ? newID : favorite.id }

    /// The panes after the release: the target follows the focused pane.
    var paneIDs: [UUID] {
        var ids = selection
        if !ids.contains(targetID), let index = ids.firstIndex(of: focusedID) { ids.insert(targetID, at: index + 1) }
        return ids
    }

    /// Saved members that will need a fresh home, for the caller's fixed IDs
    /// and typed-document validation.
    func savedHomeSources(in state: BrowserState) -> [BrowserTab] {
        guard paneIDs != selection else { return [] }
        return SplitMembership.savedHomeSources(joining: paneIDs, existing: layout,
            added: favorite.id == focusedID ? newID : nil, state: state)
    }

    func applying(to state: BrowserState, retiring: Set<UUID>, now: Date) -> BrowserState? {
        guard state.activeSpaceID == spaceID, state.selectedTabIDs == selection,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == favorite.profileID }),
              state.profiles.contains(where: { $0.id == favorite.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == favorite.profileID }),
              state.tabs.contains(favorite), members.allSatisfy({ state.tabs.contains($0) }),
              retiring.isDisjoint(with: Set(selection + [favorite.id, targetID] + Array(homeIDs.values))),
              state.splitLayouts == layouts else { return nil }
        var next = state
        if favorite.id == focusedID {
            guard let url = duplicateURL, !state.tabs.contains(where: { $0.id == newID }) else { return nil }
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
            // Original page identity is unchanged. The displayed split keeps
            // its container; a new presentation becomes a Today split.
            let weights = ids.map { id in
                layout.flatMap { group in group.tabIDs.firstIndex(of: id).map { group.widthFactors[$0] } }
                    ?? (1 / Double(selection.count))
            }
            guard let factors = BrowserSplitLayout.normalized(weights, count: ids.count) else { return nil }
            let group = BrowserSplitLayout(id: layout?.id ?? UUID(),
                sidebarAnchorID: layout?.sidebarAnchorID, customTitle: layout?.customTitle, customIcon: layout?.customIcon,
                spaceID: layout?.spaceID ?? spaceID, tabIDs: ids, orientation: layout?.orientation ?? .horizontal,
                widthFactors: factors)
            let homes = savedHomeSources(in: next)
            guard homes.allSatisfy({ homeIDs[$0.id] != nil }),
                  let admitted = SplitMembership.admitting(group, existing: layout,
                      added: favorite.id == focusedID ? newID : nil, state: next, spaceID: spaceID,
                      homeIDs: homeIDs, now: now) else { return nil }
            next = admitted
        }
        next.selectedTabIDs = ids; next.selectionBySpace[spaceID.uuidString] = ids
        // Only the destination gains focus.
        if let index = next.tabs.firstIndex(where: { $0.id == targetID }) {
            next.tabs[index].lastAccessed = now; next.tabs[index].isUnread = false
        }
        return next
    }
}
