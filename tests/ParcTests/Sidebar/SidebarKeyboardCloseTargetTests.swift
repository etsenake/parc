import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarKeyboardCloseTargetTests {
    @MainActor final class Fixture {
        let root: URL
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space: BrowserSpace
        let folder: BrowserFolder
        let noteFile: URL
        let noteBytes: Data
        let note: BrowserTab
        let saved: BrowserTab
        let todayOne: BrowserTab
        let todayTwo: BrowserTab
        let keep: BrowserTab
        let alias: BrowserTab
        let group: BrowserSplitLayout
        let todayGroup: BrowserSplitLayout
        private(set) var initial: BrowserState

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-keyboard-close-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Saved")
            let notesFolder = root.appendingPathComponent("Parc Notes")
            try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
            noteFile = notesFolder.appendingPathComponent("Original.md")
            try Data("Original body\n".utf8).write(to: noteFile)
            noteBytes = try Data(contentsOf: noteFile)
            let spaceID = space.id, profileID = profile.id
            func tab(_ title: String, kind: TabKind, folderID: UUID? = nil, url: String = "https://original.invalid/") -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: spaceID, profileID: profileID, url: url, title: title,
                           kind: kind, folderID: folderID, createdAt: Date(timeIntervalSince1970: 1),
                           lastAccessed: Date(timeIntervalSince1970: 2), savedURL: url, savedTitle: title)
            }
            note = tab("Note", kind: .pinned, folderID: folder.id, url: InternalPage.note(noteFile).urlString)
            var away = tab("Saved", kind: .pinned, folderID: folder.id)
            away.url = "https://original.invalid/away"
            away.title = "Away"
            saved = away
            todayOne = tab("Today one", kind: .today)
            todayTwo = tab("Today two", kind: .today)
            keep = tab("Keep", kind: .pinned)
            alias = tab("Alias", kind: .pinned, url: note.url)
            group = BrowserSplitLayout(sidebarAnchorID: note.id, customTitle: "Saved split", spaceID: space.id,
                                       tabIDs: [note.id, saved.id], orientation: .vertical, widthFactors: [0.25, 0.75])
            todayGroup = BrowserSplitLayout(sidebarAnchorID: todayOne.id, customTitle: "Today split", spaceID: space.id,
                                            tabIDs: [todayOne.id, todayTwo.id], orientation: .horizontal, widthFactors: [0.6, 0.4])
            var seed = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
            seed.folders = [folder]
            seed.tabs = [note, saved, todayOne, todayTwo, keep, alias]
            seed.splitLayouts = [group, todayGroup]
            seed.selectedTabIDs = group.tabIDs
            seed.selectionBySpace[space.id.uuidString] = group.tabIDs
            initial = seed
            initial = try store("normalized").state
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func store(_ name: String, seed: BrowserState? = nil) throws -> BrowserStore {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(seed ?? initial).write(to: directory.appendingPathComponent("session.json"))
            return try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        }

        func target(_ items: [SidebarItemReference], state: BrowserState? = nil) -> SidebarKeyboardCloseTarget? {
            SidebarKeyboardCloseTarget(items: items, spaceID: space.id, profileID: profile.id, state: state ?? initial)
        }

        var savedTarget: SidebarKeyboardCloseTarget? { target([.folder(folder.id), .split(group.id), .tab(keep.id)]) }
        var mixedTarget: SidebarKeyboardCloseTarget? { target([.folder(folder.id), .split(todayGroup.id)]) }

        var documents: [UUID: SidebarDocumentReference] {
            let file = noteFile
            return [note.id: SidebarDocumentReference(page: .note(file), profileID: profile.id, validate: {
                guard FileManager.default.fileExists(atPath: file.path) else { throw CocoaError(.fileNoSuchFile) }
            })]
        }

        var roomy: (state: BrowserState, later: BrowserFolder, someday: BrowserFolder, nested: BrowserFolder) {
            get throws {
                let later = BrowserFolder(id: UUID(), spaceID: space.id, name: "Later")
                let someday = BrowserFolder(id: UUID(), spaceID: space.id, name: "Someday")
                let nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: someday.id)
                var seed = initial
                seed.folders += [later, someday, nested]
                return (try store("roomy-normalized", seed: seed).state, later, someday, nested)
            }
        }
    }

    @MainActor final class Retirement {
        var requested = Set<UUID>()
        var authorize: (() -> Bool)?
        var finish: ((Bool) -> Void)?
        var admissions = 0

        func attach(to store: BrowserStore) {
            store.requestPageRetirement = { [weak self] ids, validate, done in
                guard let self else { return }
                requested = ids
                authorize = validate
                finish = done
                admissions += 1
            }
        }
    }

    private func committedSavedClose(_ fixture: Fixture) throws -> BrowserStore {
        let store = try fixture.store("saved")
        let retirement = Retirement()
        retirement.attach(to: store)
        let target = try #require(fixture.savedTarget)
        var allowed: Bool?
        store.closeTabs(Set(target.items.tabs.map(\.id)), shouldCommit: { true }) { allowed = $0 }
        #expect(retirement.authorize?() == true)
        retirement.finish?(true)
        try #require(allowed == true)
        return store
    }

    private func committedMixedClose(_ fixture: Fixture) throws -> (BrowserStore, Retirement, FolderDeletionUndo) {
        let store = try fixture.store("mixed")
        let retirement = Retirement()
        retirement.attach(to: store)
        let target = try #require(fixture.mixedTarget)
        var result: Result<Bool, Error>?
        var undo: FolderDeletionUndo?
        store.deleteFolder(target.items, documents: fixture.documents, shouldCommit: { true }, didCommit: { undo = $0 }) { result = $0 }
        #expect(retirement.authorize?() == true)
        retirement.finish?(true)
        try #require((try result?.get()) == true)
        return (store, retirement, try #require(undo))
    }

    @Test func allSavedRootsDeselectInsteadOfArchiving() throws {
        let target = try #require(try Fixture().savedTarget)
        #expect(!target.archivesItems)
        #expect(!target.requiresConfirmation)
    }

    @Test func aNestedSelectedSplitIsOwnedOnceByItsFolder() throws {
        let fixture = try Fixture()
        let target = try #require(fixture.savedTarget)
        #expect(target.items.roots == [.folder(fixture.folder.id), .tab(fixture.keep.id)])
    }

    @Test func aSavedCloseBindsTheOriginalDescendants() throws {
        let fixture = try Fixture()
        let target = try #require(fixture.savedTarget)
        #expect(target.items.tabs.map(\.id) == [fixture.note.id, fixture.saved.id, fixture.keep.id])
    }

    @Test func anyTodayRootArchivesTheWholeCollectionWithFolderConfirmation() throws {
        let target = try #require(try Fixture().mixedTarget)
        #expect(target.archivesItems)
        #expect(target.requiresConfirmation)
    }

    @Test func savedAndTodayTabsTogetherNeedNoFolderWarning() throws {
        let fixture = try Fixture()
        let target = try #require(fixture.target([.tab(fixture.keep.id), .split(fixture.todayGroup.id)]))
        #expect(target.archivesItems)
        #expect(!target.requiresConfirmation)
    }

    @Test func aTodaySplitArchivesThroughItsSidebarContainer() throws {
        let fixture = try Fixture()
        #expect(fixture.target([.split(fixture.todayGroup.id)])?.archivesItems == true)
    }

    @Test func aPinnedSplitStaysSavedAfterNavigatingAway() throws {
        let fixture = try Fixture()
        #expect(fixture.target([.split(fixture.group.id)])?.archivesItems == false)
    }

    enum RefusedSelection: CaseIterable, Sendable {
        case hiddenSplitChild, missingRoot, duplicate, foreignChild
    }

    @Test(arguments: RefusedSelection.allCases)
    func aSelectionThatCannotCloseWholeIsRefused(_ selection: RefusedSelection) throws {
        let fixture = try Fixture()
        switch selection {
        case .hiddenSplitChild:
            #expect(fixture.target([.tab(fixture.note.id)]) == nil)
        case .missingRoot:
            #expect(fixture.target([.folder(UUID()), .split(fixture.todayGroup.id)]) == nil)
        case .duplicate:
            #expect(fixture.target([.tab(fixture.keep.id), .tab(fixture.keep.id)]) == nil)
        case .foreignChild:
            var changed = fixture.initial
            changed.tabs[0].profileID = UUID()
            #expect(fixture.target([.folder(fixture.folder.id), .split(fixture.todayGroup.id)], state: changed) == nil)
        }
    }

    @Test func aSavedCloseAsksForOnePageConsent() throws {
        let fixture = try Fixture()
        let store = try fixture.store("saved")
        let retirement = Retirement()
        retirement.attach(to: store)
        let ids = Set(try #require(fixture.savedTarget).items.tabs.map(\.id))
        var allowed: Bool?
        store.closeTabs(ids, shouldCommit: { true }) { allowed = $0 }
        #expect(retirement.requested == ids)
        #expect(retirement.admissions == 1)
        #expect(allowed == nil)
    }

    @Test func aChangedSelectionRefusesTheSavedCommitAndKeepsEverything() throws {
        let fixture = try Fixture()
        let store = try fixture.store("saved")
        let retirement = Retirement()
        retirement.attach(to: store)
        let ids = Set(try #require(fixture.savedTarget).items.tabs.map(\.id))
        var allowed: Bool?
        store.closeTabs(ids, shouldCommit: { false }) { allowed = $0 }
        #expect(retirement.authorize?() == false)
        retirement.finish?(true)
        #expect(allowed == false)
        #expect(store.state == fixture.initial)
    }

    @Test func theSavedOwnerCanRetryAfterARefusal() throws {
        let fixture = try Fixture()
        let store = try fixture.store("saved")
        let retirement = Retirement()
        retirement.attach(to: store)
        let ids = Set(try #require(fixture.savedTarget).items.tabs.map(\.id))
        var current = false
        var allowed: Bool?
        store.closeTabs(ids, shouldCommit: { current }) { allowed = $0 }
        retirement.finish?(true)
        current = true
        store.closeTabs(ids, shouldCommit: { current }) { allowed = $0 }
        #expect(retirement.authorize?() == true)
        retirement.finish?(true)
        #expect(allowed == true)
    }

    @Test func aSavedCloseArchivesNothingAndKeepsFoldersAndSplits() throws {
        let fixture = try Fixture()
        let store = try committedSavedClose(fixture)
        #expect(store.state.tabs.allSatisfy { $0.archivedAt == nil })
        #expect(store.state.folders == fixture.initial.folders)
        #expect(store.state.splitLayouts.contains(fixture.group))
        #expect(store.state.splitLayouts.contains(fixture.todayGroup))
    }

    @Test func aSavedCloseResetsLiveContentToItsSavedDestination() throws {
        let fixture = try Fixture()
        let tab = try #require(try committedSavedClose(fixture).state.tabs.first { $0.id == fixture.saved.id })
        #expect(tab.url == fixture.saved.savedURL)
        #expect(tab.title == fixture.saved.savedTitle)
    }

    @Test func aSavedCloseSurvivesPersistence() throws {
        let fixture = try Fixture()
        let store = try committedSavedClose(fixture)
        try store.save()
        let disk = try BrowserStore(directory: store.directory)
        #expect(disk.state.splitLayouts.contains(fixture.group))
        #expect(disk.state.tabs.first { $0.id == fixture.saved.id }?.url == fixture.saved.savedURL)
    }

    @Test func aMixedCloseAsksOnceForTheWholeCollection() throws {
        let fixture = try Fixture()
        let store = try fixture.store("mixed")
        let retirement = Retirement()
        retirement.attach(to: store)
        var result: Result<Bool, Error>?
        store.deleteFolder(try #require(fixture.mixedTarget).items, documents: fixture.documents,
                           shouldCommit: { true }, didCommit: { _ in }) { result = $0 }
        #expect(retirement.admissions == 1)
        #expect(retirement.requested == [fixture.note.id, fixture.saved.id, fixture.todayOne.id, fixture.todayTwo.id])
        #expect(result == nil)
    }

    @Test func oneNativeRefusalPreservesEveryMixedRoot() throws {
        let fixture = try Fixture()
        let store = try fixture.store("mixed")
        let retirement = Retirement()
        retirement.attach(to: store)
        var result: Result<Bool, Error>?
        var undo: FolderDeletionUndo?
        store.deleteFolder(try #require(fixture.mixedTarget).items, documents: fixture.documents,
                           shouldCommit: { true }, didCommit: { undo = $0 }) { result = $0 }
        retirement.finish?(false)
        #expect((try result?.get()) == false)
        #expect(store.state == fixture.initial)
        #expect(undo == nil)
    }

    @Test func aConsentedMixedCloseRemovesFoldersAndArchivesTheCollection() throws {
        let fixture = try Fixture()
        let (store, retirement, _) = try committedMixedClose(fixture)
        #expect(store.state.folders.isEmpty)
        #expect(store.state.tabs.filter { retirement.requested.contains($0.id) }.allSatisfy { $0.archivedAt != nil })
        #expect(store.state.splitLayouts.isEmpty)
    }

    @Test func aMixedCloseLeavesAnUnselectedDocumentAliasAndTheNoteFileAlone() throws {
        let fixture = try Fixture()
        let (store, _, _) = try committedMixedClose(fixture)
        #expect(store.state.tabs.first { $0.id == fixture.alias.id } == fixture.alias)
        #expect(try Data(contentsOf: fixture.noteFile) == fixture.noteBytes)
    }

    @Test func aMixedCloseKeepsTheTodaySplitReopenStep() throws {
        let fixture = try Fixture()
        let (store, _, _) = try committedMixedClose(fixture)
        let intent = try #require(ClosedItemIntent(ids: [fixture.todayOne.id, fixture.todayTwo.id], state: fixture.initial,
                                                   spaceID: fixture.space.id, profileID: fixture.profile.id,
                                                   focusedTabID: fixture.todayTwo.id))
        var reopen = WindowClosedItems()
        reopen.record(intent, in: store.state)
        let step = reopen.next(in: store.state)
        #expect(step?.tabIDs == [fixture.todayOne.id, fixture.todayTwo.id])
        #expect(step?.split == fixture.todayGroup)
        #expect(step?.focusedTabID == fixture.todayTwo.id)
        #expect(step?.profileID == fixture.profile.id)
    }

    @Test func undoingAMixedCloseRestoresTheOriginalRecords() throws {
        let fixture = try Fixture()
        let (store, _, record) = try committedMixedClose(fixture)
        #expect(record.groups == fixture.initial.splitLayouts)
        let target = try #require(fixture.mixedTarget)
        #expect(record.roots == target.items.roots)
        #expect(try store.undoFolderDeletion(record, shouldCommit: { true }))
        #expect(store.state.tabs == fixture.initial.tabs)
        #expect(store.state.folders == fixture.initial.folders)
        #expect(store.state.splitLayouts == fixture.initial.splitLayouts)
    }

    @Test func severalEmptyFoldersDeleteInsteadOfClosing() throws {
        let fixture = try Fixture()
        let roomy = try fixture.roomy
        let target = try #require(fixture.target([.folder(roomy.later.id), .folder(roomy.someday.id), .folder(roomy.nested.id)],
                                                 state: roomy.state))
        #expect(target.holdsOnlyEmptyFolders)
        #expect(!target.archivesItems)
        #expect(target.items.tabs.isEmpty)
    }

    @Test func aSelectedEmptySubfolderGoesOnceWithItsEmptyParent() throws {
        let fixture = try Fixture()
        let roomy = try fixture.roomy
        let target = try #require(fixture.target([.folder(roomy.later.id), .folder(roomy.someday.id), .folder(roomy.nested.id)],
                                                 state: roomy.state))
        #expect(Set(target.items.roots) == [.folder(roomy.later.id), .folder(roomy.someday.id)])
        #expect(Set(target.items.folderIDs) == [roomy.later.id, roomy.someday.id, roomy.nested.id])
    }

    enum EmptyFolderSelection: CaseIterable, Sendable {
        case twoEmptyFolders, savedWithTabs, tabAndSplit, emptyWithTabFolder, emptyWithTab
        var deletes: Bool { self == .twoEmptyFolders }
    }

    @Test(arguments: EmptyFolderSelection.allCases)
    func onlyEmptyFolderSelectionsDelete(_ selection: EmptyFolderSelection) throws {
        let fixture = try Fixture()
        let roomy = try fixture.roomy
        let items: [SidebarItemReference] = switch selection {
        case .twoEmptyFolders: [.folder(roomy.later.id), .folder(roomy.someday.id)]
        case .savedWithTabs: [.folder(fixture.folder.id), .split(fixture.group.id), .tab(fixture.keep.id)]
        case .tabAndSplit: [.tab(fixture.keep.id), .split(fixture.todayGroup.id)]
        case .emptyWithTabFolder: [.folder(fixture.folder.id), .folder(roomy.later.id)]
        case .emptyWithTab: [.folder(roomy.later.id), .tab(fixture.keep.id)]
        }
        #expect(fixture.target(items, state: roomy.state)?.holdsOnlyEmptyFolders == selection.deletes)
    }

    @Test func deletingEmptyFoldersAsksNoPageAndTouchesOnlyThoseFolders() throws {
        let fixture = try Fixture()
        let roomy = try fixture.roomy
        let target = try #require(fixture.target([.folder(roomy.later.id), .folder(roomy.someday.id), .folder(roomy.nested.id)],
                                                 state: roomy.state))
        let store = try fixture.store("empty-folders", seed: roomy.state)
        let retirement = Retirement()
        retirement.attach(to: store)
        var result: Result<Bool, Error>?
        store.deleteFolder(target.items, shouldCommit: { true }, didCommit: { _ in }) { result = $0 }
        #expect((try result?.get()) == true)
        #expect(retirement.admissions == 0)
        #expect(store.state.folders == fixture.initial.folders)
        #expect(store.state.tabs == roomy.state.tabs)
        #expect(store.state.splitLayouts == roomy.state.splitLayouts)
    }

    @Test func undoPutsDeletedEmptyFoldersBackInPlace() throws {
        let fixture = try Fixture()
        let roomy = try fixture.roomy
        let target = try #require(fixture.target([.folder(roomy.later.id), .folder(roomy.someday.id), .folder(roomy.nested.id)],
                                                 state: roomy.state))
        let store = try fixture.store("empty-folders", seed: roomy.state)
        var undo: FolderDeletionUndo?
        store.deleteFolder(target.items, shouldCommit: { true }, didCommit: { undo = $0 }) { _ in }
        let record = try #require(undo)
        #expect(try store.undoFolderDeletion(record, shouldCommit: { true }))
        #expect(store.state.folders.count == roomy.state.folders.count)
        #expect(roomy.state.folders.allSatisfy(store.state.folders.contains))
        let pinnedRoot = SidebarContainerLocation(spaceID: fixture.space.id, folderID: nil, section: .pinned)
        #expect(SidebarHierarchy.children(in: pinnedRoot, state: store.state)
                == SidebarHierarchy.children(in: pinnedRoot, state: roomy.state))
    }
}
