import Foundation

// Session metadata is shared. Presentation belongs to one physical NSWindow;
// a store publication is never an instruction to adopt another window's page.
struct WindowPresentation {
    private(set) var activeSpaceID: UUID
    private(set) var selectedTabIDs: [UUID]
    private(set) var isReady: Bool
    private var selectionBySpace: [String: [UUID]]
    //
    // with the physical window's presentation, never in another window's
    // published selection or in a delayed renderer-focus callback.
    private var focusedTabBySpace: [UUID: UUID] = [:]
    private var splitLayoutBySpace: [UUID: BrowserSplitLayout] = [:]

    //
    // records and the currently loaded native pages. It is not restored from
    // the app's durable selected-tab list.
    private(set) var referrerPool: Set<UUID> = []
    private var poolFocusedID: UUID?
    private(set) var previouslySelectedItemID: UUID?

    mutating func recordCreation(_ id: UUID, state: BrowserState) {
        guard let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }) else { return }
        if let referrer = tab.referrerID {
            referrerPool.formUnion([referrer, id])
        } else if let previous = tab.activeTabBeforeCreationID {
            referrerPool = [previous, id]
        }
    }

    // Modal expansion/add-to-split replaces the pool, unlike ordinary creation
    // with an explicit referrer, which unions its pair into the existing Set.
    // Call only after the original Peek page has acquired its saved-item owner.
    @discardableResult
    mutating func recordPeekPromotion(_ id: UUID, state: BrowserState) -> Bool {
        guard let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
              state.spaces.contains(where: { $0.id == activeSpaceID && $0.profileID == tab.profileID }),
              state.spaces.contains(where: { $0.id == tab.spaceID && $0.profileID == tab.profileID }) else { return false }
        var replacement: Set<UUID> = [id]
        if let source = tab.referrerID {
            guard source != id, state.tabs.contains(where: {
                $0.id == source && $0.archivedAt == nil && $0.profileID == tab.profileID
            }) else { return false }
            replacement.insert(source)
        }
        referrerPool = replacement
        return true
    }

    mutating func recordSelectionForReturn(_ id: UUID?, state: BrowserState) {
        // Refreshes and renderer focus acknowledgments are not new selections.
        guard id != poolFocusedID else { return }
        if let id, !state.tabs.contains(where: { $0.id == id && $0.archivedAt == nil }) { return }
        let outgoing = poolFocusedID
        poolFocusedID = id
        guard let id else { return }
        // WindowState.previouslySelectedItem is the outgoing original item,
        // assigned only when selection actually changes to an existing item.
        // A missing outgoing selection clears it; refreshes preserve it.
        previouslySelectedItemID = outgoing
        guard referrerPool.contains(id) else { referrerPool.removeAll(); return }
        // SidebarItemContextType is recursive container context: topApp=0,
        // pinned=1, unpinned=2, missing=3. Only the first two collapse the Set.
        if let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
           tab.kind != .today { referrerPool = [id] }
    }

    struct SessionSelection: Equatable {
        let spaceID: UUID
        let isReady: Bool
        let tabIDs: [UUID]
        let focusedTabID: UUID?
    }

    var sessionSelection: SessionSelection {
        SessionSelection(spaceID: activeSpaceID, isReady: isReady, tabIDs: selectedTabIDs, focusedTabID: preferredFocusedTabID)
    }

    var preferredFocusedTabID: UUID? {
        focusedTabBySpace[activeSpaceID].flatMap { selectedTabIDs.contains($0) ? $0 : nil }
            ?? selectedTabIDs.first
    }

    mutating func recordFocusedTab(_ id: UUID?) {
        guard isReady else { return }
        guard let id else { focusedTabBySpace.removeValue(forKey: activeSpaceID); return }
        guard selectedTabIDs.contains(id) else { return }
        focusedTabBySpace[activeSpaceID] = id
    }

    // If a remembered pane is no longer available to this window, the
    // surviving panes retain their original orientation and relative sizes.
    var splitLayout: BrowserSplitLayout? {
        guard selectedTabIDs.count > 1, let layout = splitLayoutBySpace[activeSpaceID] else { return nil }
        let positions = layout.tabIDs.indices.filter { selectedTabIDs.contains(layout.tabIDs[$0]) }
        guard positions.map({ layout.tabIDs[$0] }) == selectedTabIDs,
              let factors = BrowserSplitLayout.normalized(positions.map({ layout.widthFactors[$0] }),
                                                          count: selectedTabIDs.count) else { return nil }
        return BrowserSplitLayout(id: layout.id, sidebarAnchorID: layout.sidebarAnchorID, customTitle: layout.customTitle, customIcon: layout.customIcon, spaceID: activeSpaceID, tabIDs: selectedTabIDs,
                                  orientation: layout.orientation, widthFactors: factors)
    }

    private mutating func rememberSplitLayout(_ state: BrowserState) {
        guard let layout = SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).first(where: {
            $0.tabIDs == selectedTabIDs
        }), BrowserSplitLayout.normalized(layout.widthFactors, count: layout.tabIDs.count) != nil else { return }
        splitLayoutBySpace[activeSpaceID] = layout
    }

    init(state: BrowserState, ready: Bool, preferredProfileID: UUID? = nil,
         restoredRecord: BrowserWindowRecord? = nil) {
        let preferred = preferredProfileID.flatMap { profile in
            state.spaces.first { $0.id == state.activeSpaceID && $0.profileID == profile }
                ?? state.spaces.first { $0.profileID == profile }
        }
        activeSpaceID = preferred?.id ?? state.activeSpaceID
        isReady = ready
        selectionBySpace = ready ? state.selectionBySpace : [:]
        selectedTabIDs = ready
            ? (activeSpaceID == state.activeSpaceID ? state.selectedTabIDs : selectionBySpace[activeSpaceID.uuidString] ?? [])
            : []
        if ready, let record = restoredRecord, record.focusedSpaceID != nil || record.selectedTabIDs != nil {
            selectionBySpace = [:]
            if let savedSpace = record.focusedSpaceID, state.spaces.contains(where: { $0.id == savedSpace }) {
                activeSpaceID = savedSpace
                selectedTabIDs = record.selectedTabIDs ?? []
            } else if let fallback = state.spaces.first {
                activeSpaceID = fallback.id
                selectedTabIDs = []
            }
            selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
        }
        let focus = restoredRecord?.focusedTabID.flatMap { selectedTabIDs.contains($0) ? $0 : nil } ?? selectedTabIDs.first
        if let focus { focusedTabBySpace[activeSpaceID] = focus }
        poolFocusedID = focus
        for layout in state.splitLayouts where layout.tabIDs == selectionBySpace[layout.spaceID.uuidString]
            && BrowserSplitLayout.normalized(layout.widthFactors, count: layout.tabIDs.count) != nil {
            splitLayoutBySpace[layout.spaceID] = layout
        }
        rememberSplitLayout(state)
    }

    func projected(_ state: BrowserState) -> BrowserState {
        var result = state
        result.activeSpaceID = activeSpaceID
        result.selectedTabIDs = isReady ? selectedTabIDs : []
        result.selectionBySpace = selectionBySpace
        result.selectionBySpace[activeSpaceID.uuidString] = result.selectedTabIDs
        return result
    }

    mutating func reconcile(_ state: BrowserState, available: (UUID) -> Bool) {
        let spaceIDs = Set(state.spaces.map(\.id))
        focusedTabBySpace = focusedTabBySpace.filter { spaceIDs.contains($0.key) }
        splitLayoutBySpace = splitLayoutBySpace.filter { spaceIDs.contains($0.key) }
        selectionBySpace = selectionBySpace.filter { key, _ in UUID(uuidString: key).map(spaceIDs.contains) == true }
        rememberSplitLayout(state)
        if !state.spaces.contains(where: { $0.id == activeSpaceID }), let first = state.spaces.first {
            activeSpaceID = first.id
            selectedTabIDs = []
        }
        guard isReady, let space = state.spaces.first(where: { $0.id == activeSpaceID }) else {
            selectedTabIDs = []
            focusedTabBySpace.removeValue(forKey: activeSpaceID)
            placeholdersBySpace = [:]
            return
        }
        let originalSelection = selectedTabIDs
        var seen = Set<UUID>()
        selectedTabIDs = Array(selectedTabIDs.filter { id in
            guard seen.insert(id).inserted, available(id),
                  let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }) else { return false }
            return tab.profileID == space.profileID && (tab.kind == .favorite || tab.spaceID == space.id)
        }.prefix(4))
        selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
        // Consume an invalid focus once. If that page later returns from a
        // different window, it cannot supersede the user's newer selection.
        if let focus = preferredFocusedTabID { focusedTabBySpace[activeSpaceID] = focus }
        else { focusedTabBySpace.removeValue(forKey: activeSpaceID) }
        // A surviving subset is a projection of the original split. Do not
        // substitute an unrelated shared layout with the same smaller group.
        if selectedTabIDs == originalSelection { rememberSplitLayout(state) }
        reconcilePlaceholders(state, available: available)
    }

    // Called only for a command originating in this window, not by Combine.
    mutating func captureCommand(_ state: BrowserState, available: (UUID) -> Bool) {
        guard isReady else { return }
        selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
        activeSpaceID = state.activeSpaceID
        selectedTabIDs = state.selectedTabIDs
        reconcile(state, available: available)
    }

    mutating func selectSpace(_ id: UUID, state: BrowserState, available: (UUID) -> Bool) {
        guard isReady, state.spaces.contains(where: { $0.id == id }) else { return }
        rememberSplitLayout(state)
        selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
        activeSpaceID = id
        selectedTabIDs = selectionBySpace[id.uuidString] ?? []
        reconcile(state, available: available)
    }

    /// Space deletion's inverse restores this window's original selection,
    /// never a different window's last published selection for the Space.
    mutating func restoreDeletedSpace(_ id: UUID, selection: [UUID], focus: UUID?, state: BrowserState,
                                      available: (UUID) -> Bool) {
        guard isReady, state.spaces.contains(where: { $0.id == id }) else { return }
        selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
        activeSpaceID = id; selectedTabIDs = selection
        if let focus { focusedTabBySpace[id] = focus }
        reconcile(state, available: available)
    }

    // A ready shell-local page intentionally has no native selection. A web
    // wrapper that is still creating its page is not that local-page command.
    func isLocalSelection(_ id: UUID?, state: BrowserState, hasNativeWrapper: Bool) -> Bool {
        guard isReady else { return false }
        guard let id else { return selectedTabIDs.isEmpty && !hasNativeWrapper }
        guard selectedTabIDs.contains(id),
              let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }) else { return false }
        return InternalPage.isInternal(tab.url)
            || (!hasNativeWrapper && (tab.url.isEmpty || tab.url == "about:blank"))
    }

    // An engine selection identifies an existing live page. It does not adopt
    // another window's page or collapse a split that already contains it.
    @discardableResult
    mutating func selectExistingTab(_ id: UUID, state: BrowserState,
                                    available: (UUID) -> Bool) -> Bool {
        guard isReady, available(id),
              let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
              state.spaces.contains(where: { $0.id == tab.spaceID && $0.profileID == tab.profileID }) else { return false }
        var next = self
        next.reconcile(state, available: available)
        if !next.selectedTabIDs.contains(id) {
            next.selectionBySpace[next.activeSpaceID.uuidString] = next.selectedTabIDs
            let currentProfile = state.spaces.first { $0.id == next.activeSpaceID }?.profileID
            if tab.kind != .favorite || currentProfile != tab.profileID {
                next.activeSpaceID = tab.spaceID
            }
            let group = SidebarSplitItems.groups(in: state, spaceID: next.activeSpaceID).first { $0.tabIDs.contains(id) }
            let members = group?.tabIDs ?? [id]
            guard members.allSatisfy(available) else { return false }
            next.selectedTabIDs = members
            next.selectionBySpace[next.activeSpaceID.uuidString] = members
            if let group { next.splitLayoutBySpace[next.activeSpaceID] = group }
        }
        self = next
        return true
    }

    mutating func adopt(_ id: UUID, state: BrowserState, foreground: Bool) {
        guard let tab = state.tabs.first(where: { $0.id == id }) else { return }
        // A profile-wide Favorite moved into a ready window joins that window's
        // current Space of its profile, as an existing-page selection does; its
        // stored creation Space is not a destination.
        let currentProfile = state.spaces.first { $0.id == activeSpaceID }?.profileID
        let spaceID = isReady && tab.kind == .favorite && currentProfile == tab.profileID ? activeSpaceID : tab.spaceID
        guard state.spaces.contains(where: { $0.id == spaceID && $0.profileID == tab.profileID }) else { return }
        let wasReady = isReady
        isReady = true
        if foreground || !wasReady {
            selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
            activeSpaceID = spaceID
            selectedTabIDs = [id]
            selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
        }
    }

    /// Apply only the origin's completed close decision. Other windows merely
    /// reconcile removed IDs; they never adopt this command's replacement.
    @discardableResult
    mutating func finishFolderRemoval(_ selection: FolderRemovalSelection,
                                      state: BrowserState, available: (UUID) -> Bool) -> Bool {
        guard isReady, activeSpaceID == selection.spaceID,
              state.spaces.contains(where: { $0.id == selection.spaceID && $0.profileID == selection.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == selection.profileID }),
              state.spaces.contains(where: { $0.id == selection.replacementSpaceID && $0.profileID == selection.profileID }) else { return false }
        let live = Set(state.tabs.filter { $0.archivedAt == nil }.map(\.id))
        let remaining = selection.original.filter { live.contains($0) && !selection.removed.contains($0) }
        guard selectedTabIDs == selection.original || selectedTabIDs == remaining,
              selection.tabIDs.count <= 4, Set(selection.tabIDs).count == selection.tabIDs.count,
              selection.tabIDs.allSatisfy({ id in
                  available(id) && state.tabs.contains { $0.id == id && $0.archivedAt == nil
                      && $0.profileID == selection.profileID
                      && ($0.spaceID == selection.replacementSpaceID || $0.kind == .favorite) }
              }), selection.focusedTabID == nil || selection.tabIDs.contains(selection.focusedTabID!) else { return false }
        if selection.tabIDs.count > 1 {
            guard SidebarSplitItems.groups(in: state, spaceID: selection.replacementSpaceID).contains(where: { $0.tabIDs == selection.tabIDs })
                || selection.tabIDs == remaining else { return false }
        }
        selectionBySpace[activeSpaceID.uuidString] = remaining
        activeSpaceID = selection.replacementSpaceID
        selectedTabIDs = selection.tabIDs
        selectionBySpace[activeSpaceID.uuidString] = selection.tabIDs
        focusedTabBySpace[activeSpaceID] = selection.focusedTabID
        rememberSplitLayout(state)
        // Commit the actual selection transition here, including an empty
        // selection. Intermediate store reconciliation is not a selection.
        recordSelectionForReturn(selection.focusedTabID, state: state)
        return true
    }

    ///
    /// This runs solely in the originating physical window after durable Undo.
    @discardableResult
    mutating func finishFolderUndo(_ undo: FolderDeletionUndo, state: BrowserState,
                                  available: (UUID) -> Bool) -> Bool {
        finishUndo(focusing: undo.focusedTabID, spaceID: undo.spaceID, profileID: undo.profileID,
                   state: state, available: available)
    }

    @discardableResult
    mutating func finishClosedTabsUndo(_ undo: ClosedTabsUndo, state: BrowserState,
                                       available: (UUID) -> Bool) -> Bool {
        finishUndo(focusing: undo.focusedTabID, spaceID: undo.spaceID, profileID: undo.profileID,
                   state: state, available: available)
    }

    private mutating func finishUndo(focusing focus: UUID?, spaceID: UUID, profileID: UUID,
                                     state: BrowserState, available: (UUID) -> Bool) -> Bool {
        guard let focus,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              selectExistingTab(focus, state: state, available: available) else { return false }
        recordFocusedTab(focus)
        return true
    }

    mutating func remove(_ id: UUID) {
        let previousSelection = selectedTabIDs
        for spaceID in Array(focusedTabBySpace.keys) where focusedTabBySpace[spaceID] == id {
            let selection = spaceID == activeSpaceID ? previousSelection : selectionBySpace[spaceID.uuidString] ?? []
            focusedTabBySpace[spaceID] = BrowserSplitLayout.focusSuccessor(selection.filter { $0 != id },
                                                                           removedAt: selection.firstIndex(of: id))
        }
        selectedTabIDs.removeAll { $0 == id }
        for key in Array(selectionBySpace.keys) { selectionBySpace[key]?.removeAll { $0 == id } }
    }

    //
    //
    // it leaves keeps that content as a placeholder (Blueprint case 5) with
    // no sidebar item: its row and address clear, but its pane stays in place,
    //
    struct PagePlaceholders: Equatable {
        /// The Space's panes in their original order, placeholders included.
        var tabIDs: [UUID]
        var placeholders: Set<UUID>
        var layout: BrowserSplitLayout?
        /// The Space's selection is still this slot's live panes, or what
        /// remains of them; any other selection replaced the placeholders.
        func holds(_ selection: [UUID]) -> Bool {
            var remaining = selection[...]
            for id in tabIDs where !placeholders.contains(id) && remaining.first == id { remaining = remaining.dropFirst() }
            return remaining.isEmpty
        }
    }
    private(set) var placeholdersBySpace: [UUID: PagePlaceholders] = [:]

    /// The page of `id` moved to another window. Every Space selecting it
    /// keeps its pane as a placeholder; returns whether one was kept.
    @discardableResult
    mutating func leavePlaceholder(_ id: UUID, state: BrowserState) -> Bool {
        var kept = false
        if isReady {
            var spaces = selectedTabIDs.contains(id) ? [activeSpaceID] : []
            for (key, ids) in selectionBySpace where ids.contains(id) {
                if let space = UUID(uuidString: key), space != activeSpaceID { spaces.append(space) }
            }
            for space in spaces {
                let selection = space == activeSpaceID ? selectedTabIDs : selectionBySpace[space.uuidString] ?? []
                var slot = placeholdersBySpace[space].flatMap { $0.holds(selection) ? $0 : nil }
                    ?? PagePlaceholders(tabIDs: selection, placeholders: [],
                                        layout: layout(for: selection, in: space, state: state))
                slot.placeholders.insert(id)
                placeholdersBySpace[space] = slot
                kept = true
            }
        }
        remove(id)
        return kept
    }

    private func layout(for selection: [UUID], in space: UUID, state: BrowserState) -> BrowserSplitLayout? {
        guard selection.count > 1 else { return nil }
        if let group = SidebarSplitItems.groups(in: state, spaceID: space).first(where: { $0.tabIDs == selection }) { return group }
        if space == activeSpaceID, selection == selectedTabIDs { return splitLayout }
        return splitLayoutBySpace[space].flatMap { $0.tabIDs == selection ? $0 : nil }
    }

    private var currentPlaceholders: PagePlaceholders? {
        placeholdersBySpace[activeSpaceID].flatMap { $0.holds(selectedTabIDs) ? $0 : nil }
    }
    /// Panes of the current Space: the selection, with any placeholders in
    /// their original slots.
    var displayedTabIDs: [UUID] {
        guard let slot = currentPlaceholders else { return selectedTabIDs }
        return Array(slot.tabIDs.filter { slot.placeholders.contains($0) || selectedTabIDs.contains($0) }.prefix(4))
    }
    var displayedPlaceholders: Set<UUID> { currentPlaceholders?.placeholders ?? [] }
    /// Split geometry for `displayedTabIDs`.
    var displayedSplitLayout: BrowserSplitLayout? {
        guard let slot = currentPlaceholders else { return splitLayout }
        guard let layout = slot.layout, layout.tabIDs == displayedTabIDs,
              BrowserSplitLayout.normalized(layout.widthFactors, count: layout.tabIDs.count) != nil else { return nil }
        return layout
    }
    /// Whether any Space of this window shows `id` as a placeholder.
    func showsPlaceholder(_ id: UUID) -> Bool { placeholdersBySpace.values.contains { $0.placeholders.contains(id) } }
    var hasPlaceholders: Bool { !placeholdersBySpace.isEmpty }

    private mutating func reconcilePlaceholders(_ state: BrowserState, available: (UUID) -> Bool) {
        guard isReady else { placeholdersBySpace = [:]; return }
        for (spaceID, original) in placeholdersBySpace {
            let key = spaceID.uuidString
            let selection = spaceID == activeSpaceID ? selectedTabIDs : selectionBySpace[key] ?? []
            guard let space = state.spaces.first(where: { $0.id == spaceID }), original.holds(selection) else {
                placeholdersBySpace.removeValue(forKey: spaceID); continue
            }
            func belongs(_ id: UUID) -> Bool {
                state.tabs.contains { $0.id == id && $0.archivedAt == nil && $0.profileID == space.profileID
                    && ($0.kind == .favorite || $0.spaceID == space.id) }
            }
            var slot = original
            // A page this window can use again (returned, or released by its
            // last owner) rejoins the selection in its slot.
            let returning = slot.placeholders.filter { belongs($0) && available($0) }
            slot.placeholders = slot.placeholders.filter { belongs($0) && !returning.contains($0) }
            slot.tabIDs = slot.tabIDs.filter { selection.contains($0) || returning.contains($0) || slot.placeholders.contains($0) }
            if !returning.isEmpty {
                let restored = Array(slot.tabIDs.filter { !slot.placeholders.contains($0) }.prefix(4))
                if spaceID == activeSpaceID { selectedTabIDs = restored }
                selectionBySpace[key] = restored
                if let layout = slot.layout, layout.tabIDs == restored { splitLayoutBySpace[spaceID] = layout }
                else if slot.placeholders.isEmpty, let layout = slot.layout,
                        let factors = BrowserSplitLayout.normalized(
                            layout.tabIDs.indices.filter { restored.contains(layout.tabIDs[$0]) }.map { layout.widthFactors[$0] },
                            count: restored.count), restored.count > 1 {
                    splitLayoutBySpace[spaceID] = BrowserSplitLayout(id: layout.id, sidebarAnchorID: layout.sidebarAnchorID,
                        customTitle: layout.customTitle, customIcon: layout.customIcon, spaceID: spaceID, tabIDs: restored,
                        orientation: layout.orientation, widthFactors: factors)
                }
            }
            if slot.placeholders.isEmpty { placeholdersBySpace.removeValue(forKey: spaceID) }
            else { placeholdersBySpace[spaceID] = slot }
        }
    }
}

///
/// (`WindowsData+ContentReparenting.swift`).
enum PageReparenting {
    /// Pages another window holds for a selection of `members`, in pane order,
    ///
    ///
    ///
    static func pagesToMove(_ members: [UUID], usableHere: (UUID) -> Bool, movable: (UUID) -> Bool) -> [UUID]? {
        var pages: [UUID] = []
        for id in members where !usableHere(id) {
            guard movable(id) else { return nil }
            pages.append(id)
        }
        return pages
    }

    ///
    /// so a row works in every window: an action on a tab another window
    /// holds moves its page here first. Close too moves it, then closes it
    /// here, so a leave-page prompt and the close's Undo and Reopen belong to
    /// the window whose row was used.
    enum RowAction: Equatable { case here, moveHere, moveHereThenClose }
    /// `busy` covers this window's own refusals (a close, move or retirement
    /// under way), never which window holds the page.
    static func rowAction(closing: Bool, busy: Bool, usableHere: Bool, heldElsewhere: Bool) -> RowAction? {
        guard !busy else { return nil }
        if usableHere { return .here }
        guard heldElsewhere else { return nil }
        return closing ? .moveHereThenClose : .moveHere
    }

    struct Candidate: Equatable {
        let windowID: UUID
        /// A placeholder for the page in the window's current Space.
        let displaysPlaceholder: Bool
        /// A placeholder for the page in any of the window's Spaces.
        let showsPlaceholder: Bool
        let lastActive: Date
        /// The window could take the page now (not closing, moving or in full screen).
        var canReceive = true
    }
    enum Trigger: Equatable {
        /// `ReparentingTrigger.untargeted(.itemDeselected)`.
        case deselected
        ///
        case ownerClosing
    }
    ///
    /// holding a placeholder and takes the most recent by date. A deselected
    /// page returns only to a window showing it now; a closing owner's page
    /// goes to any window keeping its placeholder rather than closing.
    static func returnDestination(_ candidates: [Candidate], trigger: Trigger) -> UUID? {
        returnDestinations(candidates, trigger: trigger).first
    }
    /// Every eligible window, most recent first, so a move one of them
    /// refuses can still go to the next.
    static func returnDestinations(_ candidates: [Candidate], trigger: Trigger) -> [UUID] {
        candidates.filter { $0.canReceive && (trigger == .deselected ? $0.displaysPlaceholder : $0.showsPlaceholder) }
            .sorted { $0.lastActive > $1.lastActive }.map(\.windowID)
    }
    enum ReturnOutcome: Equatable {
        case started
        /// A window keeps the page's placeholder but can't take it now.
        case blocked
        /// No window keeps its placeholder.
        case unneeded
    }
    /// A return that started no move still waits while a window keeps the
    /// page's placeholder in any Space; it can't take the page now (moving,
    /// in full screen, closing, or showing another Space).
    static func unstartedReturn(_ candidates: [Candidate]) -> ReturnOutcome {
        candidates.contains(where: \.showsPlaceholder) ? .blocked : .unneeded
    }
}

// The registry reserves model IDs before native creation and records the exact
// incoming page identity before adoption. A token preserves both claims while
// the native engine transfers the same live page between physical windows.
@MainActor
final class NativePageOwnership {
    private var tabs: [UUID: UUID] = [:]
    private var pages: [String: (owner: UUID, tab: UUID)] = [:]
    struct Transfer: Equatable {
        fileprivate let id = UUID()
        let tab: UUID
        let page: String
        let source: UUID
        let destination: UUID
    }
    private var transfers: [UUID: Transfer] = [:]
    struct CollectionTransfer: Equatable {
        fileprivate let id = UUID()
        let source: UUID
        let destination: UUID
        let originals: [UUID: Claim]
    }
    private var collectionTransfers: [UUID: CollectionTransfer] = [:]
    private var collections: [UUID: CollectionTransfer] = [:]

    func reserveCollection(_ ids: [UUID], from source: UUID, to destination: UUID) -> CollectionTransfer? {
        guard source != destination, Set(ids).count == ids.count,
              ids.allSatisfy({ transfers[$0] == nil && collectionTransfers[$0] == nil
                  && (tabs[$0] == nil || tabs[$0] == source) }) else { return nil }
        let value = CollectionTransfer(source: source, destination: destination,
            originals: Dictionary(uniqueKeysWithValues: ids.map { ($0, claimSnapshot($0)) }))
        collections[value.id] = value
        for id in ids { collectionTransfers[id] = value }
        return value
    }
    func isCurrent(_ value: CollectionTransfer, closed: Set<UUID> = []) -> Bool {
        collections[value.id] == value && value.originals.allSatisfy { id, original in
            collectionTransfers[id] == value && (claimSnapshot(id) == original ||
                (closed.contains(id) && tabs[id] == nil && claimSnapshot(id).pages.isEmpty))
        }
    }
    @discardableResult
    func finishCollection(_ value: CollectionTransfer, moved: Bool, closed: Set<UUID> = []) -> Bool {
        guard isCurrent(value, closed: closed) else { return false }
        collections.removeValue(forKey: value.id)
        for (id, original) in value.originals {
            collectionTransfers.removeValue(forKey: id)
            if moved && !closed.contains(id) {
                tabs[id] = value.destination
                for page in original.pages { pages[page] = (value.destination, id) }
            }
        }
        return true
    }

    func reserveTransfer(_ tab: UUID, page: String, from source: UUID, to destination: UUID) -> Transfer? {
        guard source != destination, transfers[tab] == nil, collectionTransfers[tab] == nil,
              tabs[tab] == source, let actual = pages[page],
              actual.owner == source, actual.tab == tab else { return nil }
        let transfer = Transfer(tab: tab, page: page, source: source, destination: destination)
        transfers[tab] = transfer
        return transfer
    }

    func isCurrent(_ transfer: Transfer) -> Bool {
        transfers[transfer.tab] == transfer && tabs[transfer.tab] == transfer.source
            && pages[transfer.page]?.owner == transfer.source && pages[transfer.page]?.tab == transfer.tab
    }

    @discardableResult
    func finishTransfer(_ transfer: Transfer, moved: Bool) -> Bool {
        guard isCurrent(transfer) else { return false }
        transfers.removeValue(forKey: transfer.tab)
        if moved {
            tabs[transfer.tab] = transfer.destination
            pages[transfer.page] = (transfer.destination, transfer.tab)
        }
        return true
    }

    struct Claim: Equatable {
        let owner: UUID?
        let pages: Set<String>
        let transfer: Transfer?
    }
    func claimSnapshot(_ tab: UUID) -> Claim {
        Claim(owner: tabs[tab], pages: Set(pages.filter { $0.value.tab == tab }.map(\.key)), transfer: transfers[tab])
    }

    func canUse(_ tab: UUID, owner: UUID) -> Bool { collectionTransfers[tab] == nil && (tabs[tab] == nil || tabs[tab] == owner) }
    func isClaimed(_ tab: UUID) -> Bool { tabs[tab] != nil }
    /// The window claiming the tab, without collecting its pages as `claimSnapshot` does.
    func owner(of tab: UUID) -> UUID? { tabs[tab] }
    func canAdopt(_ page: String) -> Bool { pages[page] == nil }

    @discardableResult
    func claim(_ tab: UUID, owner: UUID, page: String? = nil) -> Bool {
        guard transfers[tab] == nil, collectionTransfers[tab] == nil, canUse(tab, owner: owner) else { return false }
        if let page, let existing = pages[page], existing.owner != owner || existing.tab != tab { return false }
        if let page, pages.contains(where: { $0.key != page && $0.value.tab == tab }) { return false }
        tabs[tab] = owner
        if let page { pages[page] = (owner, tab) }
        return true
    }

    func release(_ tab: UUID, owner: UUID) {
        guard tabs[tab] == owner else { return }
        transfers.removeValue(forKey: tab)
        // A real page close may arrive during a collection transfer. Keep its
        // reservation until the transaction explicitly accounts for that close.
        tabs.removeValue(forKey: tab)
        pages = pages.filter { $0.value.owner != owner || $0.value.tab != tab }
    }

    func releaseAll(owner: UUID) {
        transfers = transfers.filter { $0.value.source != owner && $0.value.destination != owner }
        collectionTransfers = collectionTransfers.filter { $0.value.source != owner && $0.value.destination != owner }
        collections = collections.filter { $0.value.source != owner && $0.value.destination != owner }
        tabs = tabs.filter { $0.value != owner }
        pages = pages.filter { $0.value.owner != owner }
    }
}
