import Foundation
import Testing
@testable import ParcCore

struct BrowserTabLookupTests {
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

    let profile = BrowserProfile(id: UUID(), name: "Lookup")
    let space: BrowserSpace
    let strangers = (0..<5).map { _ in UUID() }

    init() {
        space = BrowserSpace(id: UUID(), name: "Lookup", symbol: "circle", color: "ABCDEF", profileID: profile.id)
    }

    func tab(_ index: Int, archived: Bool) -> BrowserTab {
        let url = "https://tab-\(index).invalid/"
        var tab = BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: "Tab \(index)",
                             kind: index % 3 == 0 ? .pinned : .today, folderID: nil,
                             createdAt: Date(timeIntervalSince1970: Double(index)),
                             lastAccessed: Date(timeIntervalSince1970: Double(index)), savedURL: url, savedTitle: "Tab \(index)")
        if archived { tab.archivedAt = Date(timeIntervalSince1970: 1_000 + Double(index)) }
        return tab
    }

    func state(tabs count: Int, archivedEvery stride: Int) -> BrowserState {
        var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        state.tabs = (0..<count).map { tab($0, archived: $0 % stride == 0) }
        return state
    }

    func verify(_ state: BrowserState, probes extra: [UUID] = [], _ context: String) {
        let probes = state.tabs.map(\.id) + strangers + extra
        let predicates: [(BrowserTab) -> Bool] = [{ $0.archivedAt == nil }, { $0.archivedAt != nil }, { $0.kind == .pinned }, { _ in false }]
        check(state.openTabs == state.tabs.filter { $0.archivedAt == nil }, "\(context): open tabs")
        for matches in predicates {
            check(state.openTabs(where: matches) == state.tabs.filter { $0.archivedAt == nil && matches($0) },
                    "\(context): filtered open tabs")
            check(state.containsOpenTab(where: matches) == state.tabs.contains { $0.archivedAt == nil && matches($0) },
                    "\(context): contains open tab")
            check(state.archivedTabs(where: matches) == state.tabs.filter { $0.archivedAt != nil && matches($0) },
                    "\(context): filtered archived tabs")
        }
        for id in probes {
            check(state.tabIndex(id) == state.tabs.firstIndex { $0.id == id }, "\(context): index of \(id)")
            check(state.tab(id) == state.tabs.first { $0.id == id }, "\(context): tab \(id)")
            check(state.containsTab(id) == state.tabs.contains { $0.id == id }, "\(context): contains \(id)")
            for matches in predicates {
                check(state.tabIndex(id, where: matches) == state.tabs.firstIndex { $0.id == id && matches($0) },
                        "\(context): filtered index of \(id)")
                check(state.tab(id, where: matches) == state.tabs.first { $0.id == id && matches($0) },
                        "\(context): filtered tab \(id)")
                check(state.containsTab(id, where: matches) == state.tabs.contains { $0.id == id && matches($0) },
                        "\(context): filtered contains \(id)")
            }
        }
    }

    @Test func aNewStateAnswersLookupsWithoutATable() {
        let state = state(tabs: 60, archivedEvery: 4)
        verify(state, "without a lookup")
        #expect(state.tabLookup.lookup == nil)
    }

    @Test func attachingALookupNeverChangesEqualityOrTheSavedForm() throws {
        let state = state(tabs: 60, archivedEvery: 4)
        let published = state.attachingTabLookup(after: nil)
        #expect(published == state)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; encoder.dateEncodingStrategy = .iso8601
        #expect(try encoder.encode(published) == encoder.encode(state))
        verify(published, "fresh lookup")
    }

    @Test func randomEditsKeepEveryPublishedCopyCurrent() {
        var random = Generator(state: 0x5EED)
        var published = state(tabs: 60, archivedEvery: 4).attachingTabLookup(after: nil)
        var next = 60
        for step in 0..<100 {
            var changed = published
            switch Int.random(in: 0..<9, using: &random) {
            case 0: changed.tabs.append(tab(next, archived: Bool.random(using: &random))); next += 1
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
            verify(changed, "step \(step) before publishing")
            published = changed.attachingTabLookup(after: previous)
            verify(published, probes: previous.tabs.map(\.id), "step \(step) after publishing")
            verify(previous, probes: published.tabs.map(\.id), "step \(step) earlier copy")
        }
    }

    @Test func duplicateIdentitiesFallBackToTheFirstMatch() throws {
        let published = state(tabs: 60, archivedEvery: 4).attachingTabLookup(after: nil)
        var duplicated = published
        let first = try #require(duplicated.tabs.first)
        var twin = first; twin.archivedAt = first.archivedAt == nil ? Date(timeIntervalSince1970: 7_000) : nil
        duplicated.tabs.append(twin)
        duplicated.tabs.insert(twin, at: duplicated.tabs.count / 2)
        let ambiguous = duplicated.attachingTabLookup(after: published)
        verify(ambiguous, "duplicate identities")
        var reused = ambiguous
        reused.tabs[0].title = "Same order, new title"
        verify(reused.attachingTabLookup(after: ambiguous), "reusing an ambiguous table")
    }

    @Test func skippingAnUnreadLookupStaysCorrect() {
        let published = state(tabs: 60, archivedEvery: 4).attachingTabLookup(after: nil)
        var unread = published
        unread.tabs[0].title = "Never looked up"
        let skipped = unread.attachingTabLookup(after: published)
        var reordered = skipped
        reordered.tabs.swapAt(0, reordered.tabs.count - 1)
        verify(reordered.attachingTabLookup(after: skipped), "skipping an unread lookup after a reorder")
        var renamed = skipped
        renamed.tabs[1].title = "Renamed after an unread lookup"
        verify(renamed.attachingTabLookup(after: skipped), "skipping an unread lookup with the same order")
    }

    @Test @MainActor func theStorePublishesStatesWithACurrentLookup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-tab-lookup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var seed = state(tabs: 12, archivedEvery: 3)
        seed.selectedTabIDs = [seed.tabs[1].id]
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(seed).write(to: root.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        verify(store.state, "loaded store")
        #expect(store.state.tabLookup.lookup != nil)
        let moved = store.state.tabs[4].id, anchor = store.state.tabs[1].id
        store.reorderTab(moved, before: anchor)
        #expect(store.state.tabIndex(moved) == store.state.tabs.firstIndex { $0.id == moved })
        verify(store.state, "after reordering")
        store.refreshVisibleTabs(Set(store.state.tabs.map(\.id)))
        #expect(store.state.tabLookup.lookup != nil)
        verify(store.state, "after an activity update")
    }
}
