import Foundation
import Testing
@testable import ParcCore

struct SplitSeparationTests {
    @MainActor private final class Fixture {
        let root: URL
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store: BrowserStore
        let a: UUID, b: UUID, c: UUID
        let folder: UUID, space: UUID, profile: UUID
        let group: BrowserSplitLayout
        let tabs: [BrowserTab]
        let folders: [BrowserFolder]
        let archive: [UUID]
        let history: [BrowserHistoryEntry]

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-separation-" + UUID().uuidString)
            let now = now
            let store = try BrowserStore(directory: root, now: { now })
            let a = store.open("https://one.invalid", kind: .pinned)
            let b = store.open("https://two.invalid"), c = store.open("https://three.invalid")
            let folder = store.createFolder(name: "Original")
            store.moveTab(a, toSpace: store.activeSpaceID, folderID: folder)
            store.setSplit([a, b, c])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let edit = SidebarSplitTitleEdit.current(state: store.state, spaceID: space, profileID: profile, selectedTabIDs: [a, b, c])!
            try store.saveSidebarSplitTitle(edit, title: "Original group")
            self.store = store
            self.a = a; self.b = b; self.c = c
            self.folder = folder; self.space = space; self.profile = profile
            group = store.activeSplitLayout!
            tabs = store.state.tabs
            folders = store.state.folders
            archive = store.state.recentlyClosedIDs
            history = store.state.history
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func reopened() throws -> BrowserStore {
            let now = now
            return try BrowserStore(directory: root, now: { now })
        }

        func remaining() -> BrowserSplitLayout {
            _ = store.separateSplitPane(b)
            return store.state.splitLayouts.first { $0.id == group.id }!
        }
    }

    @MainActor @Test func aPinnedMemberJoinsTheTodaySplitAndLeavesAFreshHomeInItsFolder() throws {
        let f = try Fixture()
        let items = SidebarHierarchy.children(in: .init(spaceID: f.space, folderID: f.folder, section: .pinned), state: f.store.state)
        #expect(items.count == 1)
        #expect(items != [.tab(f.a)])
        #expect(f.store.state.tabs.first { $0.id == f.a }?.kind == .today)
    }

    @MainActor @Test func theFocusedOriginalSeparatesThroughTheMainCommand() throws {
        let f = try Fixture()
        #expect(f.store.separateSplitPane(f.b))
    }

    @MainActor @Test func theFocusedOriginalRemainsTheSoleCurrentAndRememberedSelection() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        #expect(f.store.state.selectedTabIDs == [f.b])
        #expect(f.store.state.selectionBySpace[f.space.uuidString] == [f.b])
    }

    @MainActor @Test func siblingsKeepTheirOrderAndNormalizedRatios() throws {
        let f = try Fixture()
        let remaining = f.remaining()
        #expect(remaining.tabIDs == [f.a, f.c])
        #expect(remaining.widthFactors == [0.25, 0.75])
        #expect(remaining.orientation == .vertical)
    }

    @MainActor @Test func theSurvivingContainerKeepsItsNameAndAnchor() throws {
        let f = try Fixture()
        let remaining = f.remaining()
        #expect(remaining.customTitle == f.group.customTitle)
        #expect(remaining.sidebarAnchorID == f.a)
    }

    @MainActor @Test func separatingRecreatesNoPageRecordPlacementOrFolder() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        #expect(f.store.state.tabs == f.tabs)
        #expect(f.store.state.folders == f.folders)
    }

    @MainActor @Test func separatingIsNotACloseOrNavigation() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        #expect(f.store.state.recentlyClosedIDs == f.archive)
        #expect(f.store.state.history == f.history)
    }

    @MainActor @Test func theSeparatedFocusedOriginalIsNoLongerASplit() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        #expect(f.store.activeSplitLayout == nil)
    }

    @MainActor @Test func selectionAndContainerPersistTogether() throws {
        let f = try Fixture()
        let remaining = f.remaining()
        let loaded = try f.reopened()
        #expect(loaded.state.selectedTabIDs == [f.b])
        #expect(loaded.state.splitLayouts.contains(remaining))
    }

    @MainActor @Test func aStaleMembershipReceiptRefusesWithoutMutation() throws {
        let f = try Fixture()
        _ = f.remaining()
        let unchanged = f.store.state
        #expect(!f.store.separateTabFromSplit(f.c, expected: f.group, focusedID: f.b))
        #expect(f.store.state == unchanged)
    }

    @MainActor @Test func anUnselectedFocusCannotAuthorizeRetargeting() throws {
        let f = try Fixture()
        let remaining = f.remaining()
        let unchanged = f.store.state
        #expect(!f.store.separateTabFromSplit(f.c, expected: remaining, focusedID: UUID()))
        #expect(f.store.state == unchanged)
    }

    @MainActor @Test func aBackgroundOriginalGroupCanSeparate() throws {
        let f = try Fixture()
        let remaining = f.remaining()
        #expect(f.store.separateTabFromSplit(f.c, expected: remaining, focusedID: f.b))
    }

    @MainActor @Test func aBackgroundSeparationLeavesTheSelectionUnchanged() throws {
        let f = try Fixture()
        let remaining = f.remaining()
        _ = f.store.separateTabFromSplit(f.c, expected: remaining, focusedID: f.b)
        #expect(f.store.state.selectedTabIDs == [f.b])
        #expect(f.store.state.selectionBySpace[f.space.uuidString] == [f.b])
    }

    @MainActor @Test func aSingleChildContainerDissolvesWithoutDeletingTheOriginal() throws {
        let f = try Fixture()
        let remaining = f.remaining()
        _ = f.store.separateTabFromSplit(f.c, expected: remaining, focusedID: f.b)
        #expect(!f.store.state.splitLayouts.contains { $0.id == remaining.id })
        #expect(f.store.state.tabs == f.tabs)
    }

    @MainActor @Test func aNonfocusedDisplayedChildSeparates() throws {
        let f = try Fixture()
        #expect(f.store.separateTabFromSplit(f.c, expected: f.group, focusedID: f.a))
        #expect(f.store.state.selectedTabIDs == [f.a, f.b])
        #expect(f.store.state.selectionBySpace[f.space.uuidString] == [f.a, f.b])
    }

    @MainActor @Test func theOriginalAnchorSeparatesWithoutClosing() throws {
        let f = try Fixture()
        #expect(f.store.separateTabFromSplit(f.a, expected: f.group, focusedID: f.c))
        #expect(f.store.state.selectedTabIDs == [f.b, f.c])
    }

    @MainActor @Test func theRemainingOrderedChildBecomesTheAnchor() throws {
        let f = try Fixture()
        _ = f.store.separateTabFromSplit(f.a, expected: f.group, focusedID: f.c)
        #expect(f.store.activeSplitLayout?.sidebarAnchorID == f.b)
    }

    @MainActor @Test func aSeparatedOriginalStaysInItsSplitsTodayContainer() throws {
        let f = try Fixture()
        _ = f.store.separateTabFromSplit(f.a, expected: f.group, focusedID: f.c)
        #expect(f.store.state.tabs.first { $0.id == f.a }?.folderID == nil)
        #expect(f.store.state.tabs.first { $0.id == f.a }?.kind == .today)
    }

    @MainActor @Test func aSeparatedChildMovesDirectlyAfterItsSplit() throws {
        let f = try Fixture()
        _ = f.store.separateTabFromSplit(f.a, expected: f.group, focusedID: f.c)
        let order = SidebarHierarchy.children(in: .init(spaceID: f.space, folderID: nil, section: .today), state: f.store.state)
        #expect(order.firstIndex(of: .split(f.group.id)).map { $0 + 1 } == order.firstIndex(of: .tab(f.a)))
    }

    @MainActor private struct FolderSplit {
        let ids: [UUID]
        let box: SidebarContainerLocation
        let split: BrowserSplitLayout

        init(_ f: Fixture) throws {
            let ids = [f.store.open("https://four.invalid"), f.store.open("https://five.invalid"), f.store.open("https://six.invalid")]
            f.store.selectTab(ids[0])
            f.store.selectTab(ids[1], extendingSplit: true)
            f.store.selectTab(ids[2], extendingSplit: true)
            box = SidebarContainerLocation(spaceID: f.space, folderID: f.folder, section: .pinned)
            let snapshot = try #require(SidebarHierarchySnapshot(state: f.store.state, spaceID: f.space, profileID: f.profile))
            try #require(try f.store.moveSidebarItem(.split(f.store.activeSplitLayout!.id), to: box, before: nil, expected: snapshot))
            self.ids = ids
            split = f.store.activeSplitLayout!
        }
    }

    @MainActor @Test func aSplitMovesWholeIntoTheFolder() throws {
        let f = try Fixture()
        let s = try FolderSplit(f)
        #expect(SidebarHierarchy.children(in: s.box, state: f.store.state).contains(.split(s.split.id)))
    }

    @MainActor @Test func aPinnedFolderSplitSeparates() throws {
        let f = try Fixture()
        let s = try FolderSplit(f)
        #expect(f.store.separateTabFromSplit(s.ids[1], expected: s.split, focusedID: s.ids[0]))
    }

    @MainActor @Test func theSeparatedChildStaysPinnedInTheFolderRightAfterItsSplit() throws {
        let f = try Fixture()
        let s = try FolderSplit(f)
        _ = f.store.separateTabFromSplit(s.ids[1], expected: s.split, focusedID: s.ids[0])
        let order = SidebarHierarchy.children(in: s.box, state: f.store.state)
        let child = f.store.state.tabs.first { $0.id == s.ids[1] }
        #expect(child?.kind == .pinned)
        #expect(child?.folderID == f.folder)
        #expect(order.firstIndex(of: .split(s.split.id)).map { $0 + 1 } == order.firstIndex(of: .tab(s.ids[1])))
    }

    @MainActor @Test func aPrivateOriginalSplitUsesTheSameFocusContract() throws {
        let f = try Fixture()
        let privateDirectory = f.root.appendingPathComponent("must-not-exist")
        let privateStore = BrowserStore(privateParentProfileID: f.profile, engineProfilePath: "/not-opened", directory: privateDirectory, settings: f.store.state.settings)
        let pa = privateStore.open("https://private-one.invalid"), pb = privateStore.open("https://private-two.invalid")
        privateStore.setSplit([pa, pb])
        #expect(privateStore.separateSplitPane(pb))
        #expect(privateStore.state.selectedTabIDs == [pb])
    }

    @MainActor @Test func privateSeparationNeverPersists() throws {
        let f = try Fixture()
        let privateDirectory = f.root.appendingPathComponent("must-not-exist")
        let privateStore = BrowserStore(privateParentProfileID: f.profile, engineProfilePath: "/not-opened", directory: privateDirectory, settings: f.store.state.settings)
        let pa = privateStore.open("https://private-one.invalid"), pb = privateStore.open("https://private-two.invalid")
        privateStore.setSplit([pa, pb])
        _ = privateStore.separateSplitPane(pb)
        #expect(!FileManager.default.fileExists(atPath: privateDirectory.path))
    }

    @MainActor private final class LocalPages {
        let noteFile: URL
        let originalNote = Data("Shared\n".utf8)
        let easels: EaselStore
        let easel: EaselSession
        let originalEasel: EaselDocument
        let noteID: UUID, easelID: UUID
        let group: BrowserSplitLayout
        var closeRequests = 0

        init(_ f: Fixture) throws {
            noteFile = f.root.appendingPathComponent("Shared Note.md")
            try originalNote.write(to: noteFile)
            easels = try EaselStore(directory: f.root.appendingPathComponent("easels"))
            easel = try easels.create()
            noteID = f.store.openNote(url: noteFile, title: "Shared Note")!
            easelID = f.store.openEasel(id: easel.document.id, title: "Shared Easel")!
            originalEasel = easel.document
            f.store.setSplit([f.a, noteID, easelID])
            group = f.store.activeSplitLayout!
            f.store.requestPageRetirement = { [unowned self] _, _, _ in closeRequests += 1 }
        }
    }

    @MainActor @Test func anOriginalLocalNoteSeparatesThroughTheSameTransaction() throws {
        let f = try Fixture()
        let p = try LocalPages(f)
        #expect(f.store.separateTabFromSplit(p.noteID, expected: p.group, focusedID: p.noteID))
    }

    @MainActor @Test func localSeparationNeverRequestsRetirementOrConsent() throws {
        let f = try Fixture()
        let p = try LocalPages(f)
        _ = f.store.separateTabFromSplit(p.noteID, expected: p.group, focusedID: p.noteID)
        #expect(f.store.state.selectedTabIDs == [p.noteID])
        #expect(p.closeRequests == 0)
    }

    @MainActor @Test func theSharedLocalSessionsAreNotReplaced() throws {
        let f = try Fixture()
        let p = try LocalPages(f)
        _ = f.store.separateTabFromSplit(p.noteID, expected: p.group, focusedID: p.noteID)
        #expect(try p.easels.load(p.easel.document.id) === p.easel)
    }

    @MainActor @Test func sharedDocumentContentAndAssetIdentityStayUnchanged() throws {
        let f = try Fixture()
        let p = try LocalPages(f)
        _ = f.store.separateTabFromSplit(p.noteID, expected: p.group, focusedID: p.noteID)
        #expect(try Data(contentsOf: p.noteFile) == p.originalNote)
        #expect(p.easel.document == p.originalEasel)
    }

    @MainActor @Test func theSurvivingEmbeddedPageOwnerKeepsTheOriginalEaselReference() throws {
        let f = try Fixture()
        let p = try LocalPages(f)
        _ = f.store.separateTabFromSplit(p.noteID, expected: p.group, focusedID: p.noteID)
        #expect(f.store.state.tabs.first { $0.id == p.easelID }?.url == InternalPage.easel(p.easel.document.id).urlString)
    }

    @MainActor private func failing(_ f: Fixture) throws -> (layout: BrowserSplitLayout, state: BrowserState) {
        let layout = try #require(f.store.activeSplitLayout)
        let state = f.store.state
        try f.store.save()
        try FileManager.default.removeItem(at: f.root)
        try Data().write(to: f.root)
        return (layout, state)
    }

    @MainActor @Test func aFailedDurableCommitRefusesSeparation() throws {
        let f = try Fixture()
        let broken = try failing(f)
        #expect(!f.store.separateTabFromSplit(f.b, expected: broken.layout, focusedID: f.b))
    }

    @MainActor @Test func aFailedSaveKeepsSelectionGroupAndRecords() throws {
        let f = try Fixture()
        let broken = try failing(f)
        _ = f.store.separateTabFromSplit(f.b, expected: broken.layout, focusedID: f.b)
        #expect(f.store.state == broken.state)
        #expect(f.store.persistenceError != nil)
    }

    @MainActor @Test func theSameReceiptRetriesAfterStorageRecoversAndPublishesFocusOnce() throws {
        let f = try Fixture()
        let broken = try failing(f)
        _ = f.store.separateTabFromSplit(f.b, expected: broken.layout, focusedID: f.b)
        try FileManager.default.removeItem(at: f.root)
        try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
        #expect(f.store.separateTabFromSplit(f.b, expected: broken.layout, focusedID: f.b))
        #expect(f.store.state.selectedTabIDs == [f.b])
        #expect(f.store.persistenceError == nil)
    }
}
