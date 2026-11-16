import Foundation

struct ClosedItemRecord: Equatable {
    enum Kind { case saved, archived }
    let id: UUID
    let kind: Kind
    let spaceID: UUID
    let profileID: UUID
    let tabs: [BrowserTab]
    let split: BrowserSplitLayout?
    let focusedTabID: UUID
    var membership: ClosedSplitMembership? = nil
    var tabIDs: [UUID] { tabs.map(\.id) }

    func isValid(in state: BrowserState) -> Bool {
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

struct ClosedSplitMembership: Equatable {
    let layout: BrowserSplitLayout
    let index: Int
    let dissolved: Bool
    let closedSiblings: Set<UUID>

    func restoredLayout(restoring id: UUID, in state: BrowserState,
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
        if group.sidebarAnchorID.map({ members.contains($0) }) != true { group.sidebarAnchorID = members.first }
        return group
    }
}

struct ClosedItemIntent {
    let spaceID: UUID
    let profileID: UUID
    let tabs: [BrowserTab]
    let focusedTabID: UUID?
    let completeSplits: [BrowserSplitLayout]
    let partialSplits: [BrowserSplitLayout]
    init?(ids: Set<UUID>, state: BrowserState, spaceID: UUID, profileID: UUID, focusedTabID: UUID?) {
        let tabs = state.tabs.filter { ids.contains($0.id) && $0.archivedAt == nil }
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

    func membership(of id: UUID, in state: BrowserState) -> ClosedSplitMembership? {
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

struct ClosedPeekRecord: Equatable {
    let id: UUID
    let url: URL
    let parentTabID: UUID
    let profileID: UUID

    func isValid(in state: BrowserState) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && state.profiles.contains(where: { $0.id == profileID })
            && !state.profileRemovals.contains(where: { $0.profileID == profileID })
            && state.containsTab(parentTabID, where: { $0.archivedAt == nil && $0.profileID == profileID })
    }
}

enum ClosedItemStep {
    case items(ClosedItemRecord)
    case peek(ClosedPeekRecord)
    case folder(FolderDeletionUndo)

    var id: UUID {
        switch self {
        case .items(let record): return record.id
        case .peek(let record): return record.id
        case .folder(let undo): return undo.id
        }
    }
}

struct WindowClosedItems {
    private var saved: ClosedItemRecord?
    private var groups: [[ClosedItemStep]] = []
    private(set) var itemLastActiveDates: [UUID: Date]

    init(itemLastActiveDates: [UUID: Date] = [:]) {
        self.itemLastActiveDates = itemLastActiveDates
    }

    mutating func recordSelection(_ ids: [UUID], focusedTabID: UUID?, state: BrowserState,
                                  at date: Date = Date()) {
        let available = Set(state.tabs.filter { $0.archivedAt == nil }.map(\.id))
        itemLastActiveDates = itemLastActiveDates.filter { available.contains($0.key) }
        guard !ids.isEmpty, Set(ids).isSubset(of: available),
              let focus = focusedTabID, ids.contains(focus) else { return }
        itemLastActiveDates[focus] = date
    }

    mutating func record(_ intent: ClosedItemIntent, in state: BrowserState) {
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

    mutating func recordPeek(_ record: ClosedPeekRecord, in state: BrowserState) {
        guard record.isValid(in: state) else { return }
        groups.append([.peek(record)])
    }

    mutating func recordFolderDeletion(_ undo: FolderDeletionUndo) {
        saved = nil
        groups.append([.folder(undo)])
    }

    mutating func nextStep(in state: BrowserState,
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
    mutating func next(in state: BrowserState) -> ClosedItemRecord? {
        guard case .items(let record)? = nextStep(in: state, restorable: { _ in true }) else { return nil }
        return record
    }
    @discardableResult mutating func consume(_ record: ClosedItemRecord) -> Bool { consume(stepID: record.id) }
    @discardableResult mutating func consume(stepID: UUID) -> Bool {
        if saved?.id == stepID { saved = nil; return true }
        guard saved == nil, groups.last?.last?.id == stepID else { return false }
        groups[groups.count - 1].removeLast()
        if groups.last?.isEmpty == true { groups.removeLast() }
        return true
    }
    mutating func selected(_ ids: [UUID]) {
        if let saved, !Set(ids).isDisjoint(with: saved.tabIDs) { self.saved = nil }
    }
}

struct ClosedPageHistory<State> {
    let limit: Int
    private var states: [UUID: State] = [:]
    private var order: [UUID] = []
    private var restored: Set<UUID> = []
    init(limit: Int = 100) { self.limit = limit }

    mutating func closed(_ id: UUID, state: State) {
        if states.updateValue(state, forKey: id) != nil { order.removeAll { $0 == id } }
        order.append(id); restored.remove(id)
        while order.count > limit {
            let oldest = order.removeFirst()
            states.removeValue(forKey: oldest); restored.remove(oldest)
        }
    }
    mutating func restore(_ ids: some Sequence<UUID>) {
        for id in ids where states[id] != nil { restored.insert(id) }
    }
    mutating func unrestore(_ ids: some Sequence<UUID>) { restored.subtract(ids) }
    mutating func pageCreated(_ id: UUID) { if restored.remove(id) != nil { _ = take(id) } }
    mutating func takeRestored(_ id: UUID) -> State? {
        guard restored.remove(id) != nil else { return nil }
        return take(id)
    }
    mutating func take(_ id: UUID) -> State? {
        order.removeAll { $0 == id }; restored.remove(id)
        return states.removeValue(forKey: id)
    }
}
