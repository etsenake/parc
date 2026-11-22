import Foundation
import Testing
@testable import ParcCore

struct InterProfileMoveWindowDropsTests {
    private typealias Errands = InterProfileMoveTestsSupport.Errands
    private typealias Store = InterProfileMoveTestsSupport.Store
    private typealias Fixture = InterProfileMoveTestsSupport.Fixture

    @Test func aSameProfileOtherWindowDropKeepsTheProfileAndJoinsTheOtherSpace() throws {
        let f = Fixture()
        let e = Errands(f)
        let r = ForeignSplitDrop.Request(source: f.today, sourceHomeID: UUID(), spaceID: e.other.id, profileID: f.p.id,
            selection: [e.tabs[0].id], layout: nil, target: .insert(1), orientation: .vertical, destinationHomeIDs: [:])
        var state = f.state
        state.spaces.append(e.other)
        state.tabs.append(e.tabs[0])
        let moved = try #require(f.propose(r, state))
        let live = try #require(moved.tabs.first { $0.id == f.today.id })
        #expect(live.profileID == f.p.id)
        #expect(live.spaceID == e.other.id)
        #expect(live.url == f.today.url)
        #expect(moved.splitLayouts.contains { $0.tabIDs == [e.tabs[0].id, f.today.id] && $0.orientation == .vertical })
    }

    @Test func aSameSpaceOtherWindowDropLeavesTheSourcesSavedHome() throws {
        let f = Fixture()
        var same = f.state
        let home = UUID()
        let r = ForeignSplitDrop.Request(source: f.pinned, sourceHomeID: home, spaceID: f.s.id, profileID: f.p.id,
            selection: [f.sibling.id], layout: nil, target: .insert(0), orientation: .horizontal, destinationHomeIDs: [f.sibling.id: UUID()])
        same.activeSpaceID = f.s.id
        let placed = try #require(f.propose(r, same))
        #expect(placed.tabs.contains { $0.id == home && $0.kind == .pinned && $0.url == f.pinned.savedURL })
        #expect(placed.selectedTabIDs == [f.pinned.id, f.sibling.id])
    }

    @MainActor @Test func aSameProfilePlacementCommitsWithoutAReloadAndPersists() throws {
        let f = Fixture()
        let e = Errands(f)
        let s = try Store("foreign-drop")
        let r = ForeignSplitDrop.Request(source: f.today, sourceHomeID: UUID(), spaceID: e.other.id, profileID: f.p.id,
            selection: [e.tabs[0].id], layout: nil, target: .insert(1), orientation: .vertical, destinationHomeIDs: [:])
        var withErrands = f.state
        withErrands.spaces.append(e.other)
        withErrands.tabs.append(e.tabs[0])
        let store2 = try s.open(withErrands)
        var retired = false
        store2.requestPageRetirement = { _, _, completion in retired = true; completion(false) }
        #expect(try store2.commitForeignSplitDrop([f.today.id]) { ForeignSplitDrop.proposal(r, state: $0, now: Date(), creation: nil) })
        #expect(!retired)
        #expect(try BrowserStore(directory: s.directory).state.tabs.first { $0.id == f.today.id }?.spaceID == e.other.id)
    }

    @MainActor @Test func aProfileChangeCannotSkipTheReloadTransaction() throws {
        let f = Fixture()
        let s = try Store("foreign-cross")
        let store = try s.open(f.state)
        let cross = ForeignSplitDrop.Request(source: f.g1, sourceHomeID: UUID(), spaceID: f.d.id, profileID: f.q.id,
            selection: [f.d1.id], layout: nil, target: .insert(1), orientation: .horizontal, destinationHomeIDs: [:])
        #expect(try store.commitForeignSplitDrop([f.g1.id]) { ForeignSplitDrop.proposal(cross, state: $0, now: Date(), creation: nil) } == false)
    }
}
