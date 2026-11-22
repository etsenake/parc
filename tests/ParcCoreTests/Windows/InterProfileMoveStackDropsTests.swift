import Foundation
import Testing
@testable import ParcCore

struct InterProfileMoveStackDropsTests {
    private typealias Errands = InterProfileMoveTestsSupport.Errands
    private typealias Store = InterProfileMoveTestsSupport.Store
    private typealias Fixture = InterProfileMoveTestsSupport.Fixture

    @Test func aCrossProfileDropStacksOntoAFlatSplit() throws {
        let f = Fixture()
        let (grouped, flat) = f.groupedDestination()
        let stacked = try #require(f.propose(f.request(f.today, target: .stack(0, after: true), selection: flat.tabIDs, layout: flat), grouped))
        let column = try #require(stacked.splitLayouts.first { $0.id == flat.id })
        #expect(column.tabIDs == [f.d1.id, f.today.id, f.d2.id])
        #expect(column.stacks?.slotSizes == [2, 1])
        #expect(column.orientation == .horizontal)
        #expect(stacked.tabs.first { $0.id == f.today.id }?.profileID == f.q.id)
    }

    private func stackedSplit(_ f: Fixture) throws -> (grouped: BrowserState, flat: BrowserSplitLayout, stacked: BrowserState, column: BrowserSplitLayout) {
        let (grouped, flat) = f.groupedDestination()
        let stacked = try #require(f.propose(f.request(f.today, target: .stack(0, after: true), selection: flat.tabIDs, layout: flat), grouped))
        return (grouped, flat, stacked, try #require(stacked.splitLayouts.first { $0.id == flat.id }))
    }

    @Test func aCrossProfileDropJoinsAnExistingStackBelowTheStackedPane() throws {
        let f = Fixture()
        let s = try stackedSplit(f)
        let joined = try #require(f.propose(f.request(f.g1, target: .stack(1, after: true), selection: s.column.tabIDs, layout: s.column), s.stacked))
        let full = try #require(joined.splitLayouts.first { $0.id == s.flat.id })
        #expect(full.tabIDs == [f.d1.id, f.today.id, f.g1.id, f.d2.id])
        #expect(full.stacks?.slotSizes == [3, 1])
    }

    @Test func aFullSplitRefusesAStackDrop() throws {
        let f = Fixture()
        let s = try stackedSplit(f)
        let joined = try #require(f.propose(f.request(f.g1, target: .stack(1, after: true), selection: s.column.tabIDs, layout: s.column), s.stacked))
        let full = try #require(joined.splitLayouts.first { $0.id == s.flat.id })
        #expect(f.propose(f.request(f.g2, target: .stack(3, after: false), selection: full.tabIDs, layout: full), joined) == nil)
    }

    @Test func aFullSplitStillTakesAReplacement() throws {
        let f = Fixture()
        let s = try stackedSplit(f)
        let joined = try #require(f.propose(f.request(f.g1, target: .stack(1, after: true), selection: s.column.tabIDs, layout: s.column), s.stacked))
        let full = try #require(joined.splitLayouts.first { $0.id == s.flat.id })
        #expect(f.propose(f.request(f.g2, target: .replace(3), selection: full.tabIDs, layout: full), joined) != nil)
    }

    @Test func aSameProfileDropStacksOntoAFlatSplitKeepingItsProfile() throws {
        let f = Fixture()
        let e = Errands(f)
        let row = try #require(f.propose(e.local(f, f.today, .stack(1, after: false), e.pair), e.state))
        let layout = try #require(row.splitLayouts.first { $0.id == e.pair.id })
        #expect(layout.tabIDs == [e.tabs[0].id, f.today.id, e.tabs[1].id])
        #expect(layout.stacks?.slotSizes == [1, 2])
        #expect(layout.orientation == .vertical)
        #expect(row.tabs.first { $0.id == f.today.id }?.profileID == f.p.id)
    }

    @Test func aSameProfileDropJoinsAnExistingStack() throws {
        let f = Fixture()
        let e = Errands(f)
        let row = try #require(f.propose(e.local(f, f.today, .stack(1, after: false), e.pair), e.state))
        let rowLayout = try #require(row.splitLayouts.first { $0.id == e.pair.id })
        let grown = try #require(f.propose(e.local(f, f.g1, .stack(2, after: true), rowLayout), row))
        #expect(grown.splitLayouts.first { $0.id == e.pair.id }?.tabIDs == [e.tabs[0].id, f.today.id, e.tabs[1].id, f.g1.id])
        #expect(grown.splitLayouts.first { $0.id == e.pair.id }?.stacks?.slotSizes == [1, 3])
    }

    @MainActor @Test func aCrossProfileStackDropCommitsThroughTheReloadTransaction() throws {
        let f = Fixture()
        let (grouped, flat) = f.groupedDestination()
        let s = try Store("foreign-stack")
        let store = try s.open(grouped)
        store.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        let r = f.request(f.today, target: .stack(0, after: true), selection: flat.tabIDs, layout: flat)
        var result: Result<Bool, Error>?
        store.moveAcrossProfiles([f.today.id], proposal: { f.propose(r, $0) }) { result = $0 }
        #expect((try? result?.get()) == true)
        let saved = try BrowserStore(directory: s.directory).state.splitLayouts.first { $0.id == flat.id }
        #expect(saved?.tabIDs == [f.d1.id, f.today.id, f.d2.id])
        #expect(saved?.stacks?.slotSizes == [2, 1])
    }

    @MainActor @Test func aSameProfileStackDropCommitsWithoutAReload() throws {
        let f = Fixture()
        let e = Errands(f)
        let s = try Store("same-stack")
        let store = try s.open(e.state)
        var retired = false
        store.requestPageRetirement = { _, _, completion in retired = true; completion(false) }
        #expect(try store.commitForeignSplitDrop([f.today.id]) { f.propose(e.local(f, f.today, .stack(1, after: false), e.pair), $0) })
        #expect(!retired)
        let saved = try BrowserStore(directory: s.directory).state.splitLayouts.first { $0.id == e.pair.id }
        #expect(saved?.tabIDs == [e.tabs[0].id, f.today.id, e.tabs[1].id])
        #expect(saved?.stacks?.slotSizes == [1, 2])
    }
}
