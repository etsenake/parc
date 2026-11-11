import Foundation

enum SplitPaneOperation: Int, CaseIterable {
    case movePrevious, moveNext, addBefore, addAfter, addAbove, addBelow, separate, copyLink, share, flip

    func isEnabled(index: Int, count: Int) -> Bool {
        guard (0..<count).contains(index) else { return false }
        switch self {
        case .movePrevious: return count > 1 && index > 0
        case .moveNext: return count > 1 && index < count - 1
        case .addBefore, .addAfter, .addAbove, .addBelow: return count < 4
        case .separate, .copyLink, .share, .flip: return count > 1
        }
    }
}

struct SplitPaneInsertion: Equatable {
    let spaceID: UUID
    let profileID: UUID
    let selection: [UUID]
    let layout: BrowserSplitLayout?
    let paneID: UUID
    let index: Int
    let orientation: SplitOrientation

    init?(paneID: UUID, operation: SplitPaneOperation, state: BrowserState) {
        let selection = state.selectedTabIDs
        guard let position = selection.firstIndex(of: paneID),
              operation.isEnabled(index: position, count: selection.count),
              let space = state.spaces.first(where: { $0.id == state.activeSpaceID }) else { return nil }
        let layout = SidebarSplitItems.groups(in: state, spaceID: space.id).first { $0.tabIDs == selection }
        guard selection.count == 1 || layout != nil else { return nil }
        switch operation {
        case .addBefore: index = position; orientation = .horizontal
        case .addAfter: index = position + 1; orientation = .horizontal
        case .addAbove: index = position; orientation = .vertical
        case .addBelow: index = position + 1; orientation = .vertical
        default: return nil
        }
        spaceID = space.id; profileID = space.profileID
        self.selection = selection; self.layout = layout; self.paneID = paneID
    }

    func isCurrent(in state: BrowserState) -> Bool {
        state.activeSpaceID == spaceID && state.selectedTabIDs == selection
            && state.spaces.contains { $0.id == spaceID && $0.profileID == profileID }
            && state.profiles.contains { $0.id == profileID }
            && !state.profileRemovals.contains { $0.profileID == profileID }
            && SidebarSplitItems.groups(in: state, spaceID: spaceID).first { $0.tabIDs == selection } == layout
            && selection.allSatisfy { id in state.tabs.contains {
                $0.id == id && $0.archivedAt == nil && $0.profileID == profileID
                    && ($0.spaceID == spaceID || $0.kind == .favorite)
            } }
    }

    var previewFactors: [Double] {
        var factors = layout?.widthFactors ?? [1]
        factors.insert(1 / Double(selection.count), at: index)
        return BrowserSplitLayout.normalized(factors, count: factors.count)!
    }

    func preparedState(_ state: BrowserState, tabID: UUID, navigationURL: URL?,
                       localPage: InternalPage? = nil, localTitle: String? = nil,
                       now: Date, creation: TabCreationProvenance?) -> BrowserState? {
        guard isCurrent(in: state), !selection.contains(tabID) else { return nil }
        let address: String
        let title: String
        if let localPage {
            guard navigationURL == nil, !state.tabs.contains(where: { $0.id == tabID }),
                  !state.tabs.contains(where: {
                      InternalPage(urlString: $0.url) == localPage || InternalPage(urlString: $0.savedURL) == localPage
                  }) else { return nil }
            let name = (localTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            title = name.isEmpty ? localPage.untitledTitle : name
            address = localPage.urlString
        } else if let navigationURL {
            guard navigationURL.scheme != nil, !state.tabs.contains(where: { $0.id == tabID }) else { return nil }
            address = BrowserInternalURL.publicString(navigationURL.absoluteString)
            title = navigationURL.host ?? "New Tab"
        } else {
            return state
        }
        let receipt = creation?.validated(profileID: profileID, state: state)
        var next = state
        next.tabs.append(BrowserTab(id: tabID, spaceID: spaceID, profileID: profileID,
            url: address, title: title, kind: .today, createdAt: now, lastAccessed: now,
            savedURL: address, savedTitle: title, referrerID: receipt?.referrerID,
            activeTabBeforeCreationID: receipt?.activeTabBeforeCreationID))
        SidebarHierarchy.placingCreatedTab(tabID, insertion: .automatic, in: &next)
        return next
    }
}
