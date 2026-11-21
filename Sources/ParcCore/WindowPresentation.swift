import Foundation

package struct WindowPresentation {
    package private(set) var activeSpaceID: UUID
    package private(set) var selectedTabIDs: [UUID]
    package private(set) var isReady: Bool
    private var selectionBySpace: [String: [UUID]]
    private var focusedTabBySpace: [UUID: UUID] = [:]
    private var splitLayoutBySpace: [UUID: BrowserSplitLayout] = [:]

    package private(set) var referrerPool: Set<UUID> = []
    private var poolFocusedID: UUID?
    package private(set) var previouslySelectedItemID: UUID?

    package mutating func recordCreation(_ id: UUID, state: BrowserState) {
        guard let tab = state.tab(id, where: { $0.archivedAt == nil }) else { return }
        if let referrer = tab.referrerID {
            referrerPool.formUnion([referrer, id])
        } else if let previous = tab.activeTabBeforeCreationID {
            referrerPool = [previous, id]
        }
    }

    @discardableResult
    package mutating func recordPeekPromotion(_ id: UUID, state: BrowserState) -> Bool {
        guard let tab = state.tab(id, where: { $0.archivedAt == nil }),
              state.spaces.contains(where: { $0.id == activeSpaceID && $0.profileID == tab.profileID }),
              state.spaces.contains(where: { $0.id == tab.spaceID && $0.profileID == tab.profileID }) else { return false }
        var replacement: Set<UUID> = [id]
        if let source = tab.referrerID {
            guard source != id, state.containsTab(source, where: { $0.archivedAt == nil && $0.profileID == tab.profileID }) else { return false }
            replacement.insert(source)
        }
        referrerPool = replacement
        return true
    }

    package mutating func recordSelectionForReturn(_ id: UUID?, state: BrowserState) {
        guard id != poolFocusedID else { return }
        if let id, !state.containsTab(id, where: { $0.archivedAt == nil }) { return }
        let outgoing = poolFocusedID
        poolFocusedID = id
        guard let id else { return }
        previouslySelectedItemID = outgoing
        guard referrerPool.contains(id) else { referrerPool.removeAll(); return }
        if let tab = state.tab(id, where: { $0.archivedAt == nil }),
           tab.kind != .today { referrerPool = [id] }
    }

    package struct SessionSelection: Equatable {
        package let spaceID: UUID
        package let isReady: Bool
        package let tabIDs: [UUID]
        package let focusedTabID: UUID?
    }

    package var sessionSelection: SessionSelection {
        SessionSelection(spaceID: activeSpaceID, isReady: isReady, tabIDs: selectedTabIDs, focusedTabID: preferredFocusedTabID)
    }

    package var preferredFocusedTabID: UUID? {
        focusedTabBySpace[activeSpaceID].flatMap { selectedTabIDs.contains($0) ? $0 : nil }
            ?? selectedTabIDs.first
    }

    package mutating func recordFocusedTab(_ id: UUID?) {
        guard isReady else { return }
        guard let id else { focusedTabBySpace.removeValue(forKey: activeSpaceID); return }
        guard selectedTabIDs.contains(id) else { return }
        focusedTabBySpace[activeSpaceID] = id
    }

    package var splitLayout: BrowserSplitLayout? {
        guard selectedTabIDs.count > 1, let layout = splitLayoutBySpace[activeSpaceID] else { return nil }
        let positions = layout.tabIDs.indices.filter { selectedTabIDs.contains(layout.tabIDs[$0]) }
        guard positions.map({ layout.tabIDs[$0] }) == selectedTabIDs,
              let factors = BrowserSplitLayout.normalized(positions.map({ layout.widthFactors[$0] }),
                                                          count: selectedTabIDs.count) else { return nil }
        var projected = BrowserSplitLayout(id: layout.id, sidebarAnchorID: layout.sidebarAnchorID, customTitle: layout.customTitle, customIcon: layout.customIcon, spaceID: activeSpaceID, tabIDs: selectedTabIDs,
                                           orientation: layout.orientation, widthFactors: factors, stacks: nil)
        projected.restack(from: layout)
        return projected
    }

    private mutating func rememberSplitLayout(_ state: BrowserState) {
        guard let layout = SidebarSplitItems.groups(in: state, spaceID: activeSpaceID).first(where: {
            $0.tabIDs == selectedTabIDs
        }), BrowserSplitLayout.normalized(layout.widthFactors, count: layout.tabIDs.count) != nil else { return }
        splitLayoutBySpace[activeSpaceID] = layout
    }

    package init(state: BrowserState, ready: Bool, preferredProfileID: UUID? = nil,
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

    package func projected(_ state: BrowserState) -> BrowserState {
        var result = state
        result.activeSpaceID = activeSpaceID
        result.selectedTabIDs = isReady ? selectedTabIDs : []
        result.selectionBySpace = selectionBySpace
        result.selectionBySpace[activeSpaceID.uuidString] = result.selectedTabIDs
        return result
    }

    package mutating func reconcile(_ state: BrowserState, available: (UUID) -> Bool) {
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
                  let tab = state.tab(id, where: { $0.archivedAt == nil }) else { return false }
            return tab.profileID == space.profileID && (tab.kind == .favorite || tab.spaceID == space.id)
        }.prefix(4))
        selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
        if let focus = preferredFocusedTabID { focusedTabBySpace[activeSpaceID] = focus }
        else { focusedTabBySpace.removeValue(forKey: activeSpaceID) }
        if selectedTabIDs == originalSelection { rememberSplitLayout(state) }
        reconcilePlaceholders(state, available: available)
    }

    package mutating func captureCommand(_ state: BrowserState, available: (UUID) -> Bool) {
        guard isReady else { return }
        selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
        activeSpaceID = state.activeSpaceID
        selectedTabIDs = state.selectedTabIDs
        reconcile(state, available: available)
    }

    package mutating func selectSpace(_ id: UUID, state: BrowserState, available: (UUID) -> Bool) {
        guard isReady, state.spaces.contains(where: { $0.id == id }) else { return }
        rememberSplitLayout(state)
        selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
        activeSpaceID = id
        selectedTabIDs = selectionBySpace[id.uuidString] ?? []
        reconcile(state, available: available)
    }

    package mutating func restoreDeletedSpace(_ id: UUID, selection: [UUID], focus: UUID?, state: BrowserState,
                                      available: (UUID) -> Bool) {
        guard isReady, state.spaces.contains(where: { $0.id == id }) else { return }
        selectionBySpace[activeSpaceID.uuidString] = selectedTabIDs
        activeSpaceID = id; selectedTabIDs = selection
        if let focus { focusedTabBySpace[id] = focus }
        reconcile(state, available: available)
    }

    package func isLocalSelection(_ id: UUID?, state: BrowserState, hasNativeWrapper: Bool) -> Bool {
        guard isReady else { return false }
        guard let id else { return selectedTabIDs.isEmpty && !hasNativeWrapper }
        guard selectedTabIDs.contains(id),
              let tab = state.tab(id, where: { $0.archivedAt == nil }) else { return false }
        return InternalPage.isInternal(tab.url)
            || (!hasNativeWrapper && (tab.url.isEmpty || tab.url == "about:blank"))
    }

    @discardableResult
    package mutating func selectExistingTab(_ id: UUID, state: BrowserState,
                                    available: (UUID) -> Bool) -> Bool {
        guard isReady, available(id),
              let tab = state.tab(id, where: { $0.archivedAt == nil }),
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

    package mutating func adopt(_ id: UUID, state: BrowserState, foreground: Bool) {
        guard let tab = state.tab(id) else { return }
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

    @discardableResult
    package mutating func finishFolderRemoval(_ selection: FolderRemovalSelection,
                                      state: BrowserState, available: (UUID) -> Bool) -> Bool {
        guard isReady, activeSpaceID == selection.spaceID,
              state.spaces.contains(where: { $0.id == selection.spaceID && $0.profileID == selection.profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == selection.profileID }),
              state.spaces.contains(where: { $0.id == selection.replacementSpaceID && $0.profileID == selection.profileID }) else { return false }
        let live = Set(state.openTabs.map(\.id))
        let remaining = selection.original.filter { live.contains($0) && !selection.removed.contains($0) }
        guard selectedTabIDs == selection.original || selectedTabIDs == remaining,
              selection.tabIDs.count <= 4, Set(selection.tabIDs).count == selection.tabIDs.count,
              selection.tabIDs.allSatisfy({ id in
                  available(id) && state.containsTab(id, where: { $0.archivedAt == nil
                      && $0.profileID == selection.profileID
                      && ($0.spaceID == selection.replacementSpaceID || $0.kind == .favorite) })
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
        recordSelectionForReturn(selection.focusedTabID, state: state)
        return true
    }

    @discardableResult
    package mutating func finishFolderUndo(_ undo: FolderDeletionUndo, state: BrowserState,
                                  available: (UUID) -> Bool) -> Bool {
        finishUndo(focusing: undo.focusedTabID, spaceID: undo.spaceID, profileID: undo.profileID,
                   state: state, available: available)
    }

    @discardableResult
    package mutating func finishClosedTabsUndo(_ undo: ClosedTabsUndo, state: BrowserState,
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

    package private(set) var awaitsCloseReplacement = false

    package mutating func closePage(_ id: UUID) {
        if isReady, selectedTabIDs.contains(id) { awaitsCloseReplacement = true }
        remove(id)
    }

    package func admitsEngineSelection(of id: UUID, closing: (UUID) -> Bool) -> Bool {
        selectedTabIDs.contains(id) || (!awaitsCloseReplacement && !selectedTabIDs.contains(where: closing))
    }

    package mutating func engineSelectionSynchronized() { awaitsCloseReplacement = false }

    package mutating func remove(_ id: UUID) {
        let previousSelection = selectedTabIDs
        for spaceID in Array(focusedTabBySpace.keys) where focusedTabBySpace[spaceID] == id {
            let selection = spaceID == activeSpaceID ? previousSelection : selectionBySpace[spaceID.uuidString] ?? []
            focusedTabBySpace[spaceID] = BrowserSplitLayout.focusSuccessor(selection.filter { $0 != id },
                                                                           removedAt: selection.firstIndex(of: id))
        }
        selectedTabIDs.removeAll { $0 == id }
        for key in Array(selectionBySpace.keys) { selectionBySpace[key]?.removeAll { $0 == id } }
    }

    package struct PagePlaceholders: Equatable {
        package var tabIDs: [UUID]
        package var placeholders: Set<UUID>
        package var layout: BrowserSplitLayout?
        package func holds(_ selection: [UUID]) -> Bool {
            var remaining = selection[...]
            for id in tabIDs where !placeholders.contains(id) && remaining.first == id { remaining = remaining.dropFirst() }
            return remaining.isEmpty
        }
    }
    package private(set) var placeholdersBySpace: [UUID: PagePlaceholders] = [:]

    @discardableResult
    package mutating func leavePlaceholder(_ id: UUID, state: BrowserState) -> Bool {
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
    package var displayedTabIDs: [UUID] {
        guard let slot = currentPlaceholders else { return selectedTabIDs }
        return Array(slot.tabIDs.filter { slot.placeholders.contains($0) || selectedTabIDs.contains($0) }.prefix(4))
    }
    package var displayedPlaceholders: Set<UUID> { currentPlaceholders?.placeholders ?? [] }
    package var displayedSplitLayout: BrowserSplitLayout? {
        guard let slot = currentPlaceholders else { return splitLayout }
        guard let layout = slot.layout, layout.tabIDs == displayedTabIDs,
              BrowserSplitLayout.normalized(layout.widthFactors, count: layout.tabIDs.count) != nil else { return nil }
        return layout
    }
    package func showsPlaceholder(_ id: UUID) -> Bool { placeholdersBySpace.values.contains { $0.placeholders.contains(id) } }
    package var allPlaceholders: Set<UUID> { placeholdersBySpace.values.reduce(into: []) { $0.formUnion($1.placeholders) } }
    package var hasPlaceholders: Bool { !placeholdersBySpace.isEmpty }

    private mutating func reconcilePlaceholders(_ state: BrowserState, available: (UUID) -> Bool) {
        guard isReady else { placeholdersBySpace = [:]; return }
        for (spaceID, original) in placeholdersBySpace {
            let key = spaceID.uuidString
            let selection = spaceID == activeSpaceID ? selectedTabIDs : selectionBySpace[key] ?? []
            guard let space = state.spaces.first(where: { $0.id == spaceID }), original.holds(selection) else {
                placeholdersBySpace.removeValue(forKey: spaceID); continue
            }
            func belongs(_ id: UUID) -> Bool {
                state.containsTab(id, where: { $0.archivedAt == nil && $0.profileID == space.profileID
                    && ($0.kind == .favorite || $0.spaceID == space.id) })
            }
            var slot = original
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
                    var projected = BrowserSplitLayout(id: layout.id, sidebarAnchorID: layout.sidebarAnchorID,
                        customTitle: layout.customTitle, customIcon: layout.customIcon, spaceID: spaceID, tabIDs: restored,
                        orientation: layout.orientation, widthFactors: factors, stacks: nil)
                    projected.restack(from: layout)
                    splitLayoutBySpace[spaceID] = projected
                }
            }
            if slot.placeholders.isEmpty { placeholdersBySpace.removeValue(forKey: spaceID) }
            else { placeholdersBySpace[spaceID] = slot }
        }
    }
}

package enum PageReparenting {
    package static func pagesToMove(_ members: [UUID], usableHere: (UUID) -> Bool, movable: (UUID) -> Bool) -> [UUID]? {
        var pages: [UUID] = []
        for id in members where !usableHere(id) {
            guard movable(id) else { return nil }
            pages.append(id)
        }
        return pages
    }

    package enum RefusedCloseNotice: Equatable {
        case explain(String)
        case beep
    }
    package static func closeRefusal(unsavedNotes: Bool, reason: String?) -> RefusedCloseNotice? {
        if unsavedNotes { return .explain("The Note couldn’t save its latest changes. Open it to retry or discard them.") }
        return reason.map { .explain($0) }
    }

    package enum RowAction: Equatable { case here, moveHere, moveHereThenClose }
    package static func rowAction(closing: Bool, busy: Bool, usableHere: Bool, heldElsewhere: Bool) -> RowAction? {
        guard !busy else { return nil }
        if usableHere { return .here }
        guard heldElsewhere else { return nil }
        return closing ? .moveHereThenClose : .moveHere
    }

    package struct Candidate: Equatable {
        package let windowID: UUID
        package let displaysPlaceholder: Bool
        package let showsPlaceholder: Bool
        package let lastActive: Date
        package var canReceive = true

        package init(windowID: UUID, displaysPlaceholder: Bool, showsPlaceholder: Bool, lastActive: Date, canReceive: Bool = true) {
            self.windowID = windowID
            self.displaysPlaceholder = displaysPlaceholder
            self.showsPlaceholder = showsPlaceholder
            self.lastActive = lastActive
            self.canReceive = canReceive
        }
    }
    package enum Trigger: Equatable {
        case deselected
        case ownerClosing
    }
    package static func returnDestination(_ candidates: [Candidate], trigger: Trigger) -> UUID? {
        returnDestinations(candidates, trigger: trigger).first
    }
    package static func returnDestinations(_ candidates: [Candidate], trigger: Trigger) -> [UUID] {
        candidates.filter { $0.canReceive && (trigger == .deselected ? $0.displaysPlaceholder : $0.showsPlaceholder) }
            .sorted { $0.lastActive > $1.lastActive }.map(\.windowID)
    }
    package enum ReturnOutcome: Equatable {
        case started
        case blocked
        case unneeded
    }
    package static func unstartedReturn(_ candidates: [Candidate]) -> ReturnOutcome {
        candidates.contains(where: \.showsPlaceholder) ? .blocked : .unneeded
    }
}

@MainActor
package final class NativePageOwnership {
    private var tabs: [UUID: UUID] = [:]
    private var pages: [String: (owner: UUID, tab: UUID)] = [:]
    package struct Transfer: Equatable {
        fileprivate let id = UUID()
        package let tab: UUID
        package let page: String
        package let source: UUID
        package let destination: UUID

        package init(tab: UUID, page: String, source: UUID, destination: UUID) {
            self.tab = tab
            self.page = page
            self.source = source
            self.destination = destination
        }
    }
    private var transfers: [UUID: Transfer] = [:]
    package struct CollectionTransfer: Equatable {
        fileprivate let id = UUID()
        package let source: UUID
        package let destination: UUID
        package let originals: [UUID: Claim]

        package init(source: UUID, destination: UUID, originals: [UUID: Claim]) {
            self.source = source
            self.destination = destination
            self.originals = originals
        }
    }
    private var collectionTransfers: [UUID: CollectionTransfer] = [:]
    private var collections: [UUID: CollectionTransfer] = [:]

    package init() {}

    package func reserveCollection(_ ids: [UUID], from source: UUID, to destination: UUID) -> CollectionTransfer? {
        guard source != destination, Set(ids).count == ids.count,
              ids.allSatisfy({ transfers[$0] == nil && collectionTransfers[$0] == nil
                  && (tabs[$0] == nil || tabs[$0] == source) }) else { return nil }
        let value = CollectionTransfer(source: source, destination: destination,
            originals: Dictionary(uniqueKeysWithValues: ids.map { ($0, claimSnapshot($0)) }))
        collections[value.id] = value
        for id in ids { collectionTransfers[id] = value }
        return value
    }
    package func isCurrent(_ value: CollectionTransfer, closed: Set<UUID> = []) -> Bool {
        collections[value.id] == value && value.originals.allSatisfy { id, original in
            collectionTransfers[id] == value && (claimSnapshot(id) == original ||
                (closed.contains(id) && tabs[id] == nil && claimSnapshot(id).pages.isEmpty))
        }
    }
    @discardableResult
    package func finishCollection(_ value: CollectionTransfer, moved: Bool, closed: Set<UUID> = []) -> Bool {
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

    package func reserveTransfer(_ tab: UUID, page: String, from source: UUID, to destination: UUID) -> Transfer? {
        guard source != destination, transfers[tab] == nil, collectionTransfers[tab] == nil,
              tabs[tab] == source, let actual = pages[page],
              actual.owner == source, actual.tab == tab else { return nil }
        let transfer = Transfer(tab: tab, page: page, source: source, destination: destination)
        transfers[tab] = transfer
        return transfer
    }

    package func isCurrent(_ transfer: Transfer) -> Bool {
        transfers[transfer.tab] == transfer && tabs[transfer.tab] == transfer.source
            && pages[transfer.page]?.owner == transfer.source && pages[transfer.page]?.tab == transfer.tab
    }

    @discardableResult
    package func finishTransfer(_ transfer: Transfer, moved: Bool) -> Bool {
        guard isCurrent(transfer) else { return false }
        transfers.removeValue(forKey: transfer.tab)
        if moved {
            tabs[transfer.tab] = transfer.destination
            pages[transfer.page] = (transfer.destination, transfer.tab)
        }
        return true
    }

    package struct Claim: Equatable {
        package let owner: UUID?
        package let pages: Set<String>
        package let transfer: Transfer?

        package init(owner: UUID?, pages: Set<String>, transfer: Transfer?) {
            self.owner = owner
            self.pages = pages
            self.transfer = transfer
        }
    }
    package func claimSnapshot(_ tab: UUID) -> Claim {
        Claim(owner: tabs[tab], pages: Set(pages.filter { $0.value.tab == tab }.map(\.key)), transfer: transfers[tab])
    }

    package func canUse(_ tab: UUID, owner: UUID) -> Bool { collectionTransfers[tab] == nil && (tabs[tab] == nil || tabs[tab] == owner) }
    package func isClaimed(_ tab: UUID) -> Bool { tabs[tab] != nil }
    package func owner(of tab: UUID) -> UUID? { tabs[tab] }
    package func canAdopt(_ page: String) -> Bool { pages[page] == nil }

    @discardableResult
    package func claim(_ tab: UUID, owner: UUID, page: String? = nil) -> Bool {
        guard transfers[tab] == nil, collectionTransfers[tab] == nil, canUse(tab, owner: owner) else { return false }
        if let page, let existing = pages[page], existing.owner != owner || existing.tab != tab { return false }
        if let page, pages.contains(where: { $0.key != page && $0.value.tab == tab }) { return false }
        tabs[tab] = owner
        if let page { pages[page] = (owner, tab) }
        return true
    }

    package func release(_ tab: UUID, owner: UUID) {
        guard tabs[tab] == owner else { return }
        transfers.removeValue(forKey: tab)
        tabs.removeValue(forKey: tab)
        pages = pages.filter { $0.value.owner != owner || $0.value.tab != tab }
    }

    package func releaseAll(owner: UUID) {
        transfers = transfers.filter { $0.value.source != owner && $0.value.destination != owner }
        collectionTransfers = collectionTransfers.filter { $0.value.source != owner && $0.value.destination != owner }
        collections = collections.filter { $0.value.source != owner && $0.value.destination != owner }
        tabs = tabs.filter { $0.value != owner }
        pages = pages.filter { $0.value.owner != owner }
    }
}
