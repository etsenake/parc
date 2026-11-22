import Foundation
import Testing
@testable import ParcCore

struct SplitSeparateAllOtherSpacesTests {
    private typealias Fixture = SplitSeparateAllTestsSupport.Fixture

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
}
