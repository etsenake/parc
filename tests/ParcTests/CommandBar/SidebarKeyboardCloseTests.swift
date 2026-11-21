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

    @MainActor private func withStore(_ fixture: Fixture, check: (BrowserStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(fixture.state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        store.scheduleDeferredSave = { _, _ in }
        try check(store)
    }

    @Test(arguments: [false, true])
    @MainActor func aSavedCloseRequiresTheOriginalSelectionAtConsent(current: Bool) throws {
        let fixture = Fixture()
        try withStore(fixture) { store in
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
        try withStore(fixture) { store in
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
