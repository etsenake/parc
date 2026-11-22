import AppKit
import Combine
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct TabTitleUndoTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-tab-title-undo-" + UUID().uuidString)
        let store: BrowserStore
        let id: UUID
        let profile: UUID
        let owner = FolderUndoManager()
        let otherWindow = FolderUndoManager()
        var available = true
        var errors = 0
        var publications = 0
        var finishRetirement: ((Bool) -> Void)?
        var observation: AnyCancellable?

        init() throws {
            store = try BrowserStore(directory: directory)
            id = store.openResolvedURL(URL(string: "https://original.test/anchor")!)
            store.updateTab(id, title: "Original page")
            profile = store.activeSpace.profileID
            observation = store.statePublisher.dropFirst().sink { [unowned self] _ in publications += 1 }
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var tab: BrowserTab { store.state.tabs.first { $0.id == id }! }

        @discardableResult func record(_ title: String, in manager: FolderUndoManager? = nil) throws -> SidebarTabTitleChange? {
            let manager = manager ?? owner
            guard let change = try store.saveSidebarTitle(tab, title: title) else { return nil }
            let appended = manager.appendTabTitleChange(change, store: store, available: { [self] in available }, onError: { [self] _ in errors += 1 })
            try #require(appended)
            return change
        }

        @discardableResult func recorded(_ title: String = "Research") throws -> SidebarTabTitleChange {
            try #require(try record(title))
        }

        func breakDirectory() throws {
            try FileManager.default.removeItem(at: directory)
            try Data().write(to: directory)
        }

        func repairDirectory() throws {
            try FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func privateStore() -> (store: BrowserStore, path: URL) {
            let path = directory.appendingPathComponent("never-created")
            return (BrowserStore(privateParentProfileID: profile, engineProfilePath: "/not-opened", directory: path,
                                 settings: store.state.settings), path)
        }
    }

    @MainActor private final class PrivateTab {
        let fixture: Fixture
        let store: BrowserStore
        let path: URL
        let change: SidebarTabTitleChange
        let undo = FolderUndoManager()

        init() throws {
            fixture = try Fixture()
            (store, path) = fixture.privateStore()
            let id = store.openResolvedURL(URL(string: "https://private.test")!)
            let tab = try #require(store.state.tabs.first { $0.id == id })
            change = try #require(try store.saveSidebarTitle(tab, title: "Private"))
            let appended = undo.appendTabTitleChange(change, store: store, available: { true }, onError: { _ in })
            try #require(appended)
        }
    }

    @Test func aCommittedChangeCapturesTheOriginalIdentityProfileAndTrimmedTitle() throws {
        let fixture = try Fixture()
        let change = try fixture.recorded("  Research\n")
        #expect(change.tabID == fixture.id)
        #expect(change.profileID == fixture.profile)
        #expect(change.previousTitle == nil)
        #expect(change.title == "Research")
    }

    @Test func theNativeActionNameAndChronologyArePerWindow() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        #expect(fixture.owner.undoMenuItemTitle == "Undo Rename Item")
        #expect(!fixture.otherWindow.canUndo)
    }

    @Test func windowContextLossBlocksACapturedCommand() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        let pending = try #require(fixture.owner.command(.undo))
        fixture.available = false
        #expect(!fixture.owner.canPerform(pending))
        #expect(!fixture.owner.canUndo)
    }

    @Test func temporaryContextLossDoesNotDiscardTheInverse() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        let pending = try #require(fixture.owner.command(.undo))
        fixture.available = false
        fixture.available = true
        #expect(fixture.owner.canPerform(pending))
    }

    @Test func undoRevealsTheActualCurrentFallback() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.store.updateTab(fixture.id, title: "New live title", url: "https://original.test/next")
        fixture.owner.undo()
        #expect(fixture.tab.customTitle == nil)
        #expect(SidebarTabTitle.display(fixture.tab) == "New live title")
    }

    @Test func undoChangesOnlyTheManualTitle() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.store.updateTab(fixture.id, title: "New live title", url: "https://original.test/next")
        var expected = fixture.store.state
        expected.tabs[expected.tabs.firstIndex { $0.id == fixture.id }!].customTitle = nil
        fixture.owner.undo()
        #expect(fixture.store.state == expected)
    }

    @Test func theDurableInversePublishesExactlyOnce() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        let before = fixture.publications
        fixture.owner.undo()
        #expect(fixture.publications == before + 1)
    }

    @Test func theMenuRevisionFollowsASuccessfulCommit() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        let pending = try #require(fixture.owner.command(.undo))
        fixture.owner.undo()
        #expect(fixture.owner.redoMenuItemTitle == "Redo Rename Item")
        #expect(!fixture.owner.canPerform(pending))
    }

    @Test func redoReappliesTheOriginalManualName() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.owner.undo()
        fixture.owner.redo()
        #expect(fixture.tab.customTitle == "Research")
    }

    @Test func theNameInverseIsDurable() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.owner.undo()
        fixture.owner.redo()
        #expect(try BrowserStore(directory: fixture.directory).state.tabs.first { $0.id == fixture.id }?.customTitle == "Research")
    }

    @Test func consecutiveChangesUndoInOrder() throws {
        let fixture = try Fixture()
        try fixture.recorded("Research")
        try fixture.recorded("Planning")
        fixture.owner.undo()
        #expect(fixture.tab.customTitle == "Research")
        fixture.owner.undo()
        #expect(fixture.tab.customTitle == nil)
    }

    @Test func consecutiveChangesRedoInOrder() throws {
        let fixture = try Fixture()
        try fixture.recorded("Research")
        try fixture.recorded("Planning")
        fixture.owner.undo()
        fixture.owner.undo()
        fixture.owner.redo()
        #expect(fixture.tab.customTitle == "Research")
        fixture.owner.redo()
        #expect(fixture.tab.customTitle == "Planning")
    }

    @Test func anEmptyEditRemovesOnlyTheCustomOverride() throws {
        let fixture = try Fixture()
        try fixture.recorded("Planning")
        try fixture.recorded(" \n")
        #expect(fixture.tab.customTitle == nil)
        #expect(fixture.tab.title == "Original page")
    }

    @Test func undoingAClearRestoresThePreviousOptionalName() throws {
        let fixture = try Fixture()
        try fixture.recorded("Planning")
        try fixture.recorded(" \n")
        fixture.owner.undo()
        #expect(fixture.tab.customTitle == "Planning")
    }

    @Test func anEqualEditPreservesRedo() throws {
        let fixture = try Fixture()
        try fixture.recorded("Planning")
        fixture.owner.undo()
        #expect(try fixture.record("") == nil)
        #expect(fixture.owner.canRedo)
    }

    @Test func aCompetingSharedRenameInvalidatesTheStaleInverse() throws {
        let fixture = try Fixture()
        try fixture.recorded("Planning")
        fixture.owner.undo()
        try fixture.record("Other window", in: fixture.otherWindow)
        #expect(!fixture.owner.canRedo)
        #expect(fixture.otherWindow.canUndo)
    }

    @Test func aSharedObserverSeesTheInverseWithoutResurrectingDiscardedHistory() throws {
        let fixture = try Fixture()
        try fixture.recorded("Planning")
        fixture.owner.undo()
        try fixture.record("Other window", in: fixture.otherWindow)
        #expect(!fixture.owner.canRedo)
        fixture.otherWindow.undo()
        #expect(fixture.tab.customTitle == nil)
        #expect(!fixture.owner.canRedo)
    }

    @Test func theInverseFollowsTheOriginalIDAfterAPinAndSameProfileMove() throws {
        let fixture = try Fixture()
        try fixture.recorded("Saved name")
        fixture.store.setKind(fixture.id, .pinned)
        let destination = fixture.store.createSpace(name: "Destination")
        fixture.store.moveTab(fixture.id, toSpace: destination)
        fixture.owner.undo()
        #expect(fixture.tab.customTitle == nil)
        #expect(fixture.tab.kind == .pinned)
        #expect(fixture.tab.spaceID == destination)
    }

    @Test func aPinnedSavedDestinationAndTheLivePageStayIndependent() throws {
        let fixture = try Fixture()
        try fixture.recorded("Saved name")
        fixture.store.setKind(fixture.id, .pinned)
        let savedURL = fixture.tab.savedURL, savedTitle = fixture.tab.savedTitle
        fixture.store.updateTab(fixture.id, title: "Away title", url: "https://original.test/away")
        fixture.owner.undo()
        #expect(fixture.tab.savedURL == savedURL)
        #expect(fixture.tab.savedTitle == savedTitle)
        #expect(fixture.tab.url == "https://original.test/away")
    }

    @Test func aPriorInverseSurvivesFavoriteMembership() throws {
        let fixture = try Fixture()
        try fixture.recorded("Saved name")
        fixture.store.setKind(fixture.id, .favorite)
        fixture.owner.undo()
        #expect(fixture.tab.kind == .favorite)
        #expect(fixture.tab.customTitle == nil)
    }

    @Test func containerAndChildNameChangesShareChronologyWithoutSubstitutingIdentities() throws {
        let fixture = try Fixture()
        fixture.store.setKind(fixture.id, .pinned)
        let sibling = fixture.store.openResolvedURL(URL(string: "https://sibling.test")!)
        fixture.store.setKind(sibling, .pinned)
        fixture.store.setSplit([fixture.id, sibling])
        try fixture.recorded("Saved name")
        let group = try #require(fixture.store.state.splitLayouts.first { $0.tabIDs.contains(fixture.id) })
        let edit = try #require(SidebarSplitTitleEdit(group: group, profileID: fixture.profile, state: fixture.store.state))
        let change = try #require(try fixture.store.saveSidebarSplitTitle(edit, title: "Group"))
        _ = fixture.owner.appendSplitTitleChange(change, store: fixture.store, available: { true }, onError: { _ in })
        fixture.owner.undo()
        fixture.owner.undo()
        #expect(fixture.store.state.splitLayouts.first?.customTitle == nil)
        #expect(fixture.tab.customTitle == nil)
        fixture.owner.redo()
        fixture.owner.redo()
        #expect(fixture.store.state.splitLayouts.first?.customTitle == "Group")
        #expect(fixture.tab.customTitle == "Saved name")
    }

    @Test func aNativeRetirementReservationBlocksTheInverse() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.store.requestPageRetirement = { [fixture] _, _, completion in fixture.finishRetirement = completion }
        fixture.store.closeTab(fixture.id)
        #expect(!fixture.owner.canUndo)
    }

    @Test func aRefusedBeforeUnloadRestoresTheInverse() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.store.requestPageRetirement = { [fixture] _, _, completion in fixture.finishRetirement = completion }
        fixture.store.closeTab(fixture.id)
        fixture.finishRetirement?(false)
        #expect(fixture.owner.canUndo)
    }

    @Test func anActualWriteFailureRetainsSharedStateAndARetryableStack() throws {
        let fixture = try Fixture()
        try fixture.recorded("Saved name")
        let before = fixture.store.state
        try fixture.breakDirectory()
        fixture.owner.undo()
        #expect(fixture.store.state == before)
        #expect(fixture.errors == 1)
        #expect(fixture.owner.canUndo)
        #expect(!fixture.owner.canRedo)
    }

    @Test func aRetryPublishesTheOriginalInverse() throws {
        let fixture = try Fixture()
        try fixture.recorded("Saved name")
        try fixture.breakDirectory()
        fixture.owner.undo()
        try fixture.repairDirectory()
        fixture.owner.undo()
        #expect(fixture.tab.customTitle == nil)
        #expect(fixture.owner.canRedo)
    }

    @Test func anArchivedOriginalCannotBeRenamedOrReopenedByTheInverse() throws {
        let fixture = try Fixture()
        try fixture.recorded("Saved name")
        fixture.owner.undo()
        let redoCommand = try #require(fixture.owner.command(.redo))
        fixture.store.closeTab(fixture.id)
        #expect(fixture.tab.archivedAt != nil)
        #expect(!fixture.owner.canUndo)
        #expect(!fixture.owner.canPerform(redoCommand))
    }

    @Test func aDeletedOriginalIsNotRecreated() throws {
        let fixture = try Fixture()
        try fixture.recorded("Saved name")
        fixture.store.closeTab(fixture.id)
        fixture.store.deleteArchivedTabs([fixture.id])
        #expect(!fixture.store.state.tabs.contains { $0.id == fixture.id })
        #expect(!fixture.owner.canUndo)
    }

    @Test func windowTeardownClearsTheNameChronology() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.owner.removeAllActions()
        #expect(fixture.owner.undoMenuItemTitle == "Undo")
    }

    @Test func aMemoryOnlyOwnerUndoesAndRedoes() throws {
        let privateTab = try PrivateTab()
        privateTab.undo.undo()
        #expect(privateTab.store.state.tabs.first?.customTitle == nil)
        privateTab.undo.redo()
        #expect(privateTab.store.state.tabs.first?.customTitle == "Private")
    }

    @Test func aPrivateRedoWritesNoProfileOrModelFiles() throws {
        let privateTab = try PrivateTab()
        privateTab.undo.undo()
        privateTab.undo.redo()
        #expect(!FileManager.default.fileExists(atPath: privateTab.path.path))
    }

    enum Refusal: CaseIterable {
        case retiredProfile, replacementTab, crossProfileReassignment

        func apply(to state: inout BrowserState) {
            switch self {
            case .retiredProfile: state.profiles.removeAll()
            case .replacementTab: state.tabs[0].id = UUID()
            case .crossProfileReassignment: state.tabs[0].profileID = UUID()
            }
        }
    }

    @Test(arguments: Refusal.allCases)
    func aChangedOriginalRefusesTheInverse(_ refusal: Refusal) throws {
        let privateTab = try PrivateTab()
        var changed = privateTab.store.state
        refusal.apply(to: &changed)
        #expect(privateTab.change.target(in: changed, undo: true) == nil)
    }

    @Test func theStackNeverRetainsAClosedPrivateOwner() throws {
        let fixture = try Fixture()
        var released: BrowserStore? = fixture.privateStore().store
        let id = released!.openResolvedURL(URL(string: "https://released.test")!)
        let change = try #require(try released!.saveSidebarTitle(released!.state.tabs.first { $0.id == id }!, title: "Name"))
        let detached = FolderUndoManager()
        _ = detached.appendTabTitleChange(change, store: released!, available: { true }, onError: { _ in })
        weak let survivor = released
        released = nil
        #expect(survivor == nil)
        #expect(!detached.canUndo)
    }
}
