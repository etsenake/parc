import Foundation
import Testing
@testable import ParcCore

struct SplitSeparateAllTests {
    @MainActor private final class Fixture {
        let root: URL
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store: BrowserStore

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-separate-all-" + UUID().uuidString)
            let now = now
            store = try BrowserStore(directory: root, now: { now })
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func reopened() throws -> BrowserStore {
            let now = now
            return try BrowserStore(directory: root, now: { now })
        }
    }

    private struct Placement: Equatable {
        let id: UUID
        let kind: TabKind
        let folderID: UUID?
        let url: String
    }

    @MainActor private struct Three {
        let a: UUID, b: UUID, c: UUID
        let space: UUID
        let group: BrowserSplitLayout
        let folders: [BrowserFolder]
        let archive: [UUID]
        let history: [BrowserHistoryEntry]
        let placements: [Placement]

        init(_ store: BrowserStore) {
            let a = store.open("https://one.invalid", kind: .pinned)
            let b = store.open("https://two.invalid"), c = store.open("https://three.invalid")
            let folder = store.createFolder(name: "Original")
            store.moveTab(a, toSpace: store.activeSpaceID, folderID: folder)
            store.setSplit([a, b, c])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            self.a = a; self.b = b; self.c = c
            space = store.activeSpaceID
            group = store.activeSplitLayout!
            folders = store.state.folders
            archive = store.state.recentlyClosedIDs
            history = store.state.history
            placements = Three.placements(store)
        }

        static func placements(_ store: BrowserStore) -> [Placement] {
            store.state.tabs.map { Placement(id: $0.id, kind: $0.kind, folderID: $0.folderID, url: $0.url) }
        }
    }

    @MainActor @Test func aMovedSplitSeparatesIntoItsExactSlotInPaneOrder() throws {
        let f = try Fixture()
        let sibling = f.store.open("https://sibling.invalid")
        let firstChild = f.store.open("https://first.invalid"), secondChild = f.store.open("https://second.invalid")
        _ = f.store.open("https://other-sibling.invalid")
        f.store.setSplit([secondChild, firstChild])
        let group = try #require(f.store.activeSplitLayout)
        let snapshot = try #require(SidebarHierarchySnapshot(state: f.store.state, spaceID: f.store.activeSpaceID,
            profileID: f.store.activeSpace.profileID, includesFavorites: true))
        let today = SidebarContainerLocation(spaceID: f.store.activeSpaceID, folderID: nil, section: .today)
        try #require(try f.store.moveSidebarItem(.split(group.id), to: today, before: .tab(sibling), expected: snapshot))
        let order = SidebarTodayArchive.order(in: f.store.state, spaceID: f.store.activeSpaceID)
        #expect(f.store.separateAllTabsFromSplit(expected: group, focusedID: firstChild))
        #expect(SidebarTodayArchive.order(in: f.store.state, spaceID: f.store.activeSpaceID) == order)
    }

    @MainActor @Test func aStaleMembershipReceiptRefusesWithoutMutation() throws {
        let f = try Fixture()
        let three = Three(f.store)
        let stale = BrowserSplitLayout(id: three.group.id, sidebarAnchorID: three.group.sidebarAnchorID, spaceID: three.group.spaceID,
                                       tabIDs: [three.a, three.b], orientation: three.group.orientation, widthFactors: [0.5, 0.5], stacks: nil)
        let before = f.store.state
        #expect(!f.store.separateAllTabsFromSplit(expected: stale, focusedID: three.b))
        #expect(f.store.state == before)
    }

    @MainActor @Test func theDisplayedSplitDissolvesItsContainer() throws {
        let f = try Fixture()
        let three = Three(f.store)
        #expect(f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b))
        #expect(!f.store.state.splitLayouts.contains { $0.id == three.group.id })
    }

    @MainActor @Test func theFocusedOriginalStaysDisplayedAlone() throws {
        let f = try Fixture()
        let three = Three(f.store)
        _ = f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b)
        #expect(f.store.state.selectedTabIDs == [three.b])
        #expect(f.store.state.selectionBySpace[three.space.uuidString] == [three.b])
    }

    @MainActor @Test func everyChildKeepsItsSavedSectionFolderAndAddress() throws {
        let f = try Fixture()
        let three = Three(f.store)
        _ = f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b)
        #expect(Three.placements(f.store) == three.placements)
    }

    @MainActor @Test func theKeptPageIsStampedAsAccessed() throws {
        let f = try Fixture()
        let three = Three(f.store)
        _ = f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b)
        #expect(f.store.state.tabs.first { $0.id == three.b }?.lastAccessed == f.now)
    }

    @MainActor @Test func separatingIsNotACloseArchiveOrNavigation() throws {
        let f = try Fixture()
        let three = Three(f.store)
        _ = f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b)
        #expect(f.store.state.folders == three.folders)
        #expect(f.store.state.recentlyClosedIDs == three.archive)
        #expect(f.store.state.history == three.history)
    }

    @MainActor @Test func selectionAndDissolutionPersistTogether() throws {
        let f = try Fixture()
        let three = Three(f.store)
        _ = f.store.separateAllTabsFromSplit(expected: three.group, focusedID: three.b)
        let loaded = try f.reopened()
        #expect(loaded.state.selectedTabIDs == [three.b])
        #expect(!loaded.state.splitLayouts.contains { $0.id == three.group.id })
    }

    @MainActor @Test func aFocusOutsideTheSplitKeepsTheFirstChildDisplayed() throws {
        let f = try Fixture()
        let three = Three(f.store)
        #expect(f.store.separateAllTabsFromSplit(expected: three.group, focusedID: UUID()))
        #expect(f.store.state.selectedTabIDs == [three.a])
    }

    @MainActor @Test func aBackgroundSplitSeparates() throws {
        let f = try Fixture()
        let three = Three(f.store)
        f.store.setSplit([three.b, three.c])
        let background = try #require(f.store.activeSplitLayout)
        f.store.setSplit([three.a])
        #expect(f.store.separateAllTabsFromSplit(expected: background, focusedID: three.a))
    }

    @MainActor @Test func aBackgroundSeparationLeavesTheDisplayedSelection() throws {
        let f = try Fixture()
        let three = Three(f.store)
        f.store.setSplit([three.b, three.c])
        let background = try #require(f.store.activeSplitLayout)
        f.store.setSplit([three.a])
        _ = f.store.separateAllTabsFromSplit(expected: background, focusedID: three.a)
        #expect(f.store.state.selectedTabIDs == [three.a])
        #expect(!f.store.state.splitLayouts.contains { $0.id == background.id })
    }

    @MainActor private func flippable(_ f: Fixture) -> (Three, BrowserSplitLayout) {
        let three = Three(f.store)
        f.store.setSplit([three.b, three.c])
        f.store.setSplitLayout(orientation: .horizontal, widthFactors: [1, 3])
        return (three, f.store.activeSplitLayout!)
    }

    @MainActor @Test func theDisplayedSplitFlips() throws {
        let f = try Fixture()
        let (_, shown) = flippable(f)
        #expect(f.store.flipSplitOrientation(expected: shown))
    }

    @MainActor @Test func flippingKeepsProportionsIdentityAndSelection() throws {
        let f = try Fixture()
        let (three, shown) = flippable(f)
        _ = f.store.flipSplitOrientation(expected: shown)
        let flipped = try #require(f.store.activeSplitLayout)
        #expect(flipped.id == shown.id)
        #expect(flipped.orientation == .vertical)
        #expect(flipped.widthFactors == shown.widthFactors)
        #expect(f.store.state.selectedTabIDs == [three.b, three.c])
    }

    @MainActor @Test func aStaleFlipReceiptRefuses() throws {
        let f = try Fixture()
        let (_, shown) = flippable(f)
        _ = f.store.flipSplitOrientation(expected: shown)
        #expect(!f.store.flipSplitOrientation(expected: shown))
    }

    @MainActor @Test func aBackgroundSplitFlipsWithoutChangingTheDisplay() throws {
        let f = try Fixture()
        let (three, shown) = flippable(f)
        _ = f.store.flipSplitOrientation(expected: shown)
        let flipped = try #require(f.store.activeSplitLayout)
        f.store.setSplit([three.a])
        #expect(f.store.flipSplitOrientation(expected: flipped))
        #expect(f.store.state.selectedTabIDs == [three.a])
        #expect(f.store.state.splitLayouts.first { $0.id == flipped.id }?.orientation == .horizontal)
    }

    @MainActor @Test func aFlipPersists() throws {
        let f = try Fixture()
        let (_, shown) = flippable(f)
        _ = f.store.flipSplitOrientation(expected: shown)
        #expect(try f.reopened().state.splitLayouts.first { $0.id == shown.id }?.orientation == .vertical)
    }

    @MainActor private struct Away {
        let home: UUID, other: UUID
        let away: UUID, awayB: UUID, saved: UUID, t: UUID
        let awayGroup: BrowserSplitLayout
        let savedRecord: BrowserTab

        init(_ store: BrowserStore) {
            let home = store.activeSpaceID
            let other = store.createSpace(name: "Other")
            store.selectSpace(other)
            let away = store.open("https://away.invalid")
            let saved = store.open("https://saved.invalid", kind: .pinned)
            let awayB = store.open("https://away-b.invalid")
            store.setSplit([away, awayB])
            awayGroup = store.activeSplitLayout!
            store.setSplit([saved])
            savedRecord = store.state.tabs.first { $0.id == saved }!
            store.selectSpace(home)
            let t = store.open("https://here.invalid")
            store.setSplit([t])
            self.home = home; self.other = other
            self.away = away; self.awayB = awayB; self.saved = saved; self.t = t
        }
    }

    @MainActor private func addAfter(_ store: BrowserStore, _ pane: UUID, tab: UUID, homes: [UUID: UUID] = [:]) throws -> Bool {
        let draft = try #require(SplitPaneInsertion(paneID: pane, operation: .addAfter, state: store.state))
        return store.insertSplitPane(draft, tabID: tab, navigationURL: nil, creation: nil, savedHomeIDs: homes, documents: [:])
    }

    @MainActor @Test func aTodayTabFromAnotherSpaceJoinsTheSplit() throws {
        let f = try Fixture()
        let s = Away(f.store)
        #expect(try addAfter(f.store, s.t, tab: s.away))
    }

    @MainActor @Test func theJoiningTabMovesIntoThisSpaceAndTheWindowKeepsItsSpace() throws {
        let f = try Fixture()
        let s = Away(f.store)
        _ = try addAfter(f.store, s.t, tab: s.away)
        let joined = try #require(f.store.state.tabs.first { $0.id == s.away })
        #expect(f.store.activeSpaceID == s.home)
        #expect(f.store.state.selectedTabIDs == [s.t, s.away])
        #expect(joined.spaceID == s.home)
        #expect(joined.kind == .today)
        #expect(joined.folderID == nil)
    }

    @MainActor @Test func theOldSplitLeftWithOneChildDissolvesInItsOwnSpace() throws {
        let f = try Fixture()
        let s = Away(f.store)
        _ = try addAfter(f.store, s.t, tab: s.away)
        #expect(!f.store.state.splitLayouts.contains { $0.id == s.awayGroup.id })
        #expect(f.store.state.tabs.contains { $0.id == s.awayB && $0.spaceID == s.other })
    }

    @MainActor @Test func aPinnedTabFromAnotherSpaceJoinsTheSplit() throws {
        let f = try Fixture()
        let s = Away(f.store)
        #expect(try addAfter(f.store, s.t, tab: s.saved, homes: [s.saved: UUID()]))
        #expect(f.store.state.selectedTabIDs == [s.t, s.saved])
        #expect(f.store.state.tabs.first { $0.id == s.saved }?.spaceID == s.home)
    }

    @MainActor @Test func theSavedHomeStaysInItsOwnSpace() throws {
        let f = try Fixture()
        let s = Away(f.store)
        let homeID = UUID()
        _ = try addAfter(f.store, s.t, tab: s.saved, homes: [s.saved: homeID])
        let copy = f.store.state.tabs.first { $0.id == homeID }
        #expect(copy?.spaceID == s.other)
        #expect(copy?.kind == .pinned)
        #expect(copy?.url == s.savedRecord.savedURL)
    }

    @MainActor @Test func theOtherSpaceRemembersTheSavedHomeNotTheMovedPage() throws {
        let f = try Fixture()
        let s = Away(f.store)
        let homeID = UUID()
        _ = try addAfter(f.store, s.t, tab: s.saved, homes: [s.saved: homeID])
        #expect(f.store.state.selectionBySpace[s.other.uuidString] == [homeID])
    }

    @MainActor private struct Origin {
        let other: UUID, home: UUID
        let b1: UUID, b2: UUID, b3: UUID, q: UUID
        let bGroup: BrowserSplitLayout
        let bSlot: Int, qSlot: Int
        let bToday: SidebarContainerLocation, aToday: SidebarContainerLocation

        init(_ store: BrowserStore) {
            let home = store.activeSpaceID
            let other = store.createSpace(name: "Other")
            store.selectSpace(other)
            let b1 = store.open("https://b1.invalid"), b2 = store.open("https://b2.invalid"), b3 = store.open("https://b3.invalid")
            let filler = store.open("https://filler.invalid")
            store.setSplit([b1, b2, b3])
            let bGroup = store.activeSplitLayout!
            store.setSplit([filler])
            let bToday = SidebarContainerLocation(spaceID: other, folderID: nil, section: .today)
            bSlot = SidebarHierarchy.children(in: bToday, state: store.state).firstIndex(of: .split(bGroup.id))!
            store.selectSpace(home)
            let q = store.open("https://q.invalid")
            _ = store.open("https://above-q.invalid")
            store.setSplit([q])
            let aToday = SidebarContainerLocation(spaceID: home, folderID: nil, section: .today)
            qSlot = SidebarHierarchy.children(in: aToday, state: store.state).firstIndex(of: .tab(q))!
            self.other = other; self.home = home
            self.b1 = b1; self.b2 = b2; self.b3 = b3; self.q = q
            self.bGroup = bGroup
            self.bToday = bToday; self.aToday = aToday
        }
    }

    @MainActor @Test func theOriginSplitsAnchorCanJoinFromAnotherSpace() throws {
        let f = try Fixture()
        let s = Origin(f.store)
        #expect(try addAfter(f.store, s.q, tab: s.b1))
    }

    @MainActor @Test func theOriginSplitKeepsItsSlotUnderItsNewAnchor() throws {
        let f = try Fixture()
        let s = Origin(f.store)
        _ = try addAfter(f.store, s.q, tab: s.b1)
        let survivor = f.store.state.splitLayouts.first { $0.id == s.bGroup.id }
        #expect(survivor?.tabIDs == [s.b2, s.b3])
        #expect(survivor?.sidebarAnchorID == s.b2)
        #expect(SidebarHierarchy.children(in: s.bToday, state: f.store.state).firstIndex(of: .split(s.bGroup.id)) == s.bSlot)
    }

    @MainActor @Test func theDestinationSplitStaysAtTheTargetPanesSlot() throws {
        let f = try Fixture()
        let s = Origin(f.store)
        _ = try addAfter(f.store, s.q, tab: s.b1)
        let joined = try #require(f.store.activeSplitLayout)
        #expect(SidebarHierarchy.children(in: s.aToday, state: f.store.state).firstIndex(of: .split(joined.id)) == s.qSlot)
    }

    @MainActor @Test func optionReturnAcceptsATabFromAnotherSpaceOfTheProfile() throws {
        let f = try Fixture()
        let home = f.store.activeSpaceID
        let other = f.store.createSpace(name: "Other")
        f.store.selectSpace(other)
        let far = f.store.open("https://far.invalid")
        f.store.selectSpace(home)
        let focusTab = f.store.open("https://focus.invalid")
        f.store.setSplit([focusTab])
        #expect(f.store.insertCommandBarSplit(after: focusTab, expectedSelection: [focusTab], tabID: far))
        #expect(f.store.state.selectedTabIDs == [focusTab, far])
        #expect(f.store.activeSpaceID == home)
        #expect(f.store.state.tabs.first { $0.id == far }?.spaceID == home)
    }

    @MainActor private struct Notes {
        let home: UUID, other: UUID
        let noteTab: UUID, noteTab2: UUID, notePane: UUID
        let first: SidebarDocumentReference, second: SidebarDocumentReference

        init(_ f: Fixture) throws {
            let store = f.store
            let farNote = f.root.appendingPathComponent("Far Note.md"), farNote2 = f.root.appendingPathComponent("Far Note 2.md")
            try Data().write(to: farNote)
            try Data().write(to: farNote2)
            let home = store.activeSpaceID
            let other = store.createSpace(name: "Other")
            store.selectSpace(other)
            let noteTab = store.openNote(url: farNote, title: "Far Note")!
            let noteTab2 = store.openNote(url: farNote2, title: "Far Note 2")!
            store.setKind(noteTab, .pinned)
            store.setKind(noteTab2, .pinned)
            store.selectSpace(home)
            let notePane = store.open("https://note-pane.invalid")
            store.setSplit([notePane])
            let profile = store.activeSpace.profileID
            self.home = home; self.other = other
            self.noteTab = noteTab; self.noteTab2 = noteTab2; self.notePane = notePane
            first = SidebarDocumentReference(page: .note(farNote), profileID: profile) {
                guard FileManager.default.fileExists(atPath: farNote.path) else { throw CocoaError(.fileNoSuchFile) }
            }
            second = SidebarDocumentReference(page: .note(farNote2), profileID: profile) {
                guard FileManager.default.fileExists(atPath: farNote2.path) else { throw CocoaError(.fileNoSuchFile) }
            }
        }

        @MainActor func join(_ store: BrowserStore, homeID: UUID) throws -> Bool {
            let draft = try #require(SplitPaneInsertion(paneID: notePane, operation: .addAfter, state: store.state))
            return store.insertSplitPane(draft, tabID: noteTab, navigationURL: nil, creation: nil,
                                         savedHomeIDs: [noteTab: homeID], documents: [noteTab: first])
        }
    }

    @MainActor @Test func aPinnedNoteIsPlannedAHomeBeforeTheMove() throws {
        let f = try Fixture()
        let n = try Notes(f)
        let draft = try #require(SplitPaneInsertion(paneID: n.notePane, operation: .addAfter, state: f.store.state))
        let homes = try #require(OriginalSplitDrop.savedHomes(source: n.noteTab, state: f.store.state, selection: draft.selection, layout: draft.layout,
            target: .insert(draft.index), orientation: draft.orientation, spaceID: n.home))
        #expect(homes.map(\.id) == [n.noteTab])
    }

    @MainActor @Test func addSplitAcceptsAPinnedNoteFromAnotherSpace() throws {
        let f = try Fixture()
        let n = try Notes(f)
        #expect(try n.join(f.store, homeID: UUID()))
    }

    @MainActor @Test func theNotesSavedHomeStaysInItsSpaceAndTheNoteJoins() throws {
        let f = try Fixture()
        let n = try Notes(f)
        let homeID = UUID()
        _ = try n.join(f.store, homeID: homeID)
        #expect(f.store.state.tabs.first { $0.id == homeID }?.spaceID == n.other)
        #expect(f.store.state.selectedTabIDs.contains(n.noteTab))
    }

    @MainActor @Test func optionReturnAcceptsAPinnedNoteWithItsPlannedHome() throws {
        let f = try Fixture()
        let n = try Notes(f)
        _ = try n.join(f.store, homeID: UUID())
        let homeID = UUID()
        #expect(f.store.insertCommandBarSplit(after: n.noteTab, expectedSelection: f.store.state.selectedTabIDs, tabID: n.noteTab2,
            savedHomeIDs: [n.noteTab2: homeID], documents: [n.noteTab2: n.second]))
        #expect(f.store.state.tabs.first { $0.id == homeID }?.spaceID == n.other)
    }

    @MainActor private struct Folders {
        let home: UUID, other: UUID, profile: UUID
        let p1: UUID, p2: UUID
        let outer: UUID
        let group: BrowserSplitLayout
        let snapshot: SidebarHierarchySnapshot

        init(_ store: BrowserStore) throws {
            let home = store.activeSpaceID
            let other = store.createSpace(name: "Other")
            store.selectSpace(home)
            let p1 = store.open("https://p1.invalid"), p2 = store.open("https://p2.invalid")
            let outer = store.createFolder(name: "Outer")
            store.setSplit([p1, p2])
            let group = store.activeSplitLayout!
            let profile = store.activeSpace.profileID
            let intoOuter = SidebarHierarchySnapshot(state: store.state, spaceID: home, profileID: profile, includesFavorites: true)!
            try #require(try store.moveSidebarItem(.split(group.id), to: SidebarContainerLocation(spaceID: home, folderID: outer, section: .pinned),
                                                   before: nil, expected: intoOuter))
            store.toggleFolder(outer)
            store.selectSpace(other)
            snapshot = SidebarHierarchySnapshot(state: store.state, spaceID: home, profileID: profile, includesFavorites: true)!
            self.home = home; self.other = other
            self.p1 = p1; self.p2 = p2; self.outer = outer; self.group = group; self.profile = profile
        }

        func make(_ store: BrowserStore, id: UUID = UUID()) throws -> SidebarFolderFromItems? {
            try store.createFolder(containing: [.split(group.id)], folderID: id, expected: snapshot)
        }
    }

    @MainActor @Test func theFolderTakesTheDefaultNameInsideTheSplitsParentFolder() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let id = UUID()
        #expect(try s.make(f.store, id: id) != nil)
        let made = f.store.state.folders.first { $0.id == id }
        #expect(made?.name == SidebarFolderFromItems.defaultName)
        #expect(made?.parentID == s.outer)
        #expect(made?.spaceID == s.home)
    }

    @MainActor @Test func aCollapsedAncestorExpands() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        _ = try s.make(f.store)
        #expect(f.store.state.folders.first { $0.id == s.outer }?.isExpanded == true)
    }

    @MainActor @Test func theFolderIsMadeInTheWindowsSpaceWhileAnotherSpaceIsActive() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        _ = try s.make(f.store)
        #expect(f.store.activeSpaceID == s.other)
    }

    @MainActor @Test func theWholeSplitMovesIntoTheFolderAndStaysASplit() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let id = UUID()
        _ = try s.make(f.store, id: id)
        #expect([s.p1, s.p2].allSatisfy { tab in f.store.state.tabs.first { $0.id == tab }?.folderID == id })
        #expect(f.store.state.splitLayouts.contains { $0.id == s.group.id && $0.tabIDs == [s.p1, s.p2] })
    }

    @MainActor @Test func theFolderHoldsTheSplit() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let id = UUID()
        _ = try s.make(f.store, id: id)
        #expect(SidebarHierarchy.children(in: SidebarContainerLocation(spaceID: s.home, folderID: id, section: .pinned),
                                          state: f.store.state) == [.split(s.group.id)])
    }

    @MainActor @Test func aStaleHierarchyRefusesToMakeAFolder() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        _ = try s.make(f.store)
        #expect(try s.make(f.store) == nil)
    }

    @MainActor @Test func theFolderAndMovePersist() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let id = UUID()
        _ = try s.make(f.store, id: id)
        #expect(try f.reopened().state.folders.contains { $0.id == id })
    }

    @MainActor private func undone(_ f: Fixture, _ s: Folders) throws -> (made: UUID, before: BrowserState, receipt: SidebarFolderFromItems, undo: SidebarFolderFromItems) {
        let before = f.store.state, id = UUID()
        let receipt = try #require(try s.make(f.store, id: id))
        f.store.renameFolder(s.outer, name: "Renamed outer")
        f.store.updateTab(s.p1, title: "Changed title")
        f.store.renameFolder(id, name: "Named by the prompt")
        let undo = try #require(try f.store.revertFolderCreation(receipt, undo: true))
        return (id, before, receipt, undo)
    }

    @MainActor @Test func undoRemovesTheFolderAndRestoresPlacement() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let r = try undone(f, s)
        #expect(!f.store.state.folders.contains { $0.id == r.made })
        #expect(f.store.state.sidebarItemOrder == r.before.sidebarItemOrder)
        #expect([s.p1, s.p2].allSatisfy { tab in f.store.state.tabs.first { $0.id == tab }?.folderID == s.outer })
    }

    @MainActor @Test func undoKeepsUnrelatedEdits() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        _ = try undone(f, s)
        #expect(f.store.state.tabs.first { $0.id == s.p1 }?.title == "Changed title")
        #expect(f.store.state.folders.first { $0.id == s.outer }?.name == "Renamed outer")
    }

    @MainActor @Test func undoAppliesOnce() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let r = try undone(f, s)
        #expect(try f.store.revertFolderCreation(r.undo, undo: true) == nil)
    }

    @MainActor @Test func redoRecreatesTheSameFolderWithTheNameEnteredAfterCreation() throws {
        let f = try Fixture()
        let s = try Folders(f.store)
        let r = try undone(f, s)
        #expect(try f.store.revertFolderCreation(r.undo, undo: false) != nil)
        #expect(f.store.state.folders.first { $0.id == r.made }?.name == "Named by the prompt")
    }

    @MainActor @Test func aTodayItemsFolderIsMadeInThePinnedRoot() throws {
        let f = try Fixture()
        let home = f.store.activeSpaceID
        let item = f.store.open("https://loose.invalid")
        f.store.setSplit([item])
        let profile = f.store.activeSpace.profileID
        let snapshot = try #require(SidebarHierarchySnapshot(state: f.store.state, spaceID: home, profileID: profile, includesFavorites: true))
        let folder = UUID()
        #expect(try f.store.createFolder(containing: [.tab(item)], folderID: folder, expected: snapshot) != nil)
        #expect(f.store.state.folders.first { $0.id == folder }?.parentID == nil)
        #expect(f.store.state.tabs.first { $0.id == item }?.folderID == folder)
    }

    @MainActor private struct TodayOrder {
        let home: UUID, profile: UUID
        let x: UUID, y: UUID, z: UUID
        let order: [UUID]

        init(_ store: BrowserStore) {
            let home = store.activeSpaceID
            self.home = home
            profile = store.activeSpace.profileID
            x = store.open("https://x.invalid"); y = store.open("https://y.invalid"); z = store.open("https://z.invalid")
            order = SidebarTodayArchive.order(in: store.state, spaceID: home)
        }
    }

    @MainActor @Test func newTodayTabsOpenAtTheTopSoSidebarOrderDiffersFromArrayOrder() throws {
        let f = try Fixture()
        let s = TodayOrder(f.store)
        let top = try #require(s.order.firstIndex(of: s.z)), bottom = try #require(s.order.firstIndex(of: s.x))
        #expect(top < bottom)
    }

    @MainActor @Test func theCurrentTodayOrderAdmitsAnArchiveGroup() throws {
        let f = try Fixture()
        let s = TodayOrder(f.store)
        #expect(SidebarTodayArchive.admits(anchorID: s.y, order: s.order, ids: [s.x], state: f.store.state, spaceID: s.home, profileID: s.profile))
    }

    @MainActor @Test func theTabArrayOrderIsNotTheSidebarOrder() throws {
        let f = try Fixture()
        let s = TodayOrder(f.store)
        let arrayOrder = f.store.state.tabs.filter { $0.kind == .today && $0.spaceID == s.home && $0.archivedAt == nil }.map(\.id)
        #expect(!SidebarTodayArchive.admits(anchorID: s.y, order: arrayOrder, ids: [s.x], state: f.store.state, spaceID: s.home, profileID: s.profile))
    }
}
