import AppKit
import Combine

extension BrowserWindowController {
    func wirePinnedSection() -> AnyCancellable {
        sidebar.onSetPinnedSection = { [weak self] spaceID, collapsed in
            self?.setPinnedSection(spaceID: spaceID, collapsed: collapsed)
        }
        sidebar.onSetCollapsedPinnedIcons = PinnedSectionPreferences.shared.loadError ? nil : { shows in
            try? PinnedSectionPreferences.shared.setShowsCollapsedIcons(shows)
        }
        sidebar.showsCollapsedPinnedIcons = PinnedSectionPreferences.shared.state.showsCollapsedIcons
        return PinnedSectionPreferences.shared.$state.dropFirst().sink { [weak self] state in
            guard let self, self.sidebar.showsCollapsedPinnedIcons != state.showsCollapsedIcons else { return }
            self.sidebar.showsCollapsedPinnedIcons = state.showsCollapsedIcons
            guard !self.isClosing else { return }
            self.render(self.store.state)
            self.refreshSidebarPointer()
        }
    }

    var pinnedSectionCommandAvailable: Bool {
        !isPopupWindow && !isPrivateBrowsing && spaceCommandsAvailable && activePeek == nil && libraryView == nil
            && PinnedSectionCollapse.hasItems(state: store.state, spaceID: activeSpaceID)
    }

    var pinnedSectionCollapsed: Bool { PinnedSectionCollapse.isFolded(state: store.state, spaceID: activeSpaceID) }

    var pinnedKeyboardPeek: [SidebarItemReference]? {
        guard pinnedSectionCollapsed else { return nil }
        return PinnedSectionCollapse.peek(state: store.state, spaceID: activeSpaceID,
            active: PinnedSectionCollapse.activeItem(state: store.state, spaceID: activeSpaceID, tabID: currentTabID ?? selectedTabIDs.first))
    }

    func togglePinnedSection() {
        guard pinnedSectionCommandAvailable else { return }
        setPinnedSection(spaceID: activeSpaceID, collapsed: !pinnedSectionCollapsed)
    }

    func clearEmptyPinnedFolds(_ state: BrowserState) {
        guard !isPopupWindow, !isPrivateBrowsing, state.spaces.contains(where: {
            $0.pinnedCollapsed && !PinnedSectionCollapse.hasItems(state: state, spaceID: $0.id)
        }) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isClosing else { return }
            self.store.clearEmptyPinnedFolds()
        }
    }

    func setPinnedSection(spaceID: UUID, collapsed: Bool) {
        guard !isPopupWindow, !isPrivateBrowsing, !isClosing else { return }
        do { try store.setPinnedSectionCollapsed(collapsed, spaceID: spaceID) }
        catch { showError(error) }
    }
}
