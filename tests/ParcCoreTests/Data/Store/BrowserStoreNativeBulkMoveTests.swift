import Combine
import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeBulkMoveTests {
    @Test @MainActor static func movingSelectedTabsPublishesOneDurableMoveInSelectionOrder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let first = store.open("https://one.example", kind: .pinned)
            let third = store.open("https://three.example", kind: .pinned)
            let target = store.createFolder(name: "Target")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let destination = SidebarContainerLocation(spaceID: space, folderID: target, section: .pinned)
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            let original = store.state
            #expect(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: nil, expected: snapshot()), "Batch moves every original target in one transaction")
            #expect(publications == 1, "Bulk move publishes exactly once")
            #expect(SidebarHierarchy.children(in: destination, state: store.state) == [.tab(first), .tab(third)], "Original selection order is retained")
            #expect(store.state.selectedTabIDs == original.selectedTabIDs && store.state.history == original.history, "Bulk movement does not change page selection/history")
            #expect(try BrowserStoreTestsSupport.tab(first, in: store).url == (try BrowserStoreTestsSupport.tab(first, in: BrowserStore(directory: directory))).url, "Persisted originals retain their URLs")
            observation.cancel()
        }
    }

    @Test @MainActor static func aStaleHierarchyRejectsTheWholeBatch() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example", kind: .pinned)
            let third = store.open("https://three.example", kind: .pinned)
            let parent = store.createFolder(name: "Parent")
            let target = store.createFolder(name: "Target")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let destination = SidebarContainerLocation(spaceID: space, folderID: target, section: .pinned)
            try #require(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: nil, expected: snapshot()), "Batch moves every original target in one transaction")
            let stale = snapshot(); store.toggleFolder(parent)
            let unchanged = store.state
            #expect(!(try store.moveSidebarItems([.tab(first), .tab(second)], to: root, before: nil, expected: stale)), "Stale hierarchy rejects the whole batch")
            #expect(store.state == unchanged, "Stale batch leaves every item untouched")
        }
    }

    @Test @MainActor static func aLaterCycleRollsBackTheWholeProposedBatch() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let first = store.open("https://one.example", kind: .pinned)
            let third = store.open("https://three.example", kind: .pinned)
            let parent = store.createFolder(name: "Parent")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let target = store.createFolder(name: "Target")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let destination = SidebarContainerLocation(spaceID: space, folderID: target, section: .pinned)
            try #require(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: nil, expected: snapshot()), "Batch moves every original target in one transaction")
            store.toggleFolder(parent)
            let unchanged = store.state
            #expect(!(try store.moveSidebarItems([.tab(first), .folder(parent)], to: .init(spaceID: space, folderID: nested, section: .pinned), before: nil, expected: snapshot())), "A later cycle rejects the whole proposed batch")
            #expect(store.state == unchanged, "Earlier proposal steps never leak on later refusal")
        }
    }

    @Test @MainActor static func theSelectedAncestorRepresentsItsSelectedDescendant() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            #expect(SidebarHierarchy.roots([.folder(parent), .folder(nested)], state: store.state, spaceID: space) == [.folder(parent)], "Selected ancestor owns a selected descendant once")
        }
    }

    @Test @MainActor static func duplicateIDsRejectTheWholeBatch() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let second = store.open("https://two.example", kind: .pinned)
            let target = store.createFolder(name: "Target")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let destination = SidebarContainerLocation(spaceID: space, folderID: target, section: .pinned)
            #expect(!(try store.moveSidebarItems([.tab(second), .tab(second)], to: destination, before: nil, expected: snapshot())), "Duplicate original IDs reject")
        }
    }

    @Test @MainActor static func aBatchCannotUseOneOfItsSourceRowsAsItsDestination() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let first = store.open("https://one.example", kind: .pinned)
            let third = store.open("https://three.example", kind: .pinned)
            let target = store.createFolder(name: "Target")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let destination = SidebarContainerLocation(spaceID: space, folderID: target, section: .pinned)
            try #require(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: nil, expected: snapshot()), "Batch moves every original target in one transaction")
            #expect(!(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: .tab(third), expected: snapshot())), "Selection-relative destination cannot consume one of its own source rows")
        }
    }

    @Test @MainActor static func aSplitAndNormalizedFolderSubtreeMoveTogetherInOrder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example", kind: .pinned)
            let third = store.open("https://three.example", kind: .pinned)
            let parent = store.createFolder(name: "Parent")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let target = store.createFolder(name: "Target")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let destination = SidebarContainerLocation(spaceID: space, folderID: target, section: .pinned)
            try #require(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: nil, expected: snapshot()), "Batch moves every original target in one transaction")
            store.selectTab(first); store.selectTab(third, extendingSplit: true)
            let split = store.activeSplitLayout!
            let beforeSplit = store.state
            #expect(try store.moveSidebarItems([.split(split.id), .folder(parent), .folder(nested)], to: root, before: .tab(second), expected: snapshot()), "Whole splits and normalized subtrees move together")
            #expect(store.state.splitLayouts == beforeSplit.splitLayouts && store.state.selectedTabIDs == beforeSplit.selectedTabIDs, "Split identity, geometry and original page focus survive")
            #expect(SidebarHierarchy.children(in: root, state: store.state).prefix(3) == [.split(split.id), .folder(parent), .tab(second)], "Mixed bulk insertion uses the exact typed target order")
        }
    }

    @Test @MainActor static func aFailedBatchSavePreservesEveryItemAndTheSelection() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example", kind: .pinned)
            let third = store.open("https://three.example", kind: .pinned)
            let target = store.createFolder(name: "Target")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let destination = SidebarContainerLocation(spaceID: space, folderID: target, section: .pinned)
            try #require(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: nil, expected: snapshot()), "Batch moves every original target in one transaction")
            store.selectTab(first); store.selectTab(third, extendingSplit: true)
            let split = store.activeSplitLayout!
            try #require(try store.moveSidebarItems([.split(split.id)], to: root, before: .tab(second), expected: snapshot()))
            let stable = store.state, expected = snapshot(), file = directory.appendingPathComponent("session.json"), backup = directory.appendingPathComponent("backup.json")
            try FileManager.default.moveItem(at: file, to: backup); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.moveSidebarItems([.split(split.id), .tab(second)], to: destination, before: nil, expected: expected) } catch { failed = true }
            #expect(failed && store.state == stable, "Disk failure preserves every original item and selection")
            try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
        }
    }
}
