import Foundation

package struct CommandBarFavoriteRenameAction: Equatable, Identifiable {
    package let tab: BrowserTab
    package let spaceID: UUID
    package let profileID: UUID
    package var id: String { "rename-favorite:\(profileID):\(spaceID):\(tab.id):\(tab.createdAt.timeIntervalSinceReferenceDate)" }
    package var title: String { "Rename Current Tab…" }

    package init?(state: BrowserState, spaceID: UUID, profileID: UUID, selectedTabIDs: [UUID]) {
        guard selectedTabIDs.count == 1, let id = selectedTabIDs.first,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              state.profiles.contains(where: { $0.id == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              !state.splitLayouts.contains(where: { $0.tabIDs.contains(id) }),
              let tab = state.tab(id, where: { $0.profileID == profileID
                  && $0.kind == .favorite && $0.archivedAt == nil }) else { return nil }
        self.tab = tab; self.spaceID = spaceID; self.profileID = profileID
    }

    package func currentTab(in state: BrowserState, spaceID: UUID, profileID: UUID,
                    selectedTabIDs: [UUID]) -> BrowserTab? {
        guard self.spaceID == spaceID, self.profileID == profileID,
              let current = Self(state: state, spaceID: spaceID, profileID: profileID,
                                 selectedTabIDs: selectedTabIDs),
              current.tab.createdAt == tab.createdAt,
              SidebarTabTitle.sameItemForEditing(current.tab, tab) else { return nil }
        return current.tab
    }

    package func matches(query: String) -> Bool {
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.allSatisfy { title.lowercased().contains($0) }
    }
}
