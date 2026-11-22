import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeSplitDropTests {
    @Test @MainActor static func aSplitDropWithStaleDestinationSelectionDoesNotChangeTheSession() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            let third = store.open("https://three.example")
            store.selectTab(first)
            let before = store.state
            #expect(!store.dropTabIntoSplit(second, expectedSelection: [third], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal), "Stale destination selection must reject atomically")
            #expect(store.state == before, "Refusal must not mutate any tab or group")
        }
    }

    @Test @MainActor static func aNewSplitDropKeepsOrderedIdentitiesTheAnchorAndOriginalPageMetadata() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            let originalTab = try BrowserStoreTestsSupport.tab(second, in: store)
            #expect(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]), "Sidebar identity must join the original selected page")
            let group = store.activeSplitLayout!
            #expect(group.tabIDs == [first, second] && group.sidebarAnchorID == second, "New split keeps ordered children and the original ordinary sidebar anchor")
            let afterTab = try BrowserStoreTestsSupport.tab(second, in: store)
            #expect(afterTab.url == originalTab.url && afterTab.savedURL == originalTab.savedURL
                && afterTab.kind == originalTab.kind && afterTab.folderID == originalTab.folderID, "Joining a split must preserve original child destination and placement")
        }
    }

    @Test @MainActor static func selectingAnOriginalChildActivatesItsWholeTypedSplit() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            let group = try #require(store.activeSplitLayout)
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.selectTab(third)
            store.setSplit([third, fourth])
            store.selectTab(second)
            #expect(store.activeSplitLayout == group && store.state.selectedTabIDs == [first, second], "Selecting a child activates its whole typed container")
        }
    }

    @MainActor
    private static func withExpandedDropGroup(
        _ body: (BrowserStore, BrowserSplitLayout, BrowserSplitLayout, BrowserSplitLayout, UUID, UUID, UUID, UUID) throws -> Void
    ) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            let group = try #require(store.activeSplitLayout)
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.selectTab(third)
            store.setSplit([third, fourth])
            let other = store.activeSplitLayout!
            store.selectTab(second)
            try #require(store.dropTabIntoSplit(third, expectedSelection: [first, second], expectedLayout: group,
                target: .insert(1), orientation: .horizontal), "Move an original child from a second group")
            let expanded = store.activeSplitLayout!
            try body(store, group, other, expanded, first, second, third, fourth)
        }
    }

    @Test @MainActor static func insertingAPaneFromAnotherGroupDissolvesOnlyTheSourceGroup() throws {
        try withExpandedDropGroup { store, group, other, expanded, first, second, third, fourth in
            #expect(expanded.id == group.id && expanded.tabIDs == [first, third, second], "Insertion retains destination container identity")
            #expect(!store.state.splitLayouts.contains(where: { $0.id == other.id }), "The one-child source container dissolves while its surviving tab stays alive")
            let survivor = try BrowserStoreTestsSupport.tab(fourth, in: store)
            #expect(survivor.archivedAt == nil, "Source survivor must remain alive")
        }
    }

    @Test @MainActor static func aPaneCannotBeDroppedIntoItsOwnSplit() throws {
        try withExpandedDropGroup { store, _, _, expanded, _, second, _, _ in
            let unchanged = store.state
            #expect(!store.dropTabIntoSplit(second, expectedSelection: expanded.tabIDs, expectedLayout: expanded,
                target: .insert(0), orientation: .horizontal), "A member is not a drop source; members reorder through pane Move")
            #expect(store.state == unchanged, "A refused member drop publishes nothing")
        }
    }

    @Test @MainActor static func replacingAPaneKeepsTheDestinationGroupAndTheDisplacedPage() throws {
        try withExpandedDropGroup { store, group, _, expanded, first, second, third, fourth in
            #expect(store.dropTabIntoSplit(fourth, expectedSelection: expanded.tabIDs, expectedLayout: expanded,
                target: .replace(1), orientation: .horizontal), "Typed replacement uses the original tab")
            let replaced = store.activeSplitLayout!
            #expect(replaced.tabIDs == [first, fourth, second] && replaced.id == group.id, "Replacement retains destination geometry and identity")
            let displaced = try BrowserStoreTestsSupport.tab(third, in: store)
            #expect(displaced.archivedAt == nil, "Displaced page is preserved, not closed")
        }
    }

    @Test @MainActor static func separatingAPanePreservesTheSiblingsAndInvalidatesTheOldGroupToken() throws {
        try withExpandedDropGroup { store, _, _, expanded, first, second, third, _ in
            #expect(store.separateTabFromSplit(first, expected: expanded))
            #expect(store.activeSplitLayout?.tabIDs == [third, second])
            #expect(!store.separateTabFromSplit(second, expected: expanded))
        }
    }

    @Test @MainActor static func typedSplitGroupsPersistAndAppearExactlyOnceInTheSidebar() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            let group = try #require(store.activeSplitLayout)
            let remaining = group
            try store.save()
            let restored = try BrowserStore(directory: directory)
            #expect(restored.activeSplitLayout == remaining, "Group identity, ordering, anchor and geometry persist")
            let projected = SidebarSplitItems.groups(in: restored.state, spaceID: restored.activeSpaceID)
            #expect(projected.map(\.id) == [remaining.id], "Sidebar projection emits each typed group exactly once")
            #expect(Set(projected.flatMap(\.tabIDs)).count == projected.flatMap(\.tabIDs).count, "A Space cannot assign one tab to two sidebar containers")
        }
    }

    @Test @MainActor static func anUnknownDropSourceCannotCreateAPlaceholder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            let group = try #require(store.activeSplitLayout)
            let snapshot = store.state
            #expect(!store.dropTabIntoSplit(UUID(), expectedSelection: group.tabIDs, expectedLayout: group,
                target: .insert(0), orientation: .vertical), "Unknown source identity cannot create a placeholder")
            #expect(store.state == snapshot, "Unknown source refusal preserves exact state")
        }
    }

    enum DropDamage: CaseIterable { case outOfRange, existingMember, invalidGeometry }

    @Test(arguments: DropDamage.allCases) @MainActor static func invalidDropPlansDoNotCreateTransactions(_ damage: DropDamage) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            let group = try #require(store.activeSplitLayout)
            var layout = group
            var source = UUID()
            var index = 0
            switch damage {
            case .outOfRange: index = 99
            case .existingMember: source = second
            case .invalidGeometry: layout.widthFactors = []
            }
            #expect(SplitDropTransaction.make(source: source, selection: group.tabIDs, layout: layout,
                target: .insert(index), orientation: .horizontal, spaceID: store.activeSpaceID) == nil)
        }
    }

    @Test @MainActor static func legacyOverlappingSplitMembershipKeepsAndPersistsTheActiveGroup() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            store.closeSplit()
            let fourth = store.open("https://four.example")
            store.setSplit([fourth, second])
            let remaining = try #require(store.activeSplitLayout)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var layouts = legacy["splitLayouts"] as! [[String: Any]]
            layouts[0].removeValue(forKey: "id"); layouts[0].removeValue(forKey: "sidebarAnchorID")
            var overlap = layouts[0]
            overlap["tabIDs"] = [first.uuidString, second.uuidString]
            overlap["widthFactors"] = [0.5, 0.5]
            layouts.insert(overlap, at: 0); legacy["splitLayouts"] = layouts
            try JSONSerialization.data(withJSONObject: legacy).write(to: file)
            let migrated = try BrowserStore(directory: directory)
            #expect(migrated.state.splitLayouts.count == 1 && migrated.activeSplitLayout?.tabIDs == remaining.tabIDs, "Active typed group wins legacy overlapping layout cache membership")
            let migratedID = migrated.activeSplitLayout?.id
            let secondRead = try BrowserStore(directory: directory)
            #expect(secondRead.activeSplitLayout?.id == migratedID, "Legacy group identity migration is saved immediately and stable across rereads")
        }
    }
}
