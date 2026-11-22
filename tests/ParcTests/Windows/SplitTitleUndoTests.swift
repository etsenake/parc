import AppKit
import Combine
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SplitTitleUndoTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-undo-" + UUID().uuidString)
        let store: BrowserStore
        let a: UUID
        let b: UUID
        let profile: UUID
        let groupID: UUID
        let owner = FolderUndoManager()
        let otherWindow = FolderUndoManager()
        var available = true
        var errors = 0
        var publications = 0
        var finishRetirement: ((Bool) -> Void)?
        var observation: AnyCancellable?

        init() throws {
            store = try BrowserStore(directory: directory)
            a = store.openResolvedURL(URL(string: "https://one.test")!)
            b = store.openResolvedURL(URL(string: "https://two.test")!)
            store.setSplit([a, b])
            profile = store.activeSpace.profileID
            groupID = store.state.splitLayouts.first!.id
            observation = store.statePublisher.dropFirst().sink { [unowned self] _ in publications += 1 }
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var storedTitle: String? { store.state.splitLayouts.first?.customTitle }

        func target() throws -> SidebarSplitTitleEdit {
            let group = try #require(store.state.splitLayouts.first { $0.id == groupID })
            return try #require(SidebarSplitTitleEdit(group: group, profileID: profile, state: store.state))
        }

        @discardableResult func record(_ text: String, in manager: FolderUndoManager? = nil) throws -> SidebarSplitTitleChange? {
            let manager = manager ?? owner
            guard let change = try store.saveSidebarSplitTitle(try target(), title: text) else { return nil }
            let appended = manager.appendSplitTitleChange(change, store: store, available: { [self] in available }, onError: { [self] _ in errors += 1 })
            try #require(appended)
            return change
        }

        @discardableResult func recorded(_ text: String = "Research") throws -> SidebarSplitTitleChange {
            try #require(try record(text))
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
            let path = directory.appendingPathComponent("uncreated-private")
            return (BrowserStore(privateParentProfileID: profile, engineProfilePath: "/not-opened", directory: path,
                                 settings: store.state.settings), path)
        }
    }

    @MainActor private final class PrivateSplit {
        let fixture: Fixture
        let store: BrowserStore
        let path: URL
        let change: SidebarSplitTitleChange
        let undo = FolderUndoManager()

        init() throws {
            fixture = try Fixture()
            (store, path) = fixture.privateStore()
            let one = store.openResolvedURL(URL(string: "https://private-one.test")!)
            let two = store.openResolvedURL(URL(string: "https://private-two.test")!)
            store.setSplit([one, two])
            let target = try #require(SidebarSplitTitleEdit.current(state: store.state, spaceID: store.activeSpaceID,
                                                                    profileID: store.activeSpace.profileID, selectedTabIDs: [one, two]))
            change = try #require(try store.saveSidebarSplitTitle(target, title: "Private"))
            let appended = undo.appendSplitTitleChange(change, store: store, available: { true }, onError: { _ in })
            try #require(appended)
        }
    }

    @Test func aCommittedRenameCapturesTheOriginalContainerAndProfile() throws {
        let fixture = try Fixture()
        let change = try fixture.recorded()
        #expect(change.containerID == fixture.groupID)
        #expect(change.profileID == fixture.profile)
    }

    @Test func theNativeLabelIsWindowLocal() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        #expect(fixture.owner.undoMenuItemTitle == "Undo Rename Item")
        #expect(!fixture.otherWindow.canUndo)
    }

    @Test func aTransientWindowGateRefusesAStaleMenuDispatch() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        let command = try #require(fixture.owner.command(.undo))
        fixture.available = false
        #expect(!fixture.owner.canPerform(command))
        #expect(!fixture.owner.canUndo)
    }

    @Test func aCancelledInterruptionPreservesTheOriginalCommand() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        let command = try #require(fixture.owner.command(.undo))
        fixture.available = false
        fixture.available = true
        #expect(fixture.owner.canPerform(command))
    }

    @Test func undoRestoresTheOriginalAbsenceNotAChildTitle() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.owner.undo()
        #expect(fixture.storedTitle == nil)
        #expect(fixture.owner.canRedo)
    }

    @Test func theAtomicInversePublishesOnce() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        let before = fixture.publications
        fixture.owner.undo()
        #expect(fixture.publications == before + 1)
    }

    @Test func undoLeavesPagesFocusAndHistoryUntouched() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.store.updateTab(fixture.a, title: "Live", url: "https://one.test/next")
        let current = fixture.store.state
        fixture.owner.undo()
        #expect(fixture.store.state.tabs == current.tabs)
        #expect(fixture.store.state.selectedTabIDs == current.selectedTabIDs)
        #expect(fixture.store.state.history == current.history)
    }

    @Test func undoNeverReinstatesStaleGeometry() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        #expect(fixture.store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3]))
        let current = try #require(fixture.store.state.splitLayouts.first)
        fixture.owner.undo()
        let restored = try #require(fixture.store.state.splitLayouts.first)
        #expect(restored.orientation == .vertical)
        #expect(restored.widthFactors == current.widthFactors)
    }

    @Test func theRedoLabelAndExactCommandRevisionAdvanceTogether() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        let command = try #require(fixture.owner.command(.undo))
        fixture.owner.undo()
        #expect(fixture.owner.redoMenuItemTitle == "Redo Rename Item")
        #expect(!fixture.owner.canPerform(command))
    }

    @Test func redoReappliesTheOriginalName() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.owner.undo()
        fixture.owner.redo()
        #expect(fixture.storedTitle == "Research")
    }

    @Test func aSuccessfulInverseIsDurable() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.owner.undo()
        fixture.owner.redo()
        #expect(try BrowserStore(directory: fixture.directory).state.splitLayouts.first?.customTitle == "Research")
    }

    @Test func consecutiveRenamesUndoInChronology() throws {
        let fixture = try Fixture()
        try fixture.recorded("Research")
        try fixture.recorded("Planning")
        fixture.owner.undo()
        #expect(fixture.storedTitle == "Research")
        fixture.owner.undo()
        #expect(fixture.storedTitle == nil)
    }

    @Test func consecutiveRenamesRedoInChronology() throws {
        let fixture = try Fixture()
        try fixture.recorded("Research")
        try fixture.recorded("Planning")
        fixture.owner.undo()
        fixture.owner.undo()
        fixture.owner.redo()
        #expect(fixture.storedTitle == "Research")
        fixture.owner.redo()
        #expect(fixture.storedTitle == "Planning")
    }

    @Test func aSameValueEditLeavesRedoIntact() throws {
        let fixture = try Fixture()
        try fixture.recorded("Research")
        try fixture.recorded("Planning")
        fixture.owner.undo()
        #expect(try fixture.record("Research") == nil)
        #expect(fixture.owner.canRedo)
    }

    @Test func aCompetingSharedNameInvalidatesTheOlderInverse() throws {
        let fixture = try Fixture()
        try fixture.recorded("Research")
        try fixture.recorded("Planning")
        fixture.owner.undo()
        try fixture.record("Shared window", in: fixture.otherWindow)
        #expect(!fixture.owner.canRedo)
        #expect(fixture.otherWindow.canUndo)
    }

    @Test func anotherWindowsInverseDoesNotReviveDiscardedHistory() throws {
        let fixture = try Fixture()
        try fixture.recorded("Research")
        try fixture.recorded("Planning")
        fixture.owner.undo()
        try fixture.record("Shared window", in: fixture.otherWindow)
        #expect(!fixture.owner.canRedo)
        fixture.otherWindow.undo()
        #expect(fixture.storedTitle == "Research")
        #expect(!fixture.owner.canRedo)
    }

    @Test func aNativeRetirementReservationBlocksTheNameInverse() throws {
        let fixture = try Fixture()
        let change = try fixture.recorded()
        fixture.store.requestPageRetirement = { [fixture] _, _, done in fixture.finishRetirement = done }
        fixture.store.closeTab(fixture.a)
        #expect(!fixture.owner.canUndo)
        #expect(!fixture.store.canApplySplitTitleChange(change, undo: true))
    }

    @Test func aCancelledRetirementRestoresTheInverse() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.store.requestPageRetirement = { [fixture] _, _, done in fixture.finishRetirement = done }
        fixture.store.closeTab(fixture.a)
        fixture.finishRetirement?(false)
        #expect(fixture.owner.canUndo)
    }

    @Test func aFailedDurableUndoRetainsStateAndARetryableStack() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        let before = fixture.store.state
        try fixture.breakDirectory()
        fixture.owner.undo()
        #expect(fixture.store.state == before)
        #expect(fixture.errors == 1)
        #expect(fixture.owner.canUndo)
        #expect(!fixture.owner.canRedo)
    }

    @Test func aRetryCommitsTheSameInverse() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        try fixture.breakDirectory()
        fixture.owner.undo()
        try fixture.repairDirectory()
        fixture.owner.undo()
        #expect(fixture.owner.canRedo)
        #expect(fixture.storedTitle == nil)
    }

    @Test func aDissolvedOriginalContainerCannotBeRenamedOrRecreated() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.owner.undo()
        fixture.owner.redo()
        fixture.store.closeTab(fixture.a)
        #expect(!fixture.owner.canUndo)
        #expect(!fixture.owner.canRedo)
    }

    @Test func theRemainingChildIsNeverSubstituted() throws {
        let fixture = try Fixture()
        let original = fixture.store.state.tabs.first { $0.id == fixture.b }?.customTitle
        try fixture.recorded()
        fixture.store.closeTab(fixture.a)
        #expect(fixture.store.state.tabs.first { $0.id == fixture.b }?.customTitle == original)
    }

    @Test func windowClosureDropsTheNameHistory() throws {
        let fixture = try Fixture()
        try fixture.recorded()
        fixture.owner.removeAllActions()
        #expect(fixture.owner.undoMenuItemTitle == "Undo")
        #expect(!fixture.owner.canUndo)
    }

    @Test func aPrivateStoreSupportsTheSameStack() throws {
        let split = try PrivateSplit()
        split.undo.undo()
        #expect(split.store.state.splitLayouts.first?.customTitle == nil)
        split.undo.redo()
        #expect(split.store.state.splitLayouts.first?.customTitle == "Private")
    }

    @Test func privateNameHistoryWritesNoModelOrProfileFiles() throws {
        let split = try PrivateSplit()
        split.undo.undo()
        split.undo.redo()
        #expect(!FileManager.default.fileExists(atPath: split.path.path))
    }

    enum Refusal: CaseIterable {
        case retiredProfile, replacementContainer, changedProfileOwnership

        func apply(to state: inout BrowserState) {
            switch self {
            case .retiredProfile: state.profiles.removeAll()
            case .replacementContainer: state.splitLayouts[0].id = UUID()
            case .changedProfileOwnership: state.spaces[0].profileID = UUID()
            }
        }
    }

    @Test(arguments: Refusal.allCases)
    func aChangedOriginalRefusesTheInverse(_ refusal: Refusal) throws {
        let split = try PrivateSplit()
        var changed = split.store.state
        refusal.apply(to: &changed)
        #expect(split.change.target(in: changed, undo: true) == nil)
    }

    @Test func theOriginalContainerKeepsTitleUndoAfterAChildReorder() throws {
        let split = try PrivateSplit()
        var changed = split.store.state
        changed.splitLayouts[0].tabIDs.reverse()
        #expect(split.change.target(in: changed, undo: true) != nil)
    }

    @Test func aSameProfileCrossSpaceRelocationRetainsTheTitleCapability() throws {
        let split = try PrivateSplit()
        let destination = BrowserSpace(id: UUID(), name: "Destination", symbol: "circle", color: "B9B5D4", profileID: split.change.profileID)
        var changed = split.store.state
        changed.spaces.append(destination)
        changed.splitLayouts[0].spaceID = destination.id
        for index in changed.tabs.indices { changed.tabs[index].spaceID = destination.id }
        #expect(split.change.target(in: changed, undo: true)?.spaceID == destination.id)
    }

    @Test func aRenameIsUndoneBeforeAPrecedingCloseOnTheSameStack() throws {
        let split = try PrivateSplit()
        var closed = true
        let mixed = FolderUndoManager()
        _ = mixed.append(.init(name: "Archive Tab", isValid: { _ in true }, isAvailable: { _ in true },
                               perform: { direction, done in closed = direction == .redo; done(true) }))
        _ = mixed.appendSplitTitleChange(split.change, store: split.store, available: { true }, onError: { _ in })
        mixed.undo()
        #expect(closed)
        #expect(mixed.undoMenuItemTitle == "Undo Archive Tab")
    }

    @Test func theOriginalCloseRemainsNextInChronology() throws {
        let split = try PrivateSplit()
        var closed = true
        let mixed = FolderUndoManager()
        _ = mixed.append(.init(name: "Archive Tab", isValid: { _ in true }, isAvailable: { _ in true },
                               perform: { direction, done in closed = direction == .redo; done(true) }))
        _ = mixed.appendSplitTitleChange(split.change, store: split.store, available: { true }, onError: { _ in })
        mixed.undo()
        mixed.undo()
        #expect(!closed)
        #expect(mixed.redoMenuItemTitle == "Redo Archive Tab")
    }

    @Test func mixedRedoRestoresActionsInTheOriginalOrder() throws {
        let split = try PrivateSplit()
        var closed = true
        let mixed = FolderUndoManager()
        _ = mixed.append(.init(name: "Archive Tab", isValid: { _ in true }, isAvailable: { _ in true },
                               perform: { direction, done in closed = direction == .redo; done(true) }))
        _ = mixed.appendSplitTitleChange(split.change, store: split.store, available: { true }, onError: { _ in })
        mixed.undo()
        mixed.undo()
        mixed.redo()
        mixed.redo()
        #expect(closed)
        #expect(split.store.state.splitLayouts.first?.customTitle == "Private")
    }
}
