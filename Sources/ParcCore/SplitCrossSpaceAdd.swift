import Foundation

enum SplitCrossSpaceAdd {
    static func relocated(_ state: BrowserState, source: UUID, into spaceID: UUID, profileID: UUID,
                          pane: UUID?, homeID: UUID?, now: Date) -> BrowserState? {
        guard let tab = state.tab(source, where: { $0.archivedAt == nil }),
              tab.profileID == profileID,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { return nil }
        guard tab.kind != .favorite, tab.spaceID != spaceID else { return state }
        let origin = tab.spaceID
        guard state.spaces.contains(where: { $0.id == origin && $0.profileID == profileID }),
              let index = state.tabIndex(source) else { return nil }
        let parents = state.splitLayouts.filter { $0.tabIDs.contains(source) }
        guard parents.count <= 1, parents.allSatisfy({ $0.spaceID == origin }) else { return nil }
        var next = state
        var replacement: UUID?
        if SplitMembership.isSaved(tab) {
            guard let homeID, homeID != source, !state.containsTab(homeID),
                  FolderDuplicateTarget.validSource(tab.savedURL) else { return nil }
            let home = SplitMembership.makeHome(of: tab, id: homeID, now: now, activeTabBeforeCreationID: nil)
            if let parent = parents.first, let stored = next.splitLayouts.firstIndex(where: { $0.id == parent.id }),
               let child = parent.tabIDs.firstIndex(of: source) {
                next.splitLayouts[stored].tabIDs[child] = homeID
                if parent.sidebarAnchorID == source { next.splitLayouts[stored].sidebarAnchorID = homeID }
                next.tabs.append(home)
            } else {
                guard let location = SidebarHierarchy.location(of: .tab(source), state: state, spaceID: origin) else { return nil }
                next.tabs.append(home)
                var items = SidebarHierarchy.children(in: location, state: next).filter { $0 != .tab(homeID) }
                guard let slot = items.firstIndex(of: .tab(source)) else { return nil }
                items[slot] = .tab(homeID)
                next.sidebarItemOrder[location.key] = items.map { stored($0, state: next) }
            }
            for key in Array(next.sidebarItemOrder.keys) {
                next.sidebarItemOrder[key] = next.sidebarItemOrder[key]?.map { $0 == .tab(source) ? .tab(homeID) : $0 }
            }
            replacement = homeID
        } else if let parent = parents.first, let stored = next.splitLayouts.firstIndex(where: { $0.id == parent.id }),
                  let child = parent.tabIDs.firstIndex(of: source) {
            var kept = parent
            kept.tabIDs.remove(at: child); kept.widthFactors.remove(at: child)
            if let factors = BrowserSplitLayout.normalized(kept.widthFactors, count: kept.tabIDs.count) {
                kept.widthFactors = factors
                if kept.sidebarAnchorID.map({ kept.tabIDs.contains($0) }) != true { kept.sidebarAnchorID = kept.tabIDs.first }
                next.splitLayouts[stored] = kept
            } else { next.splitLayouts.remove(at: stored) }
        }
        next.tabs[index].spaceID = spaceID; next.tabs[index].kind = .today; next.tabs[index].folderID = nil
        SplitMembership.preservingSlots(before: state, after: &next)
        for key in next.selectionBySpace.keys where key != spaceID.uuidString {
            guard let selection = next.selectionBySpace[key], selection.contains(source) else { continue }
            let updated = replacement.map { home in selection.map { $0 == source ? home : $0 } } ?? selection.filter { $0 != source }
            next.selectionBySpace[key] = updated.isEmpty ? nil : updated
        }
        let today = SidebarContainerLocation(spaceID: spaceID, folderID: nil, section: .today)
        var items = SidebarHierarchy.children(in: today, state: next).filter { $0 != .tab(source) }
        let paneRoot: SidebarItemReference? = pane.map { id in
            SidebarSplitItems.groups(in: next, spaceID: spaceID).first { $0.tabIDs.contains(id) }.map { .split($0.id) } ?? .tab(id)
        }
        let slot = paneRoot.flatMap { items.firstIndex(of: $0) } ?? 0
        items.insert(.tab(source), at: slot)
        next.sidebarItemOrder[today.key] = items.map { stored($0, state: next) }
        return next
    }

    private static func stored(_ item: SidebarItemReference, state: BrowserState) -> SidebarItemReference {
        if case .split(let id) = item, let anchor = state.splitLayouts.first(where: { $0.id == id })?.sidebarAnchorID { return .tab(anchor) }
        return item
    }
}
