import Foundation

enum SplitPaneOperation: Int, CaseIterable {
    case movePrevious, moveNext, addBefore, addAfter, addAbove, addBelow, separate, copyLinks, flip
    case stackBefore, stackAfter, stackPrevious, stackNext

    var addsToStack: Bool { self == .stackBefore || self == .stackAfter }

    func startsSplitView(paneCount: Int, isSplit: Bool) -> Bool {
        self == .stackAfter && paneCount == 1 && !isSplit
    }

    func isEnabled(index: Int, count: Int, layout: BrowserSplitLayout? = nil) -> Bool {
        guard (0..<count).contains(index) else { return false }
        var slot = index, slots = count, place = 0, stack = 1
        if let layout, layout.tabIDs.count == count, let position = layout.position(of: layout.tabIDs[index]) {
            let shape = layout.slots
            slot = position.slot; slots = shape.count
            place = position.index; stack = shape[position.slot].tabIDs.count
        }
        switch self {
        case .movePrevious: return count > 1 && slot > 0
        case .moveNext: return count > 1 && slot < slots - 1
        case .addBefore, .addAfter, .addAbove, .addBelow: return count < 4
        case .stackBefore, .stackAfter: return (2...3).contains(count)
        case .stackPrevious: return stack > 1 && place > 0
        case .stackNext: return stack > 1 && place < stack - 1
        case .separate, .copyLinks, .flip: return count > 1
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
    let target: SplitDropTarget

    init?(paneID: UUID, operation: SplitPaneOperation, state: BrowserState) {
        if operation.addsToStack {
            guard let stacked = SplitPaneInsertion(paneID: paneID, stackingAfter: operation == .stackAfter, state: state) else { return nil }
            self = stacked
            return
        }
        let selection = state.selectedTabIDs
        guard let position = selection.firstIndex(of: paneID),
              operation.isEnabled(index: position, count: selection.count),
              let space = state.spaces.first(where: { $0.id == state.activeSpaceID }) else { return nil }
        let layout = SidebarSplitItems.groups(in: state, spaceID: space.id).first { $0.tabIDs == selection }
        guard selection.count == 1 || layout != nil else { return nil }
        let before: Bool
        switch operation {
        case .addBefore: before = true; orientation = .horizontal
        case .addAfter: before = false; orientation = .horizontal
        case .addAbove: before = true; orientation = .vertical
        case .addBelow: before = false; orientation = .vertical
        default: return nil
        }
        if let layout, layout.stacks != nil, layout.orientation != orientation { return nil }
        let slot = layout?.stacks == nil ? nil : layout?.position(of: paneID).flatMap { layout?.slotRange($0.slot) }
        index = slot.map { before ? $0.lowerBound : $0.upperBound } ?? position + (before ? 0 : 1)
        target = .insert(index)
        spaceID = space.id; profileID = space.profileID
        self.selection = selection; self.layout = layout; self.paneID = paneID
    }

    init?(paneID: UUID, stackingAfter after: Bool, state: BrowserState) {
        let selection = state.selectedTabIDs
        guard let position = selection.firstIndex(of: paneID), (2...3).contains(selection.count),
              let space = state.spaces.first(where: { $0.id == state.activeSpaceID }),
              let layout = SidebarSplitItems.groups(in: state, spaceID: space.id).first(where: { $0.tabIDs == selection })
        else { return nil }
        index = position + (after ? 1 : 0)
        orientation = layout.orientation
        target = .stack(position, after: after)
        spaceID = space.id; profileID = space.profileID
        self.selection = selection; self.layout = layout; self.paneID = paneID
    }

    func isCurrent(in state: BrowserState) -> Bool {
        state.activeSpaceID == spaceID && state.selectedTabIDs == selection
            && state.spaces.contains { $0.id == spaceID && $0.profileID == profileID }
            && state.profiles.contains { $0.id == profileID }
            && !state.profileRemovals.contains { $0.profileID == profileID }
            && SidebarSplitItems.groups(in: state, spaceID: spaceID).first { $0.tabIDs == selection } == layout
            && selection.allSatisfy { id in state.containsTab(id, where: { $0.archivedAt == nil && $0.profileID == profileID
                    && ($0.spaceID == spaceID || $0.kind == .favorite) }) }
    }

    var previewLayout: BrowserSplitLayout? {
        guard let layout, layout.stacks != nil || target.isStack else { return nil }
        return SplitDropTransaction.make(source: UUID(), selection: selection, layout: layout, target: target,
                                         orientation: orientation, spaceID: layout.spaceID)
    }

    var previewFactors: [Double] {
        if let preview = previewLayout { return preview.widthFactors }
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
            guard navigationURL == nil, !state.containsTab(tabID),
                  !state.tabs.contains(where: {
                      InternalPage(urlString: $0.url) == localPage || InternalPage(urlString: $0.savedURL) == localPage
                  }) else { return nil }
            let name = (localTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            title = name.isEmpty ? localPage.untitledTitle : name
            address = localPage.urlString
        } else if let navigationURL {
            guard navigationURL.scheme != nil, !state.containsTab(tabID) else { return nil }
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
