import Foundation

package struct ClosedItemRecord: Equatable {
    package enum Kind { case saved, archived }
    package let id: UUID
    package let kind: Kind
    package let spaceID: UUID
    package let profileID: UUID
    package let tabs: [BrowserTab]
    package let split: BrowserSplitLayout?
    package let focusedTabID: UUID
    package var membership: ClosedSplitMembership? = nil
    package var tabIDs: [UUID] { tabs.map(\.id) }

    package init(id: UUID, kind: Kind, spaceID: UUID, profileID: UUID, tabs: [BrowserTab], split: BrowserSplitLayout?, focusedTabID: UUID, membership: ClosedSplitMembership? = nil) {
        self.id = id
        self.kind = kind
        self.spaceID = spaceID
        self.profileID = profileID
        self.tabs = tabs
        self.split = split
        self.focusedTabID = focusedTabID
        self.membership = membership
    }

    package func isValid(in state: BrowserState) -> Bool {
        if let membership {
            guard kind == .archived, split == nil, tabs.count == 1, membership.layout.spaceID == spaceID,
                  membership.layout.tabIDs.contains(tabs[0].id) else { return false }
        }
        guard !tabs.isEmpty, tabs.count <= 4,
              state.profiles.contains(where: { $0.id == profileID }),
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              !state.profileRemovals.contains(where: { $0.profileID == profileID }),
              tabs.allSatisfy({ expected in
                  expected.profileID == profileID && state.tabs.contains(expected)
                      && (expected.kind == .favorite || expected.spaceID == spaceID)
              }) else { return false }
        guard tabIDs.contains(focusedTabID), Set(tabIDs).count == tabIDs.count else { return false }
        let overlapping = state.splitLayouts.filter { !Set($0.tabIDs).isDisjoint(with: tabIDs) }
        if kind == .saved {
            guard tabs.allSatisfy({ $0.kind != .today && $0.archivedAt == nil }) else { return false }
            if let split {
                return split.spaceID == spaceID && split.tabIDs == tabIDs
                    && BrowserSplitLayout.normalized(split.widthFactors, count: tabs.count) != nil
                    && overlapping == [split]
            }
            return tabs.count == 1 && overlapping.isEmpty
        }
        guard overlapping.isEmpty else { return false }
        guard tabs.allSatisfy({ $0.kind == .today && $0.archivedAt != nil }) else { return false }
        if let split {
            guard !state.splitLayouts.contains(where: { $0.id == split.id }),
                  split.spaceID == spaceID, split.tabIDs == tabIDs,
                  BrowserSplitLayout.normalized(split.widthFactors, count: tabs.count) != nil,
                  let groupID = tabs[0].archiveProvenance?.groupID,
                  tabs.allSatisfy({ $0.archiveProvenance?.groupID == groupID && $0.archiveProvenance?.split == split }),
                  Set(state.tabs.filter { $0.archivedAt != nil && $0.archiveProvenance?.groupID == groupID }.map(\.id)) == Set(tabIDs)
            else { return false }
        } else if tabs.count != 1 || tabs[0].archiveProvenance?.groupID != nil { return false }
        return true
    }
}

package struct ClosedSplitMembership: Equatable {
    package let layout: BrowserSplitLayout
    package let index: Int
    package let dissolved: Bool
    package let closedSiblings: Set<UUID>

    package func restoredLayout(restoring id: UUID, in state: BrowserState,
                        available: (UUID) -> Bool) -> BrowserSplitLayout? {
        guard let position = layout.tabIDs.firstIndex(of: id),
              let profileID = state.spaces.first(where: { $0.id == layout.spaceID })?.profileID else { return nil }
        func live(_ member: UUID) -> Bool {
            state.containsTab(member, where: { $0.archivedAt == nil && $0.profileID == profileID
                && ($0.kind == .favorite || $0.spaceID == layout.spaceID) }) && available(member)
        }
        func grouped(_ member: UUID) -> Bool {
            SidebarSplitItems.groups(in: state, spaceID: layout.spaceID).contains { $0.tabIDs.contains(member) }
        }
        guard live(id), !grouped(id) else { return nil }
        let share = layout.widthFactors[position]
        if var current = state.splitLayouts.first(where: { $0.id == layout.id }) {
            guard current.spaceID == layout.spaceID, current.tabIDs.count < 4,
                  current.tabIDs.allSatisfy(live),
                  let factors = BrowserSplitLayout.normalized(current.widthFactors, count: current.tabIDs.count)
            else { return nil }
            if layout.stacks != nil || current.stacks != nil { return rejoining(id, into: current) }
            let returned = current.tabIDs.filter { member in
                closedSiblings.contains(member) && (layout.tabIDs.firstIndex(of: member) ?? position) < position
            }.count
            let at = min(index + returned, current.tabIDs.count)
            let known = current.tabIDs.compactMap { member in
                layout.tabIDs.firstIndex(of: member).map { layout.widthFactors[$0] }
            }.reduce(0, +)
            var weights = factors.map { $0 * (known > 0 ? known : 1 - share) }
            weights.insert(share, at: at)
            current.tabIDs.insert(id, at: at)
            guard let result = BrowserSplitLayout.normalized(weights, count: current.tabIDs.count) else { return nil }
            current.widthFactors = result
            return current
        }
        guard dissolved else { return nil }
        let members = layout.tabIDs.filter { $0 == id || live($0) }
        guard !members.contains(where: { $0 != id && grouped($0) }), members.count >= 2,
              let factors = BrowserSplitLayout.normalized(
                  members.map { member in layout.widthFactors[layout.tabIDs.firstIndex(of: member)!] },
                  count: members.count) else { return nil }
        var group = layout
        group.tabIDs = members
        group.widthFactors = factors
        group.restack(from: layout)
        if group.sidebarAnchorID.map({ members.contains($0) }) != true { group.sidebarAnchorID = members.first }
        return group
    }

    private func rejoining(_ id: UUID, into current: BrowserSplitLayout) -> BrowserSplitLayout? {
        let original = layout.slots
        guard let origin = layout.position(of: id) else { return nil }
        let home = original[origin.slot], share = home.stackFactors[origin.index]
        var base = current, slots = current.slots
        let sources = current.tabIDs.map { member in original.firstIndex { $0.tabIDs.contains(member) } }
        if current.stacks == nil, current.orientation != layout.orientation, current.tabIDs.count > 1,
           let first = sources.first, first != nil, sources.allSatisfy({ $0 == first }) {
            base.orientation = layout.orientation
            slots = [BrowserSplitSlot(tabIDs: current.tabIDs, factor: 1, stackFactors: current.widthFactors)]
        }
        let preceding = Array(home.tabIDs[..<origin.index].reversed()), following = Array(home.tabIDs[(origin.index + 1)...])
        for mate in preceding + following {
            guard let slot = slots.firstIndex(where: { $0.tabIDs.contains(mate) }),
                  let index = slots[slot].tabIDs.firstIndex(of: mate) else { continue }
            let known = slots[slot].tabIDs.compactMap { member in
                home.tabIDs.firstIndex(of: member).map { home.stackFactors[$0] }
            }.reduce(0, +)
            let at = index + (preceding.contains(mate) ? 1 : 0)
            var weights = slots[slot].stackFactors.map { $0 * (known > 0 ? known : 1 - share) }
            weights.insert(share, at: at)
            slots[slot].stackFactors = weights
            slots[slot].tabIDs.insert(id, at: at)
            var result = base
            result.arrange(slots)
            return result
        }
        let earlier = Set(original[..<origin.slot].flatMap(\.tabIDs))
        let at = slots.lastIndex(where: { $0.tabIDs.contains(where: earlier.contains) }).map { $0 + 1 } ?? 0
        let homes = slots.flatMap(\.tabIDs).compactMap { member in original.firstIndex { $0.tabIDs.contains(member) } }
        let known = original.indices.filter(homes.contains).map { original[$0].factor }.reduce(0, +)
        for slot in slots.indices { slots[slot].factor *= known > 0 ? known : 1 - home.factor }
        slots.insert(BrowserSplitSlot(tabIDs: [id], factor: home.factor, stackFactors: [1]), at: at)
        var result = base
        result.arrange(slots)
        return result
    }
}

package struct ClosedItemIntent {
    package let spaceID: UUID
    package let profileID: UUID
    package let tabs: [BrowserTab]
    package let focusedTabID: UUID?
    package let completeSplits: [BrowserSplitLayout]
    package let partialSplits: [BrowserSplitLayout]
    package init?(ids: Set<UUID>, state: BrowserState, spaceID: UUID, profileID: UUID, focusedTabID: UUID?) {
        let tabs = state.openTabs(where: { ids.contains($0.id) })
        guard !ids.isEmpty, tabs.count == ids.count,
              state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              tabs.allSatisfy({ $0.profileID == profileID && ($0.kind == .favorite || $0.spaceID == spaceID) }) else { return nil }
        self.spaceID = spaceID; self.profileID = profileID; self.tabs = tabs; self.focusedTabID = focusedTabID
        completeSplits = state.splitLayouts.filter {
            $0.spaceID == spaceID && !$0.tabIDs.isEmpty && Set($0.tabIDs).isSubset(of: ids)
        }
        partialSplits = state.splitLayouts.filter {
            $0.spaceID == spaceID && !Set($0.tabIDs).isDisjoint(with: ids) && !Set($0.tabIDs).isSubset(of: ids)
        }
    }

    package func membership(of id: UUID, in state: BrowserState) -> ClosedSplitMembership? {
        let closed = Set(tabs.map(\.id))
        guard let layout = partialSplits.first(where: { $0.tabIDs.contains(id) }),
              let position = layout.tabIDs.firstIndex(of: id),
              let factors = BrowserSplitLayout.normalized(layout.widthFactors, count: layout.tabIDs.count) else { return nil }
        let survivors = layout.tabIDs.filter { !closed.contains($0) }
        let index = layout.tabIDs[..<position].filter { !closed.contains($0) }.count
        var original = layout
        original.widthFactors = factors
        let siblings = Set(layout.tabIDs.filter { $0 != id && closed.contains($0) })
        if let current = state.splitLayouts.first(where: { $0.id == layout.id }) {
            guard current.spaceID == layout.spaceID, current.tabIDs == survivors else { return nil }
            return ClosedSplitMembership(layout: original, index: index, dissolved: false, closedSiblings: siblings)
        }
        return survivors.count < 2
            ? ClosedSplitMembership(layout: original, index: index, dissolved: true, closedSiblings: siblings) : nil
    }
}

package struct ClosedPeekRecord: Equatable {
    package let id: UUID
    package let url: URL
    package let parentTabID: UUID
    package let profileID: UUID

    package init(id: UUID, url: URL, parentTabID: UUID, profileID: UUID) {
        self.id = id
        self.url = url
        self.parentTabID = parentTabID
        self.profileID = profileID
    }

    package func isValid(in state: BrowserState) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && state.profiles.contains(where: { $0.id == profileID })
            && !state.profileRemovals.contains(where: { $0.profileID == profileID })
            && state.containsTab(parentTabID, where: { $0.archivedAt == nil && $0.profileID == profileID })
    }
}

package enum ClosedItemStep {
    case items(ClosedItemRecord)
    case peek(ClosedPeekRecord)
    case folder(FolderDeletionUndo)

    package var id: UUID {
        switch self {
        case .items(let record): return record.id
        case .peek(let record): return record.id
        case .folder(let undo): return undo.id
        }
    }
}

package struct WindowClosedItems {
    private var saved: ClosedItemRecord?
    private var groups: [[ClosedItemStep]] = []
    package private(set) var itemLastActiveDates: [UUID: Date]

    package init(itemLastActiveDates: [UUID: Date] = [:]) {
        self.itemLastActiveDates = itemLastActiveDates
    }

    package mutating func recordSelection(_ ids: [UUID], focusedTabID: UUID?, state: BrowserState,
                                  at date: Date = Date()) {
        let available = Set(state.openTabs.map(\.id))
        itemLastActiveDates = itemLastActiveDates.filter { available.contains($0.key) }
        guard !ids.isEmpty, Set(ids).isSubset(of: available),
              let focus = focusedTabID, ids.contains(focus) else { return }
        itemLastActiveDates[focus] = date
    }

    package mutating func record(_ intent: ClosedItemIntent, in state: BrowserState) {
        var after: [BrowserTab] = []
        for before in intent.tabs {
            guard let tab = state.tab(before.id),
                  tab.profileID == before.profileID, tab.spaceID == before.spaceID,
                  tab.kind == before.kind, tab.folderID == before.folderID,
                  tab.savedURL == before.savedURL, tab.savedTitle == before.savedTitle,
                  before.kind == .today ? tab.archivedAt != nil : (tab.archivedAt == nil && tab.url == tab.savedURL && tab.title == tab.savedTitle)
            else { return }
            after.append(tab)
        }
        if !after.isEmpty, after.allSatisfy({ $0.kind != .today }) {
            let tab = after.enumerated().min { left, right in
                let l = itemLastActiveDates[left.element.id] ?? .distantPast
                let r = itemLastActiveDates[right.element.id] ?? .distantPast
                return l == r ? left.offset < right.offset : l > r
            }!.element
            let split = intent.completeSplits.first { $0.tabIDs.contains(tab.id) }
            let members = split.map { layout in
                layout.tabIDs.compactMap { id in after.first { $0.id == id } }
            } ?? [tab]
            let record = ClosedItemRecord(id: UUID(), kind: .saved, spaceID: intent.spaceID,
                profileID: intent.profileID, tabs: members, split: split, focusedTabID: tab.id)
            guard record.isValid(in: state) else { return }
            saved = record
            return
        }
        let archived = after.filter { $0.archivedAt != nil }
        guard !archived.isEmpty else { return }
        var seen = Set<UUID>(), steps: [ClosedItemRecord] = []
        for tab in archived where !seen.contains(tab.id) {
            let members: [BrowserTab], split: BrowserSplitLayout?
            var membership: ClosedSplitMembership?
            if let layout = tab.archiveProvenance?.split {
                let candidates = layout.tabIDs.compactMap { id in archived.first { $0.id == id } }
                guard candidates.count == layout.tabIDs.count else { continue }
                members = candidates; split = layout
            } else {
                members = [tab]; split = nil
                membership = intent.membership(of: tab.id, in: state)
            }
            let record = ClosedItemRecord(id: UUID(), kind: .archived, spaceID: intent.spaceID,
                profileID: intent.profileID, tabs: members, split: split,
                focusedTabID: intent.focusedTabID.flatMap { id in members.contains { $0.id == id } ? id : nil } ?? members[0].id,
                membership: membership)
            guard record.isValid(in: state) else { continue }
            seen.formUnion(record.tabIDs); steps.append(record)
        }
        guard !steps.isEmpty else { return }
        saved = nil
        groups.append(steps.map(ClosedItemStep.items))
    }

    package mutating func recordPeek(_ record: ClosedPeekRecord, in state: BrowserState) {
        guard record.isValid(in: state) else { return }
        groups.append([.peek(record)])
    }

    package mutating func recordFolderDeletion(_ undo: FolderDeletionUndo) {
        saved = nil
        groups.append([.folder(undo)])
    }

    package mutating func nextStep(in state: BrowserState,
                           restorable: (FolderDeletionUndo) -> Bool) -> ClosedItemStep? {
        if let saved, saved.isValid(in: state) { return .items(saved) }
        saved = nil
        while let step = groups.last?.last {
            switch step {
            case .items(let record): if record.isValid(in: state) { return step }
            case .peek(let record): if record.isValid(in: state) { return step }
            case .folder(let undo): if restorable(undo) { return step }
            }
            groups[groups.count - 1].removeLast()
            if groups.last?.isEmpty == true { groups.removeLast() }
        }
        return nil
    }
    package mutating func next(in state: BrowserState) -> ClosedItemRecord? {
        guard case .items(let record)? = nextStep(in: state, restorable: { _ in true }) else { return nil }
        return record
    }
    @discardableResult package mutating func consume(_ record: ClosedItemRecord) -> Bool { consume(stepID: record.id) }
    @discardableResult package mutating func consume(stepID: UUID) -> Bool {
        if saved?.id == stepID { saved = nil; return true }
        guard saved == nil, groups.last?.last?.id == stepID else { return false }
        groups[groups.count - 1].removeLast()
        if groups.last?.isEmpty == true { groups.removeLast() }
        return true
    }
    package mutating func selected(_ ids: [UUID]) {
        if let saved, !Set(ids).isDisjoint(with: saved.tabIDs) { self.saved = nil }
    }
}

package struct ClosedPageHistory<State> {
    package let limit: Int
    private var states: [UUID: State] = [:]
    private var order: [UUID] = []
    private var restored: Set<UUID> = []
    package init(limit: Int = 100) { self.limit = limit }

    package mutating func closed(_ id: UUID, state: State) {
        if states.updateValue(state, forKey: id) != nil { order.removeAll { $0 == id } }
        order.append(id); restored.remove(id)
        while order.count > limit {
            let oldest = order.removeFirst()
            states.removeValue(forKey: oldest); restored.remove(oldest)
        }
    }
    package mutating func restore(_ ids: some Sequence<UUID>) {
        for id in ids where states[id] != nil { restored.insert(id) }
    }
    package mutating func unrestore(_ ids: some Sequence<UUID>) { restored.subtract(ids) }
    package mutating func pageCreated(_ id: UUID) { if restored.remove(id) != nil { _ = take(id) } }
    package mutating func takeRestored(_ id: UUID) -> State? {
        guard restored.remove(id) != nil else { return nil }
        return take(id)
    }
    package mutating func take(_ id: UUID) -> State? {
        order.removeAll { $0 == id }; restored.remove(id)
        return states.removeValue(forKey: id)
    }
}
