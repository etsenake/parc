import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserImportReplaceTests {
    typealias Placement = BrowserImportPlacement

    @MainActor final class Flow {
        let directory: URL
        let store: BrowserStore
        let space: BrowserSpace
        let target: BrowserImportDestination
        var selection: BrowserImportSelection
        let first: Placement
        let other: Placement
        let workFolder: BrowserFolder
        let a: BrowserTab
        let d: BrowserTab
        let x: BrowserTab
        var root: SidebarContainerLocation { .init(spaceID: space.id, folderID: nil, section: .pinned) }

        static func page(_ id: String) -> BrowserImportBookmark {
            .init(id: id, title: id.uppercased(), url: "https://example.test/\(id)", children: [])
        }

        init(directory: URL) throws {
            self.directory = directory
            let date = Date(timeIntervalSince1970: 1_793_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let space = store.activeSpace
            let target = BrowserImportDestination(spaceID: space.id, profileID: space.profileID)
            self.store = store
            self.space = space
            self.target = target
            let sub = BrowserImportBookmark(id: "sub", title: "Sub", url: nil, children: [Self.page("c")])
            let work = BrowserImportBookmark(id: "work", title: "Work", url: nil,
                                             children: [Self.page("a"), Self.page("b"), sub])
            var selection = try BrowserImportSelection(roots: [work, Self.page("d"), Self.page("e"), Self.page("f")])
            for id in ["b", "sub", "e", "f"] { selection.toggle(id) }
            self.selection = selection
            first = try store.commitImportedBookmarks(selection.includedRoots, destination: target)
            other = try store.commitImportedBookmarks([Self.page("x")], destination: target)
            workFolder = try #require(store.state.folders.first { $0.name == "Work" })
            a = try #require(Self.tab("a", in: store))
            d = try #require(Self.tab("d", in: store))
            x = try #require(Self.tab("x", in: store))
        }

        static func tab(_ id: String, in store: BrowserStore) -> BrowserTab? {
            store.state.tabs.first { $0.url == "https://example.test/\(id)" && $0.archivedAt == nil }
        }

        func tab(_ id: String) -> BrowserTab? { Self.tab(id, in: store) }

        func count(_ id: String) -> Int { store.state.tabs.filter { $0.url == "https://example.test/\(id)" }.count }

        func order(_ location: SidebarContainerLocation) -> [SidebarItemReference] {
            SidebarHierarchy.children(in: location, state: store.state)
        }

        func replace(_ placement: Placement) throws -> Placement {
            try store.commitImportedBookmarks([(selection.includedRoots, target, placement)])[0]
        }

        func second() throws -> Placement {
            for id in ["a", "b", "sub", "e"] { selection.toggle(id) }
            return try replace(first)
        }

        func third() throws -> Placement {
            let second = try second()
            _ = try store.saveSidebarTitle(d, title: "Renamed")
            store.moveTab(try #require(tab("b")).id, toSpace: space.id, folderID: nil)
            selection.toggle("d")
            selection.toggle("b")
            return try replace(second)
        }

        func fourth() throws -> Placement {
            let third = try third()
            selection.toggle("d")
            selection.toggle("b")
            return try replace(third)
        }

        func cleared() throws -> Placement {
            let fourth = try fourth()
            selection.toggleAll()
            selection.toggleAll()
            store.moveTab(x.id, toSpace: space.id, folderID: workFolder.id)
            store.selectTab(try #require(tab("e")).id)
            return try replace(fourth)
        }
    }

    func withFlow(_ body: (Flow) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try body(Flow(directory: directory))
        }
    }

    @Test func aFirstAcceptAddsTheTickedTreeAndAnotherImportFollowsIt() throws {
        try withFlow { flow in
            #expect(flow.order(flow.root).suffix(3) == [.folder(flow.workFolder.id), .tab(flow.d.id), .tab(flow.x.id)])
        }
    }

    @Test func nextWithTheSameTicksChangesNothing() throws {
        try withFlow { flow in
            let unchanged = flow.store.state
            let same = try flow.store.commitImportedBookmarks([(flow.selection.includedRoots, flow.target, flow.first)])
            #expect(flow.store.state == unchanged && same == [flow.first])
        }
    }

    @Test func anUntickedBookmarkThePageAddedLeaves() throws {
        try withFlow { flow in
            _ = try flow.second()
            #expect(flow.tab("a") == nil && flow.count("a") == 0)
            #expect(!flow.store.state.sidebarItemOrder.values.contains { $0.contains(.tab(flow.a.id)) })
        }
    }

    @Test func newlyTickedBookmarksJoinTheFoldersThePageAlreadyAdded() throws {
        try withFlow { flow in
            _ = try flow.second()
            let b = try #require(flow.tab("b"))
            let subFolder = try #require(flow.store.state.folders.first { $0.name == "Sub" })
            #expect(flow.store.state.folders.first { $0.id == flow.workFolder.id } == flow.workFolder
                    && b.folderID == flow.workFolder.id && subFolder.parentID == flow.workFolder.id
                    && flow.tab("c")?.folderID == subFolder.id)
        }
    }

    @Test func aStillTickedBookmarkKeepsItsIdentityAndAnotherImportsIsUntouched() throws {
        try withFlow { flow in
            _ = try flow.second()
            #expect(flow.store.state.tabs.first { $0.id == flow.d.id } == flow.d && flow.tab("x") == flow.x)
        }
    }

    @Test func aNewlyTickedBookmarkGoesBesideItsSourceSiblings() throws {
        try withFlow { flow in
            _ = try flow.second()
            let b = try #require(flow.tab("b"))
            let e = try #require(flow.tab("e"))
            let subFolder = try #require(flow.store.state.folders.first { $0.name == "Sub" })
            #expect(flow.order(flow.root).suffix(4) == [.folder(flow.workFolder.id), .tab(flow.d.id), .tab(e.id), .tab(flow.x.id)])
            #expect(flow.order(.init(spaceID: flow.space.id, folderID: flow.workFolder.id, section: .pinned))
                    == [.tab(b.id), .folder(subFolder.id)])
        }
    }

    @Test func nothingIsAddedTwice() throws {
        try withFlow { flow in
            _ = try flow.second()
            #expect(["b", "c", "d", "e", "x"].allSatisfy { flow.count($0) == 1 } && flow.count("f") == 0)
        }
    }

    @Test func renamedOrMovedBookmarksAreKeptWhenUnticked() throws {
        try withFlow { flow in
            _ = try flow.third()
            #expect(flow.tab("d")?.customTitle == "Renamed" && flow.tab("b")?.folderID == nil)
        }
    }

    @Test func tickingAKeptBookmarkAgainAddsNoDuplicate() throws {
        try withFlow { flow in
            _ = try flow.fourth()
            #expect(flow.count("d") == 1 && flow.count("b") == 1)
        }
    }

    @Test func untickingEverythingLeavesNothingSelected() throws {
        try withFlow { flow in
            flow.selection.toggleAll()
            flow.selection.toggleAll()
            #expect(flow.selection.selected.isEmpty)
        }
    }

    @Test func clearingKeepsOpenBookmarksFoldersWithOtherItemsAndOtherImports() throws {
        try withFlow { flow in
            let fourth = try flow.fourth()
            let beforeAll = flow.store.state
            flow.selection.toggleAll()
            flow.selection.toggleAll()
            flow.store.moveTab(flow.x.id, toSpace: flow.space.id, folderID: flow.workFolder.id)
            let e = try #require(flow.tab("e"))
            flow.store.selectTab(e.id)
            _ = try flow.replace(fourth)
            let subFolder = flow.store.state.folders.first { $0.name == "Sub" }
            #expect(flow.tab("c") == nil && subFolder == nil)
            #expect(flow.tab("e") != nil && flow.store.state.selectedTabIDs == [e.id])
            #expect(flow.store.state.folders.contains { $0.id == flow.workFolder.id } && flow.tab("x")?.folderID == flow.workFolder.id)
            #expect(flow.tab("d") != nil && flow.tab("b") != nil && flow.tab("x") != nil)
            #expect(flow.other.tabs.count == 1 && beforeAll.tabs.count - flow.store.state.tabs.count == 1)
        }
    }

    @Test func aRefusedReplaceWritePropagatesAndLeavesThePreviousAcceptedBookmarks() throws {
        try withFlow { flow in
            let cleared = try flow.cleared()
            flow.selection.toggleAll()
            let accepted = flow.store.state
            let session = flow.directory.appendingPathComponent("session.json")
            let backup = flow.directory.appendingPathComponent("prior-session.json")
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) { try flow.replace(cleared) }
            #expect(flow.store.state == accepted)
        }
    }

    @Test func repeatedBackAndNextLoopsNeverDuplicateAndTheReplacedSetIsSaved() throws {
        try withFlow { flow in
            var placement = try flow.cleared()
            flow.selection.toggleAll()
            for _ in 0..<3 { placement = try flow.replace(placement) }
            #expect(["a", "b", "c", "d", "e", "f", "x"].allSatisfy { flow.count($0) == 1 })
            let reloaded = try BrowserStore(directory: flow.directory)
            #expect(reloaded.state.tabs == flow.store.state.tabs && reloaded.state.folders == flow.store.state.folders)
        }
    }
}
