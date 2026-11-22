import Combine
import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSpaceHierarchyTests {
    @MainActor
    private struct HierarchyFixture {
        let store: BrowserStore
        let space: UUID
        let root: SidebarContainerLocation
        let first: UUID
        let second: UUID
        let parent: UUID
        let nested: UUID
        let peer: UUID
        let today: UUID

        var inside: SidebarContainerLocation { .init(spaceID: space, folderID: parent, section: .pinned) }

        func snapshot() -> SidebarHierarchySnapshot {
            SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: store.activeSpace.profileID)!
        }

        func batchedMatches() -> Bool {
            let state = store.state
            let batched = SidebarHierarchy.childrenByContainer(spaceID: space, state: state)
            let locations = [root, SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)]
                + state.folders.filter { $0.spaceID == space }.map { SidebarContainerLocation(spaceID: space, folderID: $0.id, section: .pinned) }
            return locations.allSatisfy { (batched[$0.key] ?? []) == SidebarHierarchy.children(in: $0, state: state) }
        }

        func nestFirstTab() throws {
            store.toggleFolder(parent)
            try #require(try store.moveSidebarItem(.tab(first), to: inside, before: .folder(nested), expected: snapshot()))
        }

        func formSplit() throws -> (BrowserSplitLayout, BrowserTab) {
            try nestFirstTab()
            try #require(try store.moveSidebarItem(.tab(today), to: inside, before: .tab(first), expected: snapshot()))
            try #require(try store.moveSidebarItem(.folder(nested), to: root, before: .folder(peer), expected: snapshot()))
            store.selectTab(first)
            store.selectTab(second, extendingSplit: true)
            let group = try #require(store.activeSplitLayout)
            let home = try BrowserStoreTestsSupport.expectHome(of: first, in: store, savedURL: "https://one.example.org")
            return (group, home)
        }

        func moveSplitIntoTheFolder(_ group: BrowserSplitLayout) throws {
            try #require(try store.moveSidebarItem(.split(group.id), to: inside, before: .tab(today), expected: snapshot()))
        }
    }

    @MainActor
    private static func hierarchy(in directory: URL) throws -> HierarchyFixture {
        let store = try BrowserStore(directory: directory)
        let space = store.activeSpaceID
        let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
        let first = store.open("https://one.example.org", kind: .pinned)
        let second = store.open("https://two.example.org", kind: .pinned)
        let parent = store.createFolder(name: "Parent")
        let nested = store.createFolder(name: "Nested", parentID: parent)
        let peer = store.createFolder(name: "Peer")
        let today = store.open("https://today.example.org")
        return HierarchyFixture(store: store, space: space, root: root, first: first, second: second,
                                parent: parent, nested: nested, peer: peer, today: today)
    }

    @Test @MainActor static func aLegacySidebarKeepsTabThenFolderOrder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try hierarchy(in: directory)
            let store = fixture.store
            let root = fixture.root
            let first = fixture.first
            let second = fixture.second
            let parent = fixture.parent
            let peer = fixture.peer
            #expect(SidebarHierarchy.children(in: root, state: store.state) == [.tab(first), .tab(second), .folder(parent), .folder(peer)], "Legacy sessions preserve their prior tab-then-folder order")
            #expect(fixture.batchedMatches(), "Every container's children match in one pass, legacy order")
        }
    }

    @Test @MainActor static func aFolderReordersAmongTabsInOnePublication() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try hierarchy(in: directory)
            let store = fixture.store
            let root = fixture.root
            let first = fixture.first
            let second = fixture.second
            let parent = fixture.parent
            let peer = fixture.peer
            let original = store.state
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            #expect(try store.moveSidebarItem(.folder(peer), to: root, before: .tab(second), expected: fixture.snapshot()), "Folders reorder among tabs in a typed shared container")
            #expect(SidebarHierarchy.children(in: root, state: store.state) == [.tab(first), .folder(peer), .tab(second), .folder(parent)], "Mixed sibling insertion is exact")
            #expect(fixture.batchedMatches(), "Every container's children match in one pass, stored mixed order")
            #expect(publications == 1, "The complete move publishes once")
            #expect(store.state.tabs == original.tabs && store.state.selectedTabIDs == original.selectedTabIDs && store.state.history == original.history, "Reordering preserves original pages, selection and history metadata")
            observation.cancel()
        }
    }

    @Test @MainActor static func aChangedDisclosureRejectsAStaleMove() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try hierarchy(in: directory)
            let store = fixture.store
            let parent = fixture.parent
            let first = fixture.first
            let inside = fixture.inside
            let stale = fixture.snapshot()
            store.toggleFolder(parent)
            #expect(!(try store.moveSidebarItem(.tab(first), to: inside, before: nil, expected: stale)), "Changed hierarchy/disclosure rejects a stale capability")
        }
    }

    @Test @MainActor static func nestingATabBeforeAFolderRevealsTheDestination() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try hierarchy(in: directory)
            let store = fixture.store
            let parent = fixture.parent
            let first = fixture.first
            let inside = fixture.inside
            let nested = fixture.nested
            store.toggleFolder(parent)
            #expect(try store.moveSidebarItem(.tab(first), to: inside, before: .folder(nested), expected: fixture.snapshot()), "A tab nests before a folder without replacing either")
            #expect(store.state.folders.first { $0.id == parent }?.isExpanded == true, "A committed drop reveals its destination")
            #expect(SidebarHierarchy.children(in: inside, state: store.state) == [.tab(first), .folder(nested)], "Nested mixed order is durable")
        }
    }

    @Test @MainActor static func movingATodayTabIntoAFolderPinsItsLiveDestination() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try hierarchy(in: directory)
            let store = fixture.store
            let today = fixture.today
            let inside = fixture.inside
            let first = fixture.first
            try fixture.nestFirstTab()
            #expect(try store.moveSidebarItem(.tab(today), to: inside, before: .tab(first), expected: fixture.snapshot()), "Today can move into a genuine pinned folder")
            #expect(try BrowserStoreTestsSupport.tab(today, in: store).kind == .pinned && (try BrowserStoreTestsSupport.tab(today, in: store)).savedURL == "https://today.example.org", "Pinning retains the original live destination")
        }
    }

    @Test @MainActor static func outdentingAFolderPreservesItsIdentity() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try hierarchy(in: directory)
            let store = fixture.store
            let root = fixture.root
            let nested = fixture.nested
            let peer = fixture.peer
            #expect(try store.moveSidebarItem(.folder(nested), to: root, before: .folder(peer), expected: fixture.snapshot()), "A nested folder can move out to the root")
            #expect(store.state.folders.first { $0.id == nested }?.parentID == nil, "Outdent preserves folder identity")
        }
    }

    @Test @MainActor static func formingATodaySplitLeavesAHomeInThePinnedChildsFolderSlot() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try hierarchy(in: directory)
            let store = fixture.store
            let inside = fixture.inside
            let today = fixture.today
            let (_, firstHome) = try fixture.formSplit()
            #expect(SidebarHierarchy.children(in: inside, state: store.state) == [.tab(today), .tab(firstHome.id)], "The new Today split leaves the pinned child's fresh home in its folder slot")
        }
    }

    @Test @MainActor static func movingAChildCannotDetachItFromTheSplit() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try hierarchy(in: directory)
            let store = fixture.store
            let root = fixture.root
            let first = fixture.first
            _ = try fixture.formSplit()
            #expect(!(try store.moveSidebarItem(.tab(first), to: root, before: nil, expected: fixture.snapshot())), "A split child cannot silently detach through folder drag")
        }
    }

    @Test @MainActor static func movingAWholeSplitPreservesItsPanesAndInsertsOneRow() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try hierarchy(in: directory)
            let store = fixture.store
            let parent = fixture.parent
            let first = fixture.first
            let second = fixture.second
            let inside = fixture.inside
            let today = fixture.today
            let (group, firstHome) = try fixture.formSplit()
            let originalGroup = group
            #expect(try store.moveSidebarItem(.split(group.id), to: inside, before: .tab(today), expected: fixture.snapshot()), "The whole split is one movable sidebar item")
            #expect(store.activeSplitLayout == originalGroup && store.state.selectedTabIDs == originalGroup.tabIDs, "Moving preserves container identity, geometry and selected original pages")
            #expect(try BrowserStoreTestsSupport.tab(first, in: store).folderID == parent && (try BrowserStoreTestsSupport.tab(second, in: store)).folderID == parent, "All original split children move together")
            #expect(SidebarHierarchy.children(in: inside, state: store.state) == [.split(group.id), .tab(today), .tab(firstHome.id)], "Only the split container appears in the destination order")
        }
    }

    @Test @MainActor static func nestingAFolderWithASplitPreservesEveryChildAndPersistsItsOrder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let fixture = try hierarchy(in: directory)
            let store = fixture.store
            let space = fixture.space
            let parent = fixture.parent
            let peer = fixture.peer
            let (group, _) = try fixture.formSplit()
            try fixture.moveSplitIntoTheFolder(group)
            let groupState = store.state
            #expect(try store.moveSidebarItem(.folder(parent), to: .init(spaceID: space, folderID: peer, section: .pinned), before: nil, expected: fixture.snapshot()), "A folder subtree containing a split can nest")
            #expect(store.state.tabs == groupState.tabs && store.state.splitLayouts == groupState.splitLayouts, "Subtree nesting preserves every original child record")
            #expect(fixture.batchedMatches(), "Every container's children match in one pass, with stored order, nesting and a split")
            let loaded = try BrowserStore(directory: directory)
            #expect(loaded.state.sidebarItemOrder == store.state.sidebarItemOrder && loaded.state.folders == store.state.folders, "Hierarchy ordering and nesting survive reopening the model")
        }
    }
}
