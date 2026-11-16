import Foundation

struct RecentTabOrder {
    struct Item: Identifiable {
        var tabIDs: [UUID]
        var focusedTabID: UUID
        var spaceID: UUID
        var profileID: UUID
        var orientation: SplitOrientation
        var id: String { tabIDs.map(\.uuidString).joined(separator: ":") }
    }
    private var recency: [String] = []
    private var lastFocus: [String: UUID] = [:]

    mutating func record(_ ids: [UUID], focus: UUID?) {
        guard let first = ids.first else { return }
        let key = ids.map(\.uuidString).joined(separator: ":")
        lastFocus[key] = focus.flatMap { ids.contains($0) ? $0 : nil } ?? first
        if recency.first != key { recency.removeAll { $0 == key }; recency.insert(key, at: 0) }
    }

    mutating func items(state: BrowserState, selected: [UUID], currentSpace: UUID,
                        available: (UUID) -> Bool) -> [Item] {
        let tabs = Dictionary(uniqueKeysWithValues: state.openTabs(where: { available($0.id) }).map { ($0.id, $0) })
        let spaces = Dictionary(uniqueKeysWithValues: state.spaces.map { ($0.id, $0) })
        var result: [Item] = [], assigned = Set<UUID>()
        func append(_ ids: [UUID], spaceID: UUID, orientation: SplitOrientation) {
            guard !ids.isEmpty, Set(ids).count == ids.count,
                  let space = spaces[spaceID], ids.allSatisfy({ id in
                      guard let tab = tabs[id] else { return false }
                      return !assigned.contains(id) && tab.profileID == space.profileID
                          && (tab.kind == .favorite || tab.spaceID == spaceID)
                  }) else { return }
            let key = ids.map(\.uuidString).joined(separator: ":")
            result.append(Item(tabIDs: ids, focusedTabID: lastFocus[key].flatMap { ids.contains($0) ? $0 : nil } ?? ids[0],
                               spaceID: spaceID, profileID: space.profileID, orientation: orientation))
            assigned.formUnion(ids)
        }
        let selectedLayout = SidebarSplitItems.groups(in: state, spaceID: currentSpace).first { $0.tabIDs == selected }
        append(selected, spaceID: currentSpace, orientation: selectedLayout?.orientation ?? .horizontal)
        for layout in state.splitLayouts.reversed() where layout.tabIDs.count > 1 {
            append(layout.tabIDs, spaceID: layout.spaceID, orientation: layout.orientation)
        }
        for tab in state.tabs { append([tab.id], spaceID: tab.spaceID, orientation: .horizontal) }
        let keys = Set(result.map(\.id))
        recency.removeAll { !keys.contains($0) }; lastFocus = lastFocus.filter { keys.contains($0.key) }
        let ranks = Dictionary(uniqueKeysWithValues: recency.enumerated().map { ($0.element, $0.offset) })
        return result.sorted { left, right in
            let l = ranks[left.id], r = ranks[right.id]
            if l != nil || r != nil { return (l ?? Int.max) < (r ?? Int.max) }
            let ld = left.tabIDs.compactMap { tabs[$0]?.lastAccessed }.max() ?? .distantPast
            let rd = right.tabIDs.compactMap { tabs[$0]?.lastAccessed }.max() ?? .distantPast
            return ld == rd ? left.id < right.id : ld > rd
        }
    }
}

struct RecentTabSwitcherSelection {
    static let maximumDisplayedItems = 5
    private(set) var itemIDs: [String]
    private(set) var focusedIndex: Int
    var displayedIDs: ArraySlice<String> { itemIDs.prefix(Self.maximumDisplayedItems) }

    init(itemIDs: [String], currentID: String?, forward: Bool) {
        var seen = Set<String>()
        self.itemIDs = Array(itemIDs.filter { seen.insert($0).inserted }.prefix(Self.maximumDisplayedItems + 1))
        let count = min(self.itemIDs.count, Self.maximumDisplayedItems)
        if let currentID, let index = self.itemIDs.prefix(count).firstIndex(of: currentID), count > 0 {
            focusedIndex = (index + (forward ? 1 : count - 1)) % count
        } else { focusedIndex = forward ? 0 : max(0, count - 1) }
    }

    mutating func focus(_ index: Int) {
        let count = displayedIDs.count
        guard count > 0 else { focusedIndex = 0; return }
        focusedIndex = (index % count + count) % count
    }

    mutating func didClose(_ id: String, availableIDs: [String]) {
        let available = Set(availableIDs).subtracting([id])
        var seen = Set<String>()
        itemIDs = Array((itemIDs + availableIDs).filter {
            available.contains($0) && seen.insert($0).inserted
        }.prefix(Self.maximumDisplayedItems + 1))
        focusedIndex = min(focusedIndex, max(0, displayedIDs.count - 1))
    }
}

struct RecentTabSwitcherInput {
    static let modifierMask: UInt = 0x1E_0000
    static let control: UInt = 0x4_0000
    enum KeyAction: Equatable { case forward, backward, cancel, close, consume }
    let continuationFlags: [UInt]

    init(next: UInt?, previous: UInt?) {
        continuationFlags = [next, previous, Self.control].compactMap { $0.map { $0 & Self.modifierMask } }
    }

    func isHolding(_ flags: UInt) -> Bool {
        flags & continuationFlags.reduce(0, |) != 0
    }

    func continues(_ flags: UInt) -> Bool {
        continuationFlags.contains(flags & Self.modifierMask)
    }

    func keyDown(matchesNext: Bool, matchesPrevious: Bool, keyCode: UInt16, flags: UInt) -> KeyAction {
        if matchesNext { return .forward }
        if matchesPrevious { return .backward }
        if keyCode == 50 && flags & Self.modifierMask == Self.control { return .backward }
        switch keyCode {
        case 123: return .backward
        case 124: return .forward
        case 53: return .cancel
        case 13: return .close
        default: return .consume
        }
    }
}
