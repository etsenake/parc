import Foundation

final class BrowserTabLookup {
    enum Match: Equatable { case found(Int), absent, ambiguous }

    private struct Table {
        let ids: [UUID]
        let positions: [UUID: Int]
        let ambiguous: Bool
    }

    private let lock = NSLock()
    private var table: Table?
    private var predecessor: BrowserTabLookup?

    init(after previous: BrowserTabLookup?) {
        predecessor = previous?.reusableSource
    }

    func match(_ id: UUID, in tabs: [BrowserTab]) -> Match {
        let table = resolvedTable(for: tabs)
        if table.ambiguous { return .ambiguous }
        return table.positions[id].map(Match.found) ?? .absent
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

struct BrowserTabLookupSlot: Equatable {
    var lookup: BrowserTabLookup?
    static func == (_: Self, _: Self) -> Bool { true }
}

extension BrowserState {
    func attachingTabLookup(after previous: BrowserState?) -> BrowserState {
        guard tabLookup.lookup == nil else { return self }
        var result = self
        result.tabLookup.lookup = BrowserTabLookup(after: previous?.tabLookup.lookup)
        return result
    }

    func tabIndex(_ id: UUID) -> Int? {
        switch tabLookup.lookup?.match(id, in: tabs) {
        case .found(let index): return index
        case .absent: return nil
        case .ambiguous, nil: return tabs.firstIndex { $0.id == id }
        }
    }

    func tabIndex(_ id: UUID, where matches: (BrowserTab) -> Bool) -> Int? {
        switch tabLookup.lookup?.match(id, in: tabs) {
        case .found(let index): return matches(tabs[index]) ? index : nil
        case .absent: return nil
        case .ambiguous, nil: return tabs.firstIndex { $0.id == id && matches($0) }
        }
    }

    func tab(_ id: UUID) -> BrowserTab? {
        tabIndex(id).map { tabs[$0] }
    }

    func tab(_ id: UUID, where matches: (BrowserTab) -> Bool) -> BrowserTab? {
        tabIndex(id, where: matches).map { tabs[$0] }
    }

    func containsTab(_ id: UUID) -> Bool {
        tabIndex(id) != nil
    }

    func containsTab(_ id: UUID, where matches: (BrowserTab) -> Bool) -> Bool {
        tabIndex(id, where: matches) != nil
    }
}
