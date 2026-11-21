import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct SidebarKeyboardCloseTests {
    private struct Fixture {
        let profile = BrowserProfile(id: UUID(), name: "Personal")
        let space: BrowserSpace
        let folder: BrowserFolder
        let saved: BrowserTab
        let today: BrowserTab
        let empty: BrowserFolder
        let nested: BrowserFolder
        let state: BrowserState

        init() {
            let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            self.space = space
            folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Saved")
            empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty")
            nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: empty.id)
            let address = "https://example.test/"
            saved = BrowserTab(id: UUID(), spaceID: space.id, profileID: profile.id, url: address + "away", title: "Away",
                kind: .pinned, folderID: folder.id, createdAt: .distantPast, lastAccessed: .distantPast,
                savedURL: address, savedTitle: "Saved")
            today = BrowserTab(id: UUID(), spaceID: space.id, profileID: profile.id, url: address + "today", title: "Today",
                kind: .today, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: address + "today", savedTitle: "Today")
            var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
            state.folders = [folder, empty, nested]
            state.tabs = [saved, today]
            state.selectedTabIDs = [saved.id]
            state.selectionBySpace[space.id.uuidString] = state.selectedTabIDs
            self.state = state
        }

        func target(_ items: [SidebarItemReference], in state: BrowserState? = nil) -> SidebarKeyboardCloseTarget? {
            SidebarKeyboardCloseTarget(items: items, spaceID: space.id, profileID: profile.id, state: state ?? self.state)
        }
    }

    @Test(arguments: [false, true])
    func selectingATodayTabArchivesTheEntireSelection(hasToday: Bool) throws {
        let fixture = Fixture()
        let items: [SidebarItemReference] = [.folder(fixture.folder.id)] + (hasToday ? [.tab(fixture.today.id)] : [])
        let target = try #require(fixture.target(items))
        #expect(target.archivesItems == hasToday)
        #expect(target.requiresConfirmation == hasToday)
    }

    @Test func closingOnlyEmptyFoldersDeduplicatesSelectedDescendants() throws {
        let fixture = Fixture()
        let target = try #require(fixture.target([.folder(fixture.empty.id), .folder(fixture.nested.id)]))
        #expect(target.holdsOnlyEmptyFolders)
        #expect(target.items.roots == [.folder(fixture.empty.id)])
        #expect(Set(target.items.folderIDs) == Set([fixture.empty.id, fixture.nested.id]))
    }

    @Test(arguments: [false, true])
    func anInvalidRootRefusesTheEntireSelection(duplicate: Bool) {
        let fixture = Fixture()
        let id = duplicate ? fixture.today.id : UUID()
        #expect(fixture.target([.tab(fixture.today.id), .tab(id)]) == nil)
    }

    @Test func aForeignFolderDescendantRefusesTheEntireSelection() {
        let fixture = Fixture()
        var state = fixture.state
        state.tabs[0].profileID = UUID()
        #expect(fixture.target([.folder(fixture.folder.id), .tab(fixture.today.id)], in: state) == nil)
    }

    @MainActor private func withStore(_ state: BrowserState, check: (BrowserStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        store.scheduleDeferredSave = { _, _ in }
        try check(store)
    }

    @Test(arguments: [false, true])
    @MainActor func aSavedCloseRequiresTheOriginalSelectionAtConsent(current: Bool) throws {
        let fixture = Fixture()
        try withStore(fixture.state) { store in
            let before = store.state
            var confirm: (() -> Bool)?
            var finish: ((Bool) -> Void)?
            store.requestPageRetirement = { ids, validate, done in
                #expect(ids == [fixture.saved.id])
                confirm = validate
                finish = done
            }
            var stillCurrent = true
            var result: Bool?
            store.closeTabs([fixture.saved.id], shouldCommit: { stillCurrent }) { result = $0 }
            stillCurrent = current
            #expect(confirm?() == current)
            let complete = try #require(finish)
            complete(true)
            #expect(result == current)
            if current {
                #expect(store.state.tab(fixture.saved.id)?.url == fixture.saved.savedURL)
                #expect(store.state.tab(fixture.saved.id)?.archivedAt == nil)
                #expect(store.state.folders == before.folders)
            } else {
                #expect(store.state == before)
            }
        }
    }

    @Test(arguments: [false, true])
    @MainActor func aMixedCloseCommitsItsEntireCollectionOnlyAfterConsent(consent: Bool) throws {
        let fixture = Fixture()
        try withStore(fixture.state) { store in
            let before = store.state
            let target = try #require(fixture.target([.folder(fixture.folder.id), .tab(fixture.today.id)], in: before))
            var approve: (() -> Bool)?
            var finish: ((Bool) -> Void)?
            store.requestPageRetirement = { ids, validate, done in
                #expect(ids == [fixture.saved.id, fixture.today.id])
                approve = validate
                finish = done
            }
            var result: Result<Bool, Error>?
            store.deleteFolder(target.items, shouldCommit: { true }, didCommit: { _ in }) { result = $0 }
            #expect(store.state == before)
            let authorize = try #require(approve)
            let complete = try #require(finish)
            complete(consent && authorize())
            let committed = try result?.get()
            #expect(committed == consent)
            #expect(store.state.folders.contains(fixture.folder) == !consent)
        }
    }
}

extension SidebarKeyboardCloseTests {
    @Test @MainActor func deletingOnlyEmptyFoldersRequiresNoPageConsent() throws {
        let fixture = Fixture()
        try withStore(fixture.state) { store in
            let before = store.state
            let target = try #require(fixture.target([.folder(fixture.empty.id), .folder(fixture.nested.id)], in: before))
            var admissions = 0
            var result: Result<Bool, Error>?
            store.requestPageRetirement = { _, _, _ in admissions += 1 }
            store.deleteFolder(target.items, shouldCommit: { true }) { result = $0 }
            let committed = try result?.get()
            #expect(committed == true)
            #expect(admissions == 0)
            #expect(store.state.folders == [fixture.folder])
            #expect(store.state.tabs == before.tabs)
        }
    }

    @Test @MainActor func undoRestoresTheOriginalFolderTreeAndTabs() throws {
        let fixture = Fixture()
        try withStore(fixture.state) { store in
            let before = store.state
            let target = try #require(fixture.target([.folder(fixture.folder.id), .tab(fixture.today.id)], in: before))
            var result: Result<Bool, Error>?
            var undo: FolderDeletionUndo?
            store.deleteFolder(target.items, shouldCommit: { true }, didCommit: { undo = $0 }) { result = $0 }
            let archived = try result?.get()
            try #require(archived == true)
            let record = try #require(undo)
            #expect(try store.undoFolderDeletion(record, shouldCommit: { true }))
            #expect(Set(store.state.folders.map(\.id)) == Set(before.folders.map(\.id)))
            #expect(store.state.folders.allSatisfy(before.folders.contains))
            let location = SidebarContainerLocation(spaceID: fixture.space.id, folderID: nil, section: .pinned)
            #expect(SidebarHierarchy.children(in: location, state: store.state) == SidebarHierarchy.children(in: location, state: before))
            #expect(store.state.tabs == before.tabs)
        }
    }

    @Test(arguments: [false, true])
    func aHiddenSplitChildCannotBeClosedAsAnIndependentRow(saved: Bool) throws {
        let fixture = Fixture()
        var state = fixture.state
        var second = fixture.today
        let first = saved ? fixture.saved : fixture.today
        second.id = UUID()
        second.kind = first.kind
        second.folderID = first.folderID
        state.tabs.append(second)
        let split = BrowserSplitLayout(sidebarAnchorID: first.id, spaceID: fixture.space.id,
                                      tabIDs: [first.id, second.id], widthFactors: [0.25, 0.75])
        state.splitLayouts = [split]
        let grouped = try #require(fixture.target([.split(split.id)], in: state))
        #expect(grouped.archivesItems == !saved)
        #expect(fixture.target([.tab(first.id)], in: state) == nil)
    }
}
