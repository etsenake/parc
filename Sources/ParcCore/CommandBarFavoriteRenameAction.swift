import Foundation

/// Type Travel Rename owns the current original Favorite, not the keyboard
/// highlight or a sidebar multi-selection. The global menu has a separate owner.
struct CommandBarFavoriteRenameAction: Equatable, Identifiable {
    let tab: BrowserTab
    let spaceID: UUID
    let profileID: UUID
    var id: String { "rename-favorite:\(profileID):\(spaceID):\(tab.id):\(tab.createdAt.timeIntervalSinceReferenceDate)" }
    var title: String { "Rename Current Tab…" }

    init?(state: BrowserState, spaceID: UUID, profileID: UUID, selectedTabIDs: [UUID]) {
        guard selectedTabIDs.count == 1, let id = selectedTabIDs.first,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              !state.splitLayouts.contains(where: { $0.tabIDs.contains(id) }),
              let tab = state.tabs.first(where: { $0.id == id && $0.profileID == profileID
                  && $0.kind == .favorite && $0.archivedAt == nil }) else { return nil }
        self.tab = tab; self.spaceID = spaceID; self.profileID = profileID
    }

    func currentTab(in state: BrowserState, spaceID: UUID, profileID: UUID,
                    selectedTabIDs: [UUID]) -> BrowserTab? {
        guard self.spaceID == spaceID, self.profileID == profileID,
              let current = Self(state: state, spaceID: spaceID, profileID: profileID,
                                 selectedTabIDs: selectedTabIDs),
              current.tab.createdAt == tab.createdAt,
              SidebarTabTitle.sameItemForEditing(current.tab, tab) else { return nil }
        return current.tab
    }

    func matches(query: String) -> Bool {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.allSatisfy { title.lowercased().contains($0) }
    }
}
