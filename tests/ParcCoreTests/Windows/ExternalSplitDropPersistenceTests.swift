import Foundation
import Testing
@testable import ParcCore

struct ExternalSplitDropPersistenceTests {
    private typealias Fixture = ExternalSplitDropTestsSupport.Fixture

    @MainActor @Test func aFavoriteSplitCommitsAtomicallyThroughTheStore() throws {
        let f = try Fixture()
        let store = try BrowserStore(directory: f.session(f.favorite(), "favorite"))
        #expect(try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical, savedHomeID: f.homeID))
    }

    @MainActor @Test func theSavedHomeAndLivePlacementSurviveAReload() throws {
        let f = try Fixture()
        let directory = try f.session(f.favorite(), "favorite")
        let original = f.favorite().tabs[f.aIndex]
        let store = try BrowserStore(directory: directory)
        _ = try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical, savedHomeID: f.homeID)
        let loaded = try BrowserStore(directory: directory)
        #expect(loaded.state.tabs.contains { $0.id == f.homeID && $0.url == original.savedURL })
        #expect(loaded.state.tabs.contains { $0.id == f.a && $0.kind == .today })
    }

    @MainActor @Test func aFailedFavoriteCommitKeepsTheOriginalStateExactly() throws {
        let f = try Fixture()
        let directory = try f.session(f.favorite(), "favorite-failure")
        let store = try BrowserStore(directory: directory)
        let before = store.state
        try f.breakWrites(in: directory)
        #expect(throws: (any Error).self) {
            _ = try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical, savedHomeID: f.homeID)
        }
        #expect(store.state == before)
        #expect(store.persistenceError != nil)
    }

    @MainActor @Test func aPinnedSplitCommitReopensWithHomeOrderAndLiveSelectionTogether() throws {
        let f = try Fixture()
        let directory = try f.session(f.pinned(), "pinned")
        let store = try BrowserStore(directory: directory)
        #expect(try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(0), orientation: .vertical, savedHomeID: f.homeID))
        let reloaded = try BrowserStore(directory: directory)
        #expect(SidebarHierarchy.children(in: f.pinnedContainer, state: reloaded.state) == [.tab(f.b), .tab(f.homeID), .folder(f.siblingFolderID)])
        #expect(reloaded.state.selectedTabIDs == [f.urlID, f.a])
    }

    @MainActor @Test func aFlatSplitReopensAsAFlatSplit() throws {
        let f = try Fixture()
        let store = try BrowserStore(directory: f.session(f.original, "stack"))
        #expect(store.activeSplitLayout?.id == f.group.id)
        #expect(store.activeSplitLayout?.stacks == nil)
    }

    @MainActor @Test func aLinkOnTheTopBandOfAFlatSplitCommitsAStack() throws {
        let f = try Fixture()
        let store = try BrowserStore(directory: f.session(f.original, "stack"))
        #expect(try f.commit(store, selection: [f.a, f.b], layout: store.activeSplitLayout, target: .stack(1, after: false)))
    }

    @MainActor @Test func theStackedTabAndItsStackReopenTogether() throws {
        let f = try Fixture()
        let directory = try f.session(f.original, "stack")
        let store = try BrowserStore(directory: directory)
        let id = UUID()
        _ = try f.commit(store, id: id, selection: [f.a, f.b], layout: store.activeSplitLayout, target: .stack(1, after: false))
        let reloaded = try BrowserStore(directory: directory)
        #expect(reloaded.state.selectedTabIDs == [f.a, id, f.b])
        #expect(reloaded.activeSplitLayout?.id == f.group.id)
        #expect(reloaded.activeSplitLayout?.orientation == .horizontal)
        #expect(reloaded.activeSplitLayout?.stacks?.slotSizes == [1, 2])
        #expect(reloaded.state.tabs.first { $0.id == id }?.url == f.destination.absoluteString)
    }

    @MainActor @Test func aLinkJoinsAnExistingStackBelowTheStackedPane() throws {
        let f = try Fixture()
        let store = try BrowserStore(directory: f.session(f.original, "stack"))
        let stackID = UUID(), joinID = UUID()
        _ = try f.commit(store, id: stackID, selection: [f.a, f.b], layout: store.activeSplitLayout, target: .stack(1, after: false))
        #expect(try f.commit(store, id: joinID, selection: [f.a, stackID, f.b], layout: store.activeSplitLayout, target: .stack(2, after: true)))
        #expect(store.state.selectedTabIDs == [f.a, stackID, f.b, joinID])
        #expect(store.activeSplitLayout?.stacks?.slotSizes == [1, 3])
        #expect(store.activeSplitLayout?.id == f.group.id)
    }

    @MainActor @Test func aFullStackedSplitRefusesAnotherLink() throws {
        let f = try Fixture()
        let store = try BrowserStore(directory: f.session(f.original, "stack"))
        _ = try f.commit(store, selection: [f.a, f.b], layout: store.activeSplitLayout, target: .stack(1, after: false))
        let second = UUID()
        _ = try f.commit(store, id: second, selection: store.state.selectedTabIDs, layout: store.activeSplitLayout, target: .stack(2, after: true))
        let full = store.state
        #expect(try !f.commit(store, selection: full.selectedTabIDs, layout: store.activeSplitLayout, target: .stack(0, after: false)))
        #expect(store.state == full)
    }
}
