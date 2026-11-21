import Foundation

package final class BrowserTabLookup {
    package enum Match: Equatable { case found(Int), absent, ambiguous }

    private struct Table {
        let ids: [UUID]
        let positions: [UUID: Int]
        let ambiguous: Bool

        package init(ids: [UUID], positions: [UUID: Int], ambiguous: Bool) {
            self.ids = ids
            self.positions = positions
            self.ambiguous = ambiguous
        }
    }

    private let lock = NSLock()
    private var table: Table?
    private var predecessor: BrowserTabLookup?
    private var open: [BrowserTab]?
    private var archived: [BrowserTab]?

    package init(after previous: BrowserTabLookup?) {
        predecessor = previous?.reusableSource
    }

    package func match(_ id: UUID, in tabs: [BrowserTab]) -> Match {
        let table = resolvedTable(for: tabs)
        if table.ambiguous { return .ambiguous }
        return table.positions[id].map(Match.found) ?? .absent
    }

    package func openTabs(in tabs: [BrowserTab]) -> [BrowserTab] {
        lock.lock(); defer { lock.unlock() }
        if let open { return open }
        let built = tabs.filter { $0.archivedAt == nil }
        open = built
        return built
    }

    package func archivedTabs(in tabs: [BrowserTab]) -> [BrowserTab] {
        lock.lock(); defer { lock.unlock() }
        if let archived { return archived }
        let built = tabs.filter { $0.archivedAt != nil }
        archived = built
        return built
    }

    private var reusableSource: BrowserTabLookup? {
        lock.lock(); defer { lock.unlock() }
        return table == nil ? predecessor : self
    }

    private var builtTable: Table? {
        lock.lock(); defer { lock.unlock() }
        return table
    }

    private func resolvedTable(for tabs: [BrowserTab]) -> Table {
        lock.lock(); defer { lock.unlock() }
        if let table { return table }
        let previous = predecessor?.builtTable
        predecessor = nil
        let resolved: Table
        if let previous, previous.ids.count == tabs.count, zip(previous.ids, tabs).allSatisfy({ $0 == $1.id }) {
            resolved = previous
        } else {
            resolved = Self.table(for: tabs)
        }
        table = resolved
        return resolved
    }

    private static func table(for tabs: [BrowserTab]) -> Table {
        var positions = [UUID: Int](minimumCapacity: tabs.count)
        var ambiguous = false
        for index in tabs.indices where positions.updateValue(index, forKey: tabs[index].id) != nil {
            ambiguous = true
        }
        return Table(ids: tabs.map(\.id), positions: positions, ambiguous: ambiguous)
    }
}

package struct BrowserTabLookupSlot: Equatable {
    package var lookup: BrowserTabLookup?
    package static func == (_: Self, _: Self) -> Bool { true }
}

extension BrowserState {
    package func attachingTabLookup(after previous: BrowserState?) -> BrowserState {
        guard tabLookup.lookup == nil else { return self }
        var result = self
        result.tabLookup.lookup = BrowserTabLookup(after: previous?.tabLookup.lookup)
        return result
    }

    package func tabIndex(_ id: UUID) -> Int? {
        switch tabLookup.lookup?.match(id, in: tabs) {
        case .found(let index): return index
        case .absent: return nil
        case .ambiguous, nil: return tabs.firstIndex { $0.id == id }
        }
    }

    package func tabIndex(_ id: UUID, where matches: (BrowserTab) -> Bool) -> Int? {
        switch tabLookup.lookup?.match(id, in: tabs) {
        case .found(let index): return matches(tabs[index]) ? index : nil
        case .absent: return nil
        case .ambiguous, nil: return tabs.firstIndex { $0.id == id && matches($0) }
        }
    }

    package func tab(_ id: UUID) -> BrowserTab? {
        tabIndex(id).map { tabs[$0] }
    }

    package func tab(_ id: UUID, where matches: (BrowserTab) -> Bool) -> BrowserTab? {
        tabIndex(id, where: matches).map { tabs[$0] }
    }

    package func containsTab(_ id: UUID) -> Bool {
        tabIndex(id) != nil
    }

    package func containsTab(_ id: UUID, where matches: (BrowserTab) -> Bool) -> Bool {
        tabIndex(id, where: matches) != nil
    }

    package var openTabs: [BrowserTab] {
        tabLookup.lookup?.openTabs(in: tabs) ?? tabs.filter { $0.archivedAt == nil }
    }

    package func openTabs(where matches: (BrowserTab) -> Bool) -> [BrowserTab] {
        guard let lookup = tabLookup.lookup else { return tabs.filter { $0.archivedAt == nil && matches($0) } }
        return lookup.openTabs(in: tabs).filter(matches)
    }

    package func containsOpenTab(where matches: (BrowserTab) -> Bool) -> Bool {
        guard let lookup = tabLookup.lookup else { return tabs.contains { $0.archivedAt == nil && matches($0) } }
        return lookup.openTabs(in: tabs).contains(where: matches)
    }

    package func archivedTabs(where matches: (BrowserTab) -> Bool) -> [BrowserTab] {
        guard let lookup = tabLookup.lookup else { return tabs.filter { $0.archivedAt != nil && matches($0) } }
        return lookup.archivedTabs(in: tabs).filter(matches)
    }
}
