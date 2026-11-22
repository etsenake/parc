import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct DuplicateUndoTestsRemovalTests {
    private typealias Dup = DuplicateUndoTestsSupport.Dup

    @Test func theRecordOwnsExactlyTheCopiedFoldersTabsAndWholeSplit() throws {
        let d = try Dup()
        #expect(Set(d.record.tabs.map(\.id)) == d.copiedIDs)
        #expect(d.record.folders.count == 2)
        #expect(d.record.groups.count == 1)
    }

    @Test func typedCopiesKeepTheOriginalDocumentReferences() throws {
        let d = try Dup()
        #expect(d.record.documentReferences.count == 2)
        #expect(d.record.documentsAreAvailable)
    }

    @Test func duplicateRegistersOneWindowUndoStep() throws {
        let d = try Dup()
        #expect(d.manager.canUndo)
        #expect(d.manager.undoMenuItemTitle == "Undo Duplicate")
    }

    @Test func undoWaitsWhileTheWindowCannotRetireACopy() throws {
        let d = try Dup()
        d.undoUsable = false
        #expect(!d.manager.canUndo)
    }

    @Test func declinedPageConsentLeavesEveryCopyAndTheUndoStepInPlace() throws {
        let d = try Dup().edit()
        d.allowRetirement = false
        d.manager.undo()
        #expect(d.store.state == d.edited)
        #expect(d.manager.canUndo)
        #expect(!d.manager.canRedo)
    }

    @Test func undoAsksExactlyTheCopiedPagesAndOnlyThemToClose() throws {
        let d = try Dup().edit()
        d.allowRetirement = false
        d.manager.undo()
        #expect(d.retired.last == d.copiedIDs)
    }

    @Test func undoRemovesEveryCopyAndLeavesTheOriginalTabsUntouched() throws {
        let d = try Dup().undone()
        #expect(d.store.state.tabs.allSatisfy { !d.copiedIDs.contains($0.id) })
        #expect(d.store.state.tabs == d.initial.tabs)
    }

    @Test func copiedFoldersAndSplitLeaveWhileOriginalsKeepTheirRecords() throws {
        let d = try Dup().undone()
        #expect(d.store.state.folders == d.initial.folders)
        #expect(d.store.state.splitLayouts == d.initial.splitLayouts)
    }

    @Test func everyContainerReturnsToItsPreDuplicateOrder() throws {
        let d = try Dup().undone()
        #expect(d.layout(d.store.state) == d.layout(d.initial))
    }

    @Test func undoKeepsTheWindowsSelection() throws {
        let d = try Dup().undone()
        #expect(d.store.state.selectedTabIDs == d.initial.selectedTabIDs)
        #expect(d.store.state.activeSpaceID == d.initial.activeSpaceID)
    }

    @Test func undoNeverTouchesTheSharedNoteOrEasel() throws {
        let d = try Dup().undone()
        #expect(try Data(contentsOf: d.noteFile) == d.noteBytes)
        let loaded = try d.easels.load(d.easel.document.id)
        #expect(loaded === d.easel)
    }

    @Test func undoneCopiesDoNotLandInTheArchive() throws {
        let d = try Dup().undone()
        #expect(d.store.archivedItems(profileID: d.profile.id).allSatisfy { $0.tabs.allSatisfy { !d.copiedIDs.contains($0.id) } })
    }

    @Test func undoMovesTheStepToRedo() throws {
        let d = try Dup().undone()
        #expect(d.manager.canRedo)
        #expect(d.manager.redoMenuItemTitle == "Redo Duplicate")
        #expect(!d.manager.canUndo)
    }

    @Test func theRemovalIsSaved() throws {
        let d = try Dup().undone()
        let reloaded = try BrowserStore(directory: d.root)
        #expect(reloaded.state.tabs.allSatisfy { !d.copiedIDs.contains($0.id) })
    }
}
