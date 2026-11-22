import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSplitDocumentsTests {
    @Test @MainActor static func droppingAPageIntoAPinnedSplitUsesItsFolderAndPersists() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID
            let folder = store.createFolder(name: "Saved")
            let folderBox = SidebarContainerLocation(spaceID: space, folderID: folder, section: .pinned)
            let v1 = store.open("https://v1.example"), v2 = store.open("https://v2.example")
            let pinnedSplit = try BrowserStoreTestsSupport.savedSplit(store, [v1, v2], in: folderBox)
            store.selectTab(v1)
            let t4 = store.open("https://t4.example")
            store.selectTab(v1)
            #expect(store.dropTabIntoSplit(t4, expectedSelection: [v1, v2], expectedLayout: store.activeSplitLayout,
                target: .insert(2), orientation: pinnedSplit.orientation), "Drop a Today tab into a pinned split")
            #expect(try BrowserStoreTestsSupport.tab(t4, in: store).kind == .pinned && (try BrowserStoreTestsSupport.tab(t4, in: store)).folderID == folder
                       && store.activeSplitLayout?.tabIDs == [v1, v2, t4], "The dropped tab enters the pinned split's folder")

            try store.save()
            let reopened = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            #expect(reopened.state == store.state, "Container membership and slots survive restart")
        }
    }

    @Test @MainActor static func addingANewURLBesideATodayNoteNeedsNoSavedHome() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let documentID = URL(fileURLWithPath: directory.appendingPathComponent("Note.md").path)
            let note = store.openNote(url: documentID, title: "Note")!
            store.selectTab(note)
            let todayJoin = UUID()
            #expect(store.commandBarSplitHomes(after: note, expectedSelection: [note], tabID: todayJoin, isNew: true)?.isEmpty == true, "A Today Note does not leave a pinned home beside a new URL")
        }
    }

    @Test @MainActor static func aPinnedNoteNeedsALiveDocumentToPlanItsSplitHome() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let profile = store.activeSpace.profileID
            let documentID = URL(fileURLWithPath: directory.appendingPathComponent("Note.md").path)
            let note = store.openNote(url: documentID, title: "Note")!
            store.selectTab(note)
            store.setKind(note, .pinned)
            let newID = UUID()
            let noteHomes = store.commandBarSplitHomes(after: note, expectedSelection: [note], tabID: newID, isNew: true)!
            #expect(noteHomes.map(\.id) == [note], "The displayed pinned Note needs a home even beside a new URL")
            #expect(SplitMembership.homePlan(noteHomes) { _ in nil } == nil, "A typed home without a live document refuses")
            let reference = SidebarDocumentReference(page: .note(documentID), profileID: profile) { }
            let plan = SplitMembership.homePlan(noteHomes) { _ in [note: reference] }!
            #expect(Set(plan.ids.keys) == [note] && plan.documents.count == 1, "The plan fixes one validated Note home")
        }
    }

    @Test @MainActor static func aPinnedNoteLeavesAnAliasWhenJoiningANewTodaySplit() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let profile = store.activeSpace.profileID
            let documentID = URL(fileURLWithPath: directory.appendingPathComponent("Note.md").path)
            let note = store.openNote(url: documentID, title: "Note")!
            store.selectTab(note)
            store.setKind(note, .pinned)
            let newID = UUID()
            let noteHomes = store.commandBarSplitHomes(after: note, expectedSelection: [note], tabID: newID, isNew: true)!
            let reference = SidebarDocumentReference(page: .note(documentID), profileID: profile) { }
            let plan = SplitMembership.homePlan(noteHomes) { _ in [note: reference] }!
            #expect(store.insertCommandBarSplit(after: note, expectedSelection: [note], tabID: newID,
                newURL: URL(string: "https://new.example")!, savedHomeIDs: plan.ids, documents: plan.documents), "A lone Note pane splits with a new URL")
            let noteHome = store.state.tabs.first { $0.id == plan.ids[note] }!
            #expect(try noteHome.kind == .pinned && noteHome.savedURL == InternalPage.note(documentID).urlString
                       && (try BrowserStoreTestsSupport.tab(note, in: store)).kind == .today, "The Note joins Today and its alias home stays pinned")
        }
    }

    @Test @MainActor static func splitExtensionPlansUseTheInitiatingWindowsSelection() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID
            let p = store.open("https://p.example", kind: .pinned), q = store.open("https://q.example", kind: .pinned)
            let t = store.open("https://t.example")
            _ = store.setWindowPresentation(spaceID: space, selectedTabIDs: [p])
            #expect(store.splitExtensionHomes(q).map(\.id) == [p, q], "Window A's single pinned page also needs a home")
            _ = store.setWindowPresentation(spaceID: space, selectedTabIDs: [t])
            #expect(store.splitExtensionHomes(q).map(\.id) == [q], "Window B plans from its own synchronized selection")
        }
    }

    @Test @MainActor static func pinningOnePanePinsTheWholeSplit() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID
            let pinnedRoot = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let a = store.open("https://a.example"), b = store.open("https://b.example")
            store.selectTab(a); store.selectTab(b, extendingSplit: true)
            let pair = store.activeSplitLayout!
            store.setKind(b, .pinned)
            #expect(try BrowserStoreTestsSupport.tab(a, in: store).kind == .pinned && (try BrowserStoreTestsSupport.tab(b, in: store)).kind == .pinned
                       && SidebarHierarchy.children(in: pinnedRoot, state: store.state).contains(.split(pair.id)), "Pinning a split pane pins its whole split")
        }
    }

    @Test @MainActor static func unpinningOnePaneMovesTheWholeSplitToToday() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID
            let pinnedRoot = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            let a = store.open("https://a.example"), b = store.open("https://b.example")
            store.selectTab(a); store.selectTab(b, extendingSplit: true)
            let pair = store.activeSplitLayout!
            store.setKind(b, .pinned)
            try #require(try BrowserStoreTestsSupport.tab(a, in: store).kind == .pinned && (try BrowserStoreTestsSupport.tab(b, in: store)).kind == .pinned
                       && SidebarHierarchy.children(in: pinnedRoot, state: store.state).contains(.split(pair.id)), "Pinning a split pane pins its whole split")
            store.setKind(a, .today)
            #expect(try BrowserStoreTestsSupport.tab(a, in: store).kind == .today && (try BrowserStoreTestsSupport.tab(b, in: store)).kind == .today
                       && SidebarHierarchy.children(in: todayBox, state: store.state).contains(.split(pair.id)), "Unpinning a split pane unpins its whole split")
        }
    }

    @Test @MainActor static func restoringAWindowsSplitLeavesThePinnedHomeInPlace() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID
            let w1 = store.open("https://w1.example", kind: .pinned), w2 = store.open("https://w2.example")
            _ = store.setWindowPresentation(spaceID: space, selectedTabIDs: [w1, w2],
                splitLayout: BrowserSplitLayout(spaceID: space, tabIDs: [w1, w2], widthFactors: [0.5, 0.5]))
            let reformed = store.state.splitLayouts.first { $0.tabIDs == [w1, w2] }
            #expect(try reformed != nil && (try BrowserStoreTestsSupport.tab(w1, in: store)).kind == .today
                       && store.state.tabs.contains { $0.kind == .pinned && $0.savedURL == "https://w1.example" && $0.id != w1 }, "A window's own split re-forms through the membership owner")
        }
    }

    @Test @MainActor static func closingAPinnedPaneKeepsItsSavedDestinationBesideTheSplit() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID
            let pinnedRoot = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let x1 = store.open("https://x1.example"), x2 = store.open("https://x2.example"), x3 = store.open("https://x3.example")
            let pinnedSplit = try BrowserStoreTestsSupport.savedSplit(store, [x1, x2, x3], in: pinnedRoot)
            store.selectTab(x1)
            store.closeTab(x2)
            let afterClose = SidebarHierarchy.children(in: pinnedRoot, state: store.state)
            #expect(try store.state.splitLayouts.first { $0.id == pinnedSplit.id }?.tabIDs == [x1, x3]
                       && (try BrowserStoreTestsSupport.tab(x2, in: store)).kind == .pinned && (try BrowserStoreTestsSupport.tab(x2, in: store)).archivedAt == nil
                       && afterClose.firstIndex(of: .split(pinnedSplit.id)).map { $0 + 1 } == afterClose.firstIndex(of: .tab(x2)), "A closed pinned pane stays saved and follows its split")
        }
    }

    @Test @MainActor static func closingAFavoritePaneFromAnotherSpaceEditsTheSharedSplit() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let f1 = store.open("https://f1.example"), f2 = store.open("https://f2.example"), f3 = store.open("https://f3.example")
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            let favoriteSplit = try BrowserStoreTestsSupport.savedSplit(store, [f1, f2, f3], in: tray)
            let second = store.createSpace(name: "Second")
            store.selectTab(f1)
            #expect(store.activeSpaceID == second && store.activeSplitLayout?.id == favoriteSplit.id, "The Favorite split shows in Space 2")
            store.closeTab(f2)
            let trayFromSecond = SidebarHierarchy.children(in: .init(spaceID: second, folderID: nil, section: .favorite, profileID: profile), state: store.state)
            #expect(store.state.splitLayouts.first { $0.id == favoriteSplit.id }?.tabIDs == [f1, f3]
                       && trayFromSecond.firstIndex(of: .split(favoriteSplit.id)).map { $0 + 1 } == trayFromSecond.firstIndex(of: .tab(f2)), "Closing a Favorite split pane from another Space removes it from the one split")
        }
    }

    @Test @MainActor static func assigningAProfileMovesNoteRecordsButDoesNotMoveTheFile() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let documentID = URL(fileURLWithPath: directory.appendingPathComponent("Note.md").path)
            let note = store.openNote(url: documentID, title: "Note")!
            store.selectTab(note)
            store.setKind(note, .pinned)
            let newID = UUID()
            let noteHomes = store.commandBarSplitHomes(after: note, expectedSelection: [note], tabID: newID, isNew: true)!
            let reference = SidebarDocumentReference(page: .note(documentID), profileID: profile) { }
            let plan = SplitMembership.homePlan(noteHomes) { _ in [note: reference] }!
            #expect(store.insertCommandBarSplit(after: note, expectedSelection: [note], tabID: newID,
                newURL: URL(string: "https://new.example")!, savedHomeIDs: plan.ids, documents: plan.documents), "A lone Note pane splits with a new URL")
            let noteHome = store.state.tabs.first { $0.id == plan.ids[note] }!
            let other = store.createProfile(name: "Other")
            var relocatedNote = false
            store.relocateLocalDocuments = { _, _, _, _ in relocatedNote = true; return {} }
            store.assignProfile(other, toSpace: space)
            #expect(try !relocatedNote && (try BrowserStoreTestsSupport.tab(note, in: store)).profileID == other && (try BrowserStoreTestsSupport.tab(noteHome.id, in: store)).profileID == other, "Profile assignment carries the Note and its alias along while the note file stays put")
        }
    }

    @Test @MainActor static func aFavoriteSplitSurvivesReassignmentOfItsStoringSpace() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let f1 = store.open("https://f1.example"), f2 = store.open("https://f2.example"), f3 = store.open("https://f3.example")
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            let favoriteSplit = try BrowserStoreTestsSupport.savedSplit(store, [f1, f2, f3], in: tray)
            let second = store.createSpace(name: "Second")
            store.selectTab(f1)
            store.closeTab(f2)
            store.selectSpace(space)
            let other = store.createProfile(name: "Other")
            store.assignProfile(other, toSpace: space)
            let kept = store.state.splitLayouts.first { $0.id == favoriteSplit.id }
            #expect(kept?.spaceID == second && kept?.tabIDs == [f1, f3], "A Favorite split survives its storing Space changing Profile")
        }
    }
}
