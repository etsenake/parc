import Foundation
import Testing
@testable import ParcCore

struct SplitPaneControlsTests {
    @MainActor private final class Fixture {
        let root: URL
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store: BrowserStore
        let saved: UUID, folder: UUID
        let a: UUID, b: UUID, c: UUID
        let original: BrowserSplitLayout
        let tabs: [BrowserTab]
        let archive: [UUID]
        let url = URL(string: "https://four.invalid/post-result")!

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-pane-controls-" + UUID().uuidString)
            let now = now
            let store = try BrowserStore(directory: root, now: { now })
            let saved = store.open("https://one.invalid", kind: .pinned)
            let folder = store.createFolder(name: "Original parent")
            store.moveTab(saved, toSpace: store.activeSpaceID, folderID: folder)
            let a = store.open("https://one.invalid/today")
            let b = store.open("https://two.invalid"), c = store.open("https://three.invalid")
            store.setSplit([a, b, c])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            self.store = store
            self.saved = saved; self.folder = folder
            self.a = a; self.b = b; self.c = c
            original = store.activeSplitLayout!
            tabs = store.state.tabs
            archive = store.state.recentlyClosedIDs
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func moved() -> BrowserSplitLayout {
            _ = store.moveSplitPane(b, offset: 1, expected: original)
            return store.activeSplitLayout!
        }

        func creation() -> TabCreationProvenance {
            TabCreationProvenance(referrerID: nil, activeTabID: b, profileID: store.activeSpace.profileID, state: store.state)
        }

        func insertFour(operation: SplitPaneOperation = .addAbove) throws -> (id: UUID, draft: SplitPaneInsertion) {
            let draft = try #require(SplitPaneInsertion(paneID: b, operation: operation, state: store.state))
            let id = UUID()
            _ = store.insertSplitPane(draft, tabID: id, navigationURL: url, creation: creation(), savedHomeIDs: [:], documents: [:])
            return (id, draft)
        }

        func insertPinned() throws -> (home: UUID, newID: UUID) {
            store.selectTab(saved)
            let draft = try #require(SplitPaneInsertion(paneID: saved, operation: .addAfter, state: store.state))
            let newID = UUID(), home = UUID()
            _ = store.insertSplitPane(draft, tabID: newID, navigationURL: url, creation: nil, savedHomeIDs: [saved: home], documents: [:])
            return (home, newID)
        }

        func breakStorage() throws {
            try FileManager.default.removeItem(at: root)
            try Data().write(to: root)
        }

        func restoreStorage() throws {
            try FileManager.default.removeItem(at: root)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    @MainActor @Test func theFirstPaneCannotMoveBeforeTheStart() throws {
        let f = try Fixture()
        #expect(!f.store.moveSplitPane(f.a, offset: -1, expected: f.original))
    }

    @MainActor @Test func theLastPaneCannotMoveAfterTheEnd() throws {
        let f = try Fixture()
        #expect(!f.store.moveSplitPane(f.c, offset: 1, expected: f.original))
    }

    @MainActor @Test func anUntrustedOffsetRefusesWithoutOverflow() throws {
        let f = try Fixture()
        #expect(!f.store.moveSplitPane(f.a, offset: Int.min, expected: f.original))
    }

    @MainActor @Test func anOriginalPaneMovesDown() throws {
        let f = try Fixture()
        #expect(f.store.moveSplitPane(f.b, offset: 1, expected: f.original))
    }

    @MainActor @Test func movingKeepsTheGroupAndReordersPageIDs() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(moved.tabIDs == [f.a, f.c, f.b])
        #expect(moved.id == f.original.id)
    }

    @MainActor @Test func paneProportionsMoveWithTheirContent() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(moved.widthFactors == [f.original.widthFactors[0], f.original.widthFactors[2], f.original.widthFactors[1]])
    }

    @MainActor @Test func movingPreservesOrientationAndAnchor() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(moved.orientation == .vertical)
        #expect(moved.sidebarAnchorID == f.original.sidebarAnchorID)
    }

    @MainActor @Test func movingDoesNotRecreatePagesOrCloseOriginals() throws {
        let f = try Fixture()
        _ = f.moved()
        #expect(f.store.state.tabs == f.tabs)
        #expect(f.store.state.recentlyClosedIDs == f.archive)
    }

    @MainActor @Test func orderAndWindowSelectionPublishTogether() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(f.store.state.selectedTabIDs == moved.tabIDs)
        #expect(f.store.state.selectionBySpace[f.store.activeSpaceID.uuidString] == moved.tabIDs)
    }

    @MainActor @Test func aMoveIsDurablyRestored() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(try BrowserStore(directory: f.root).activeSplitLayout == moved)
    }

    @MainActor @Test func aStaleMenuReceiptRefuses() throws {
        let f = try Fixture()
        _ = f.moved()
        let unchanged = f.store.state
        #expect(!f.store.moveSplitPane(f.b, offset: -1, expected: f.original))
        #expect(f.store.state == unchanged)
    }

    @MainActor @Test func theInverseMoveRestoresTheOriginalMetadataAndRatios() throws {
        let f = try Fixture()
        let moved = f.moved()
        #expect(f.store.moveSplitPane(f.b, offset: -1, expected: moved))
        #expect(f.store.activeSplitLayout == f.original)
    }

    @Test func theFirstPaneCannotMovePreviousButCanMoveNext() {
        #expect(!SplitPaneOperation.movePrevious.isEnabled(index: 0, count: 3))
        #expect(SplitPaneOperation.moveNext.isEnabled(index: 0, count: 3))
    }

    @Test func addIsUnavailableAtFourPanes() {
        #expect(!SplitPaneOperation.addAfter.isEnabled(index: 0, count: 4))
    }

    @Test func aSolePaneCannotBeSeparated() {
        #expect(!SplitPaneOperation.separate.isEnabled(index: 0, count: 1))
    }

    @Test func copyLinksNeedsAPopulatedSplit() {
        #expect(SplitPaneOperation.copyLinks.isEnabled(index: 0, count: 2))
        #expect(!SplitPaneOperation.copyLinks.isEnabled(index: 0, count: 1))
    }

    @MainActor @Test func aTopInsertionDraftTargetsTheExactPane() throws {
        let f = try Fixture()
        let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state))
        #expect(draft.index == 1)
        #expect(draft.orientation == .vertical)
        #expect(draft.selection == [f.a, f.b, f.c])
    }

    @MainActor @Test func temporaryGeometryStaysNormalized() throws {
        let f = try Fixture()
        let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state))
        #expect(draft.previewFactors.count == 4)
        #expect(abs(draft.previewFactors.reduce(0, +) - 1) < 0.00001)
    }

    @MainActor @Test func thePendingPaneReceivesOneOverTheNewPaneCount() throws {
        let f = try Fixture()
        let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state))
        #expect(abs(draft.previewFactors[1] - 0.25) < 0.00001)
    }

    @MainActor @Test func existingPanesKeepTheirRelativeFactors() throws {
        let f = try Fixture()
        let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state))
        let previous = try #require(f.store.activeSplitLayout).widthFactors, pending = draft.previewFactors
        #expect(zip(previous, [pending[0], pending[2], pending[3]]).allSatisfy { abs($0 * 0.75 - $1) < 0.00001 })
    }

    @MainActor @Test func draftingNeverPersistsAPlaceholder() throws {
        let f = try Fixture()
        let before = f.store.state
        _ = SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state)
        #expect(f.store.state == before)
    }

    @MainActor @Test func anAcceptedNavigationInsertsOneRecordAtomically() throws {
        let f = try Fixture()
        let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state))
        #expect(f.store.insertSplitPane(draft, tabID: UUID(), navigationURL: f.url, creation: f.creation(), savedHomeIDs: [:], documents: [:]))
    }

    @MainActor @Test func theNewPaneUsesTheRequestedSlotInTheOriginalContainer() throws {
        let f = try Fixture()
        let inserted = try f.insertFour()
        #expect(f.store.state.selectedTabIDs == [f.a, inserted.id, f.b, f.c])
        #expect(f.store.activeSplitLayout?.id == f.original.id)
    }

    @MainActor @Test func theInsertedTabKeepsItsDestinationAndCreationSource() throws {
        let f = try Fixture()
        let inserted = try f.insertFour()
        let created = try #require(f.store.state.tabs.first { $0.id == inserted.id })
        #expect(created.url == f.url.absoluteString)
        #expect(created.kind == .today)
        #expect(created.activeTabBeforeCreationID == f.b)
    }

    @MainActor @Test func existingPagesKeepTheirExactIdentity() throws {
        let f = try Fixture()
        _ = try f.insertFour()
        #expect(f.tabs.allSatisfy { f.store.state.tabs.contains($0) })
    }

    @MainActor @Test func aFifthPaneCannotBeDrafted() throws {
        let f = try Fixture()
        let inserted = try f.insertFour()
        #expect(SplitPaneInsertion(paneID: inserted.id, operation: .addAfter, state: f.store.state) == nil)
    }

    @MainActor @Test func anAdmittedDraftCannotReplayAfterMembershipChanged() throws {
        let f = try Fixture()
        let inserted = try f.insertFour()
        let full = f.store.state
        #expect(!f.store.insertSplitPane(inserted.draft, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:]))
        #expect(f.store.state == full)
    }

    @MainActor @Test func theAcceptedPaneAndGroupPersistTogether() throws {
        let f = try Fixture()
        let inserted = try f.insertFour()
        #expect(try BrowserStore(directory: f.root).state.selectedTabIDs == [f.a, inserted.id, f.b, f.c])
    }

    @MainActor @Test func mainAddSupportsASingleOriginalContent() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let single = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAfter, state: f.store.state))
        #expect(single.selection.count == 1)
        #expect(single.index == 1)
    }

    @MainActor private struct LocalNote {
        let file: URL
        let id: UUID
        let old: BrowserTab

        init(_ f: Fixture) throws {
            file = f.root.appendingPathComponent("Shared Note.md")
            let id = f.store.openNote(url: file, title: "Shared Note")!
            f.store.selectTab(f.b)
            self.id = id
            old = f.store.state.tabs.first { $0.id == id }!
        }

        func join(_ f: Fixture) throws -> Bool {
            let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addBelow, state: f.store.state))
            return f.store.insertSplitPane(draft, tabID: id, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:])
        }
    }

    @MainActor @Test func anExistingLocalNoteCanFillABlankPane() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let note = try LocalNote(f)
        #expect(try note.join(f))
    }

    @MainActor @Test func theLocalNoteRecordIsMovedNeverCloned() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let note = try LocalNote(f)
        _ = try note.join(f)
        #expect(f.store.state.tabs.first { $0.id == note.id }?.url == note.old.url)
        #expect(f.store.state.selectedTabIDs == [f.b, note.id])
    }

    @MainActor @Test func aTodayNoteLeavesNoSavedHome() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let note = try LocalNote(f)
        _ = try note.join(f)
        #expect(f.store.state.tabs.filter { InternalPage(urlString: $0.url) == .note(note.file) }.count == 1)
    }

    @MainActor @Test func separatingTheNoteRestoresTheOriginalFirstPane() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let note = try LocalNote(f)
        _ = try note.join(f)
        #expect(f.store.separateTabFromSplit(note.id, expected: f.store.activeSplitLayout!, focusedID: f.b))
        #expect(f.store.state.selectedTabIDs == [f.b])
    }

    @MainActor private struct LocalEasel {
        let easels: EaselStore
        let easel: EaselSession
        let id: UUID
        let old: BrowserTab

        init(_ f: Fixture) throws {
            easels = try EaselStore(directory: f.root.appendingPathComponent("easels"))
            easel = try easels.create()
            let id = f.store.openEasel(id: easel.document.id, title: "Shared Easel")!
            f.store.selectTab(f.b)
            self.id = id
            old = f.store.state.tabs.first { $0.id == id }!
        }

        func join(_ f: Fixture) throws -> Bool {
            let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAfter, state: f.store.state))
            return f.store.insertSplitPane(draft, tabID: id, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:])
        }
    }

    @MainActor @Test func anExistingLocalEaselCanFillABlankPane() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let easel = try LocalEasel(f)
        #expect(try easel.join(f))
    }

    @MainActor @Test func theLocalEaselRecordIsMovedNeverCloned() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let easel = try LocalEasel(f)
        _ = try easel.join(f)
        #expect(f.store.state.tabs.first { $0.id == easel.id }?.url == easel.old.url)
        #expect(f.store.state.selectedTabIDs == [f.b, easel.id])
    }

    @MainActor @Test func aTodayEaselLeavesNoSavedHome() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let easel = try LocalEasel(f)
        _ = try easel.join(f)
        #expect(f.store.state.tabs.filter { InternalPage(urlString: $0.url)?.easelID == easel.easel.document.id }.count == 1)
    }

    @MainActor @Test func theSharedEaselSessionRemainsTheOriginal() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let easel = try LocalEasel(f)
        _ = try easel.join(f)
        #expect(try easel.easels.load(easel.easel.document.id) === easel.easel)
    }

    @MainActor private struct Host {
        let id: UUID
        let createdNote: URL
        let draft: SplitPaneInsertion

        init(_ f: Fixture, operation: SplitPaneOperation) throws {
            id = f.store.open("https://later.invalid/host")
            f.store.selectTab(id)
            createdNote = f.root.appendingPathComponent("Untitled.md")
            draft = try #require(SplitPaneInsertion(paneID: id, operation: operation, state: f.store.state))
        }

        func insertNote(_ f: Fixture, tabID: UUID = UUID(), navigation: URL? = nil) -> Bool {
            f.store.insertSplitPane(draft, tabID: tabID, navigationURL: navigation, creation: nil, savedHomeIDs: [:], documents: [:],
                localPage: .note(createdNote), localTitle: "Untitled")
        }
    }

    @MainActor @Test func addLeftDraftsTheFirstSlot() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addBefore)
        #expect(host.draft.index == 0)
        #expect(host.draft.orientation == .horizontal)
        #expect(host.draft.selection == [host.id])
    }

    @MainActor @Test func aLocalPageAndANavigationURLCannotMaterializeTogether() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addBefore)
        let before = f.store.state
        #expect(!host.insertNote(f, navigation: f.url))
        #expect(f.store.state == before)
    }

    @MainActor @Test func aNewNoteOccupiesTheDraftedSlot() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addBefore)
        let tab = UUID()
        #expect(host.insertNote(f, tabID: tab))
        #expect(f.store.state.selectedTabIDs == [tab, host.id])
        #expect(f.store.activeSplitLayout?.orientation == .horizontal)
    }

    @MainActor @Test func theNewNoteTabAddressesTheCreatedDocumentWithoutASavedHome() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addBefore)
        let tab = UUID()
        _ = host.insertNote(f, tabID: tab)
        #expect(f.store.state.tabs.first { $0.id == tab }?.url == InternalPage.note(host.createdNote).urlString)
        #expect(f.store.state.tabs.filter { InternalPage(urlString: $0.url) == .note(host.createdNote) }.count == 1)
    }

    @MainActor @Test func separatingTheNewNoteRestoresTheOriginalHost() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addBefore)
        let tab = UUID()
        _ = host.insertNote(f, tabID: tab)
        #expect(f.store.separateTabFromSplit(tab, expected: f.store.activeSplitLayout!, focusedID: host.id))
        #expect(f.store.state.selectedTabIDs == [host.id])
    }

    @MainActor @Test func theSameNewNoteDocumentCannotOpenASecondTab() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addAbove)
        _ = host.insertNote(f)
        let before = f.store.state
        #expect(!host.insertNote(f))
        #expect(f.store.state == before)
    }

    @MainActor @Test func aNewEaselOccupiesTheDraftedTopSlot() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addAbove)
        let easels = try EaselStore(directory: f.root.appendingPathComponent("easels"))
        let created = try easels.create()
        let tab = UUID()
        #expect(host.draft.index == 0)
        #expect(host.draft.orientation == .vertical)
        #expect(host.draft.selection == [host.id])
        #expect(f.store.insertSplitPane(host.draft, tabID: tab, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:],
            localPage: .easel(created.document.id), localTitle: created.document.title))
        #expect(f.store.state.selectedTabIDs == [tab, host.id])
        #expect(f.store.activeSplitLayout?.orientation == .vertical)
    }

    @MainActor @Test func aSavedOriginalNeedsARealSavedHomeReceipt() throws {
        let f = try Fixture()
        f.store.selectTab(f.saved)
        let pinned = try #require(SplitPaneInsertion(paneID: f.saved, operation: .addAfter, state: f.store.state))
        #expect(!f.store.insertSplitPane(pinned, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:]))
    }

    @MainActor @Test func aMissingHomeLeaksNoPartialTab() throws {
        let f = try Fixture()
        f.store.selectTab(f.saved)
        let pinned = try #require(SplitPaneInsertion(paneID: f.saved, operation: .addAfter, state: f.store.state))
        let before = f.store.state
        _ = f.store.insertSplitPane(pinned, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:])
        #expect(f.store.state == before)
    }

    @MainActor @Test func aPinnedOriginalMovesWithAFreshSavedHome() throws {
        let f = try Fixture()
        f.store.selectTab(f.saved)
        let pinned = try #require(SplitPaneInsertion(paneID: f.saved, operation: .addAfter, state: f.store.state))
        #expect(f.store.insertSplitPane(pinned, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [f.saved: UUID()], documents: [:]))
    }

    @MainActor @Test func theSavedHomeKeepsTheExactParentSection() throws {
        let f = try Fixture()
        let inserted = try f.insertPinned()
        let home = f.store.state.tabs.first { $0.id == inserted.home }
        #expect(home?.folderID == f.folder)
        #expect(home?.kind == .pinned)
    }

    @MainActor @Test func theLiveOriginalBecomesThePaneAndTheHomeNeverReplacesItsPage() throws {
        let f = try Fixture()
        let inserted = try f.insertPinned()
        #expect(f.store.state.tabs.first { $0.id == f.saved }?.kind == .today)
        #expect(f.store.state.selectedTabIDs == [f.saved, inserted.newID])
    }

    @MainActor private func pendingDraft(_ f: Fixture) throws -> SplitPaneInsertion {
        _ = try f.insertPinned()
        return try #require(SplitPaneInsertion(paneID: f.saved, operation: .addBelow, state: f.store.state))
    }

    @MainActor @Test func aDestinationProfileChangeInvalidatesTheDraft() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        var foreign = f.store.state
        foreign.spaces[0].profileID = UUID()
        #expect(!pending.isCurrent(in: foreign))
    }

    @MainActor @Test func aRemovedProfileInvalidatesTheDraft() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        var removed = f.store.state
        removed.profiles.removeAll { $0.id == pending.profileID }
        #expect(!pending.isCurrent(in: removed))
    }

    @MainActor @Test func aRetiredOriginalInvalidatesTheDraft() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        var archived = f.store.state
        archived.tabs[archived.tabs.firstIndex { $0.id == f.saved }!].archivedAt = f.now
        #expect(!pending.isCurrent(in: archived))
    }

    @MainActor @Test func changedGroupGeometryInvalidatesTheDraft() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        var changed = f.store.state
        changed.splitLayouts[changed.splitLayouts.firstIndex { $0.id == pending.layout?.id }!].widthFactors = [0.75, 0.25]
        #expect(!pending.isCurrent(in: changed))
    }

    @MainActor @Test func aStorageFailureRefusesPaneMaterialization() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        try f.breakStorage()
        #expect(!f.store.insertSplitPane(pending, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:]))
    }

    @MainActor @Test func aFailedSaveLeavesOriginalsAndNoOrphanTab() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        let failureState = f.store.state
        try f.breakStorage()
        _ = f.store.insertSplitPane(pending, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:])
        #expect(f.store.state == failureState)
        #expect(f.store.persistenceError != nil)
    }

    @MainActor @Test func aStorageFailureAlsoRefusesAReorder() throws {
        let f = try Fixture()
        _ = try pendingDraft(f)
        let failureState = f.store.state
        try f.breakStorage()
        #expect(!f.store.moveSplitPane(f.saved, offset: 1, expected: f.store.activeSplitLayout!))
        #expect(f.store.state == failureState)
    }

    @MainActor @Test func theSameReceiptRetriesAfterStorageRecovers() throws {
        let f = try Fixture()
        let pending = try pendingDraft(f)
        let failureID = UUID()
        try f.breakStorage()
        _ = f.store.insertSplitPane(pending, tabID: failureID, navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:])
        try f.restoreStorage()
        #expect(f.store.insertSplitPane(pending, tabID: failureID, navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:]))
        #expect(f.store.persistenceError == nil)
    }

    @MainActor private struct Links {
        let space: UUID, profile: UUID
        let note: UUID, easel: UUID, settings: UUID, blank: UUID

        init(_ f: Fixture) {
            space = f.store.activeSpaceID
            profile = f.store.activeSpace.profileID
            note = f.store.openResolvedURL(URL(string: InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).urlString)!)
            easel = f.store.openResolvedURL(URL(string: InternalPage.easel(UUID()).urlString)!)
            settings = f.store.openResolvedURL(URL(string: "parc://settings/")!)
            blank = f.store.openResolvedURL(URL(string: "about:blank")!)
        }
    }

    @MainActor @Test func copyLinksCopiesEveryPagesAddressInPaneOrder() throws {
        let f = try Fixture()
        let l = Links(f)
        #expect(FolderLinks.links(in: f.store.state, tabIDs: [f.c, f.a, f.b], spaceID: l.space, profileID: l.profile).map(\.tabID) == [f.c, f.a, f.b])
    }

    @MainActor @Test func notesCopyTheirFileWhileEaselsParcPagesAndBlankTabsAreSkippedAndPagesCopyOnce() throws {
        let f = try Fixture()
        let l = Links(f)
        let links = FolderLinks.links(in: f.store.state, tabIDs: [l.note, f.b, l.settings, l.easel, f.a, l.blank, f.b], spaceID: l.space, profileID: l.profile)
        #expect(links.map(\.tabID) == [l.note, f.b, f.a])
    }

    @MainActor @Test func aSplitWithoutAWebPageHasNothingToCopy() throws {
        let f = try Fixture()
        let l = Links(f)
        #expect(FolderLinks.links(in: f.store.state, tabIDs: [l.easel, l.settings], spaceID: l.space, profileID: l.profile).isEmpty)
    }

    @MainActor @Test func anotherProfilesPagesAreNeverCopied() throws {
        let f = try Fixture()
        let l = Links(f)
        #expect(FolderLinks.links(in: f.store.state, tabIDs: [f.a, f.b], spaceID: l.space, profileID: UUID()).isEmpty)
    }
}
