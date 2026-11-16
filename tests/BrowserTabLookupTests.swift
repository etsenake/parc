import Foundation

@main @MainActor
struct BrowserTabLookupTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }

    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func tab(_ index: Int, space: BrowserSpace, archived: Bool) -> BrowserTab {
        let url = "https://tab-\(index).invalid/"
        var tab = BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: "Tab \(index)",
                             kind: index % 3 == 0 ? .pinned : .today, folderID: nil,
                             createdAt: Date(timeIntervalSince1970: Double(index)),
                             lastAccessed: Date(timeIntervalSince1970: Double(index)), savedURL: url, savedTitle: "Tab \(index)")
        if archived { tab.archivedAt = Date(timeIntervalSince1970: 1_000 + Double(index)) }
        return tab
    }

    static func verify(_ state: BrowserState, probes extra: [UUID], _ context: String) throws {
        let probes = state.tabs.map(\.id) + extra
        let predicates: [(BrowserTab) -> Bool] = [{ $0.archivedAt == nil }, { $0.archivedAt != nil }, { $0.kind == .pinned }, { _ in false }]
        for id in probes {
            try check(state.tabIndex(id) == state.tabs.firstIndex { $0.id == id }, "\(context): index of \(id)")
            try check(state.tab(id) == state.tabs.first { $0.id == id }, "\(context): tab \(id)")
            try check(state.containsTab(id) == state.tabs.contains { $0.id == id }, "\(context): contains \(id)")
            for matches in predicates {
                try check(state.tabIndex(id, where: matches) == state.tabs.firstIndex { $0.id == id && matches($0) },
                          "\(context): filtered index of \(id)")
                try check(state.tab(id, where: matches) == state.tabs.first { $0.id == id && matches($0) },
                          "\(context): filtered tab \(id)")
                try check(state.containsTab(id, where: matches) == state.tabs.contains { $0.id == id && matches($0) },
                          "\(context): filtered contains \(id)")
            }
        }
    }

    static func main() throws {
        let profile = BrowserProfile(id: UUID(), name: "Lookup")
        let space = BrowserSpace(id: UUID(), name: "Lookup", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        var random = Generator(state: 0x5EED)
        var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        state.tabs = (0..<60).map { tab($0, space: space, archived: $0 % 4 == 0) }
        let strangers = (0..<5).map { _ in UUID() }

        try verify(state, probes: strangers, "without a lookup")
        try check(state.tabLookup.lookup == nil, "a newly built state starts without a lookup")
        var published = state.attachingTabLookup(after: nil)
        try check(published == state, "a lookup never changes equality")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; encoder.dateEncodingStrategy = .iso8601
        try check(try encoder.encode(published) == encoder.encode(state), "a lookup is never saved")
        try verify(published, probes: strangers, "fresh lookup")

        var next = 60
        for step in 0..<400 {
            var changed = published
            switch Int.random(in: 0..<9, using: &random) {
            case 0: changed.tabs.append(tab(next, space: space, archived: Bool.random(using: &random))); next += 1
            case 1 where !changed.tabs.isEmpty: changed.tabs.remove(at: Int.random(in: 0..<changed.tabs.count, using: &random))
            case 2 where changed.tabs.count > 1:
                let item = changed.tabs.remove(at: Int.random(in: 0..<changed.tabs.count, using: &random))
                changed.tabs.insert(item, at: Int.random(in: 0...changed.tabs.count, using: &random))
            case 3 where !changed.tabs.isEmpty:
                let index = Int.random(in: 0..<changed.tabs.count, using: &random)
                changed.tabs[index].archivedAt = changed.tabs[index].archivedAt == nil ? Date(timeIntervalSince1970: 5_000) : nil
            case 4 where !changed.tabs.isEmpty:
                changed.tabs[Int.random(in: 0..<changed.tabs.count, using: &random)].title = "Renamed \(step)"
            case 5 where !changed.tabs.isEmpty:
                changed.tabs[Int.random(in: 0..<changed.tabs.count, using: &random)].id = UUID()
            case 6 where changed.tabs.count > 1:
                changed.tabs.swapAt(Int.random(in: 0..<changed.tabs.count, using: &random),
                                    Int.random(in: 0..<changed.tabs.count, using: &random))
            case 7: changed.tabs.removeAll { $0.archivedAt != nil && Bool.random(using: &random) }
            default: changed.activeSpaceID = space.id
            }
            let previous = published
            try verify(changed, probes: strangers, "step \(step) before publishing")
            published = changed.attachingTabLookup(after: previous)
            try verify(published, probes: strangers + previous.tabs.map(\.id), "step \(step) after publishing")
            try verify(previous, probes: strangers + published.tabs.map(\.id), "step \(step) earlier copy")
        }

        var duplicated = published
        if let first = duplicated.tabs.first {
            var twin = first; twin.archivedAt = first.archivedAt == nil ? Date(timeIntervalSince1970: 7_000) : nil
            duplicated.tabs.append(twin)
            duplicated.tabs.insert(twin, at: duplicated.tabs.count / 2)
        }
        let ambiguous = duplicated.attachingTabLookup(after: published)
        try verify(ambiguous, probes: strangers, "duplicate identities")

        var reused = ambiguous
        reused.tabs[0].title = "Same order, new title"
        try verify(reused.attachingTabLookup(after: ambiguous), probes: strangers, "reusing an ambiguous table")

        var unread = published
        unread.tabs[0].title = "Never looked up"
        let skipped = unread.attachingTabLookup(after: published)
        var reordered = skipped
        reordered.tabs.swapAt(0, reordered.tabs.count - 1)
        try verify(reordered.attachingTabLookup(after: skipped), probes: strangers, "skipping an unread lookup after a reorder")
        var renamed = skipped
        renamed.tabs[1].title = "Renamed after an unread lookup"
        try verify(renamed.attachingTabLookup(after: skipped), probes: strangers, "skipping an unread lookup with the same order")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-tab-lookup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var seed = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        seed.tabs = (0..<12).map { tab($0, space: space, archived: $0 % 3 == 0) }
        seed.selectedTabIDs = [seed.tabs[1].id]
        try encoder.encode(seed).write(to: root.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        try verify(store.state, probes: strangers, "loaded store")
        try check(store.state.tabLookup.lookup != nil, "the store publishes states with a lookup")
        let moved = store.state.tabs[4].id, anchor = store.state.tabs[1].id
        store.reorderTab(moved, before: anchor)
        try check(store.state.tabIndex(moved) == store.state.tabs.firstIndex { $0.id == moved }, "reordering keeps lookups current")
        try verify(store.state, probes: strangers, "after reordering")
        store.refreshVisibleTabs(Set(store.state.tabs.map(\.id)))
        try check(store.state.tabLookup.lookup != nil, "activity-only updates keep a lookup")
        try verify(store.state, probes: strangers, "after an activity update")
        print("BrowserTabLookupTests passed \(count) checks")
    }
}
