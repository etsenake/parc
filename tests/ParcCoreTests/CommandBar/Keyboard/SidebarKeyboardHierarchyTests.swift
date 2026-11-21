import Foundation
import Testing
@testable import ParcCore

struct SidebarKeyboardHierarchyTests {
    private final class Fixture {
        var state = BrowserState.initial()
        let space: BrowserSpace
        let profile: UUID
        let outer: BrowserFolder
        let inner: BrowserFolder
        let empty: BrowserFolder
        let favorite: BrowserTab
        let a: BrowserTab
        let b: BrowserTab
        let hidden: BrowserTab
        let today: BrowserTab
        let group: BrowserSplitLayout
        let directory = CommandBarFixtures.temporaryDirectory("sidebar-keyboard")

        deinit { try? FileManager.default.removeItem(at: directory) }

        init() {
            let start = BrowserState.initial()
            state = start
            let space = start.spaces[0], profile = space.profileID
            self.space = space
            self.profile = profile
            outer = BrowserFolder(id: UUID(), spaceID: space.id, name: "Outer", parentID: nil, isExpanded: true)
            inner = BrowserFolder(id: UUID(), spaceID: space.id, name: "Inner", parentID: outer.id, isExpanded: false)
            empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty", parentID: nil, isExpanded: false)
            func tab(_ name: String, _ kind: TabKind, _ parent: UUID? = nil) -> BrowserTab {
                .init(id: UUID(), spaceID: space.id, profileID: profile, url: "https://example.invalid/" + name,
                    title: name, kind: kind, folderID: parent, createdAt: .distantPast, lastAccessed: .distantPast,
                    savedURL: "https://example.invalid/" + name, savedTitle: name)
            }
            favorite = tab("Favorite", .favorite)
            a = tab("A", .pinned, outer.id)
            b = tab("B", .pinned, outer.id)
            hidden = tab("Hidden", .pinned, inner.id)
            today = tab("Today", .today)
            group = BrowserSplitLayout(id: UUID(), sidebarAnchorID: b.id, spaceID: space.id,
                tabIDs: [a.id, b.id], orientation: .vertical, widthFactors: [0.35, 0.65], stacks: nil)
            state.tabs = [favorite, a, b, hidden, today]
            state.folders = [outer, inner, empty]
            state.splitLayouts = [group]
            state.selectedTabIDs = group.tabIDs
            state.selectionBySpace[space.id.uuidString] = group.tabIDs
            state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned).key] =
                [.folder(outer.id), .folder(empty.id)]
            state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: outer.id, section: .pinned).key] =
                [.folder(inner.id), .split(group.id)]
        }

        func items(_ unavailable: Set<UUID> = []) -> [SidebarKeyboardNavigation.Item] {
            SidebarKeyboardNavigation.items(state: state, spaceID: space.id, selected: group.tabIDs,
                focused: b.id, available: { !unavailable.contains($0) })
        }

        var file: URL { directory.appendingPathComponent("session.json") }

        @MainActor func persistedStore(collapsingInner: Bool = true) throws -> BrowserStore {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if collapsingInner { state.folders[1].isExpanded = false }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: file)
            return try BrowserStore(directory: directory)
        }
    }

    @Test func mixedDisplayedOrderIncludesOrdinaryAndEmptyFolders() {
        let f = Fixture()
        let expected: [SidebarItemReference] = [.tab(f.favorite.id), .folder(f.outer.id), .folder(f.inner.id), .split(f.group.id),
                                                .folder(f.empty.id), .tab(f.today.id)]
        #expect(f.items().map(\.reference) == expected)
    }

    @Test func aFolderHighlightCannotSelectAPage() {
        let f = Fixture()
        #expect(f.items().first { $0.reference == .folder(f.inner.id) }?.selection == nil)
    }

    @Test func aFolderCommitCapturesItsOriginalDisclosure() {
        let f = Fixture()
        #expect(f.items().first { $0.reference == .folder(f.inner.id) }?.folder == f.inner)
    }

    @Test func aWholeSplitOwnsOneTargetKeepingItsFocusAndOrientation() throws {
        let f = Fixture()
        let split = try #require(f.items().first { $0.reference == .split(f.group.id) })
        #expect(split.selection?.tabIDs == f.group.tabIDs)
        #expect(split.selection?.focusedTabID == f.b.id)
        #expect(split.selection?.orientation == .vertical)
    }

    @Test func thereAreNoSplitChildDuplicateKeyboardRows() {
        let f = Fixture()
        #expect(!f.items().contains { $0.reference == .tab(f.a.id) || $0.reference == .tab(f.b.id) })
    }

    @Test func aCollapsedAncestorHidesChildren() {
        let f = Fixture()
        #expect(!f.items().contains { $0.reference == .tab(f.hidden.id) })
    }

    @Test func anUnavailableMemberExcludesTheCompleteSplit() {
        let f = Fixture()
        #expect(f.items([f.b.id]).allSatisfy { $0.reference != .split(f.group.id) })
    }

    @Test func folderDisclosureDoesNotRequireOpeningItsChildren() {
        let f = Fixture()
        #expect(f.items([f.b.id]).contains { $0.reference == .folder(f.outer.id) })
    }

    @Test func arrowMovementIsIndependentFromTheActivePageAndState() {
        let f = Fixture()
        let entries = f.items()
        var cursor = SidebarKeyboardCursor(highlightedID: entries[2].id)
        let before = f.state
        cursor.move(1, in: entries.map(\.id))
        #expect(cursor.highlightedID == entries[3].id)
        #expect(f.state == before)
    }

    @Test func aWholeSplitConsumesOneArrowStep() {
        let f = Fixture()
        let entries = f.items()
        var cursor = SidebarKeyboardCursor(highlightedID: entries[3].id)
        cursor.move(1, in: entries.map(\.id))
        #expect(cursor.highlightedID == entries[4].id)
    }

    @Test func collapsingOmitsAllDescendantsWhileRetainingTheFolder() {
        let f = Fixture()
        f.state.folders[0].isExpanded = false
        #expect(f.items().map(\.reference) == [.tab(f.favorite.id), .folder(f.outer.id), .folder(f.empty.id), .tab(f.today.id)])
    }

    @Test func aRemovedDescendantCannotRetargetALaterRow() throws {
        let f = Fixture()
        let split = try #require(f.items().first { $0.reference == .split(f.group.id) })
        f.state.folders[0].isExpanded = false
        var cursor = SidebarKeyboardCursor(highlightedID: split.id)
        cursor.reconcile(f.items().map(\.id))
        #expect(cursor.highlightedID == nil)
    }

    @Test func expandingEntersTheActualChildIdentities() {
        let f = Fixture()
        f.state.folders[1].isExpanded = true
        #expect(f.items().contains { $0.reference == .tab(f.hidden.id) })
    }

    @Test func positionalTabCommandsStillOmitFolderRows() {
        let f = Fixture()
        f.state.folders[1].isExpanded = true
        let positional = PositionalTabNavigation.items(state: f.state, spaceID: f.space.id, selected: f.group.tabIDs,
                                                       focused: f.b.id, available: { _ in true })
        #expect(positional.count == 4)
    }

    @Test @MainActor func returnExpansionCommitsAndPreservesPageAndSpaceSelection() throws {
        let f = Fixture()
        let store = try f.persistedStore()
        let original = store.state
        #expect(try store.setFolderExpanded(true, expected: f.inner, profileID: f.profile))
        #expect(store.state.selectedTabIDs == original.selectedTabIDs)
        #expect(store.state.activeSpaceID == original.activeSpaceID)
    }

    @Test @MainActor func disclosurePreservesOriginalRecordsAndSplitGeometry() throws {
        let f = Fixture()
        let store = try f.persistedStore()
        let original = store.state
        _ = try store.setFolderExpanded(true, expected: f.inner, profileID: f.profile)
        #expect(store.state.tabs == original.tabs)
        #expect(store.state.splitLayouts == original.splitLayouts)
    }

    @Test @MainActor func disclosureIsDurableBeforePublication() throws {
        let f = Fixture()
        let store = try f.persistedStore()
        _ = try store.setFolderExpanded(true, expected: f.inner, profileID: f.profile)
        let loaded = try BrowserStore(directory: f.directory)
        #expect(loaded.state.folders.first { $0.id == f.inner.id }?.isExpanded == true)
    }

    @Test @MainActor func aStaleDisclosureTokenCannotReverseANewerAction() throws {
        let f = Fixture()
        let store = try f.persistedStore()
        _ = try store.setFolderExpanded(true, expected: f.inner, profileID: f.profile)
        let stale = try store.setFolderExpanded(false, expected: f.inner, profileID: f.profile)
        #expect(!stale)
        #expect(store.state.folders.first { $0.id == f.inner.id }?.isExpanded == true)
    }

    @Test @MainActor func aForeignProfileCannotMutateDisclosure() throws {
        let f = Fixture()
        let store = try f.persistedStore()
        _ = try store.setFolderExpanded(true, expected: f.inner, profileID: f.profile)
        var current = f.inner
        current.isExpanded = true
        #expect(!(try store.setFolderExpanded(false, expected: current, profileID: UUID())))
    }

    @Test @MainActor func aSecondReturnCollapsesTheExactFolder() throws {
        let f = Fixture()
        let store = try f.persistedStore()
        _ = try store.setFolderExpanded(true, expected: f.inner, profileID: f.profile)
        var current = f.inner
        current.isExpanded = true
        #expect(try store.setFolderExpanded(false, expected: current, profileID: f.profile))
        #expect(store.state.folders.first { $0.id == f.inner.id }?.isExpanded == false)
    }

    @Test @MainActor func anEmptyFolderUsesTheSameActualDisclosureTransaction() throws {
        let f = Fixture()
        let store = try f.persistedStore()
        #expect(try store.setFolderExpanded(true, expected: f.empty, profileID: f.profile))
    }

    @Test @MainActor func aFailedSaveCannotPublishDisclosureOrAnyBrowserStateChange() throws {
        let f = Fixture()
        let store = try f.persistedStore()
        let prior = store.state
        try FileManager.default.removeItem(at: f.file)
        try FileManager.default.createDirectory(at: f.file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { _ = try store.setFolderExpanded(true, expected: f.inner, profileID: f.profile) }
        #expect(store.state == prior)
    }

    @Test @MainActor func anEphemeralOwnerNeverWritesNormalFolderState() throws {
        let f = Fixture()
        let privateStore = BrowserStore(privateParentProfileID: f.profile, engineProfilePath: "/unused-original-context",
            directory: f.directory.appendingPathComponent("must-not-exist"), settings: f.state.settings)
        let refused = try privateStore.setFolderExpanded(true, expected: f.inner, profileID: f.profile)
        #expect(!refused)
        #expect(!FileManager.default.fileExists(atPath: privateStore.directory.path))
    }
}
