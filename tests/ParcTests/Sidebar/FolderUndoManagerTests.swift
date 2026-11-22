import AppKit
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct FolderUndoManagerTests {
    @MainActor private final class Undo {
        let manager = FolderUndoManager()
        var valid = true
        var available = true
        var operations: [FolderUndoManager.Direction] = []
        var finish: ((Bool) -> Void)?
        var joined = 0
        lazy var entry = FolderUndoManager.Entry(name: "Archive Tabs", isValid: { [weak self] _ in self?.valid ?? false },
                                                 isAvailable: { [weak self] _ in self?.available ?? false },
                                                 perform: { [weak self] direction, done in self?.operations.append(direction); self?.finish = done })
        let newer = FolderUndoManager.Entry(name: "Archive Tab", isValid: { _ in true }, isAvailable: { _ in true }, perform: { _, done in done(true) })

        func recorded() -> Undo {
            _ = manager.append(entry)
            return self
        }

        func undone() -> Undo {
            manager.undo()
            finish?(true)
            return self
        }
    }

    @Test func nativeUndoBecomesAvailableAfterACommittedClose() {
        let undo = Undo()
        #expect(undo.manager.append(undo.entry))
        #expect(undo.manager.canUndo)
        #expect(!undo.manager.canRedo)
    }

    @Test func theNativeMenuReceivesTheRecordedPrompt() {
        let undo = Undo().recorded()
        #expect(undo.manager.undoMenuItemTitle == "Undo Archive Tabs")
    }

    @Test func aTransientOwnerRefusalPreservesTheGroupWithoutAuthorizingTheCommand() {
        let undo = Undo().recorded()
        let command = undo.manager.command(.undo)!
        undo.available = false
        #expect(!undo.manager.canUndo)
        #expect(!undo.manager.canPerform(command))
    }

    @Test func theSameExactGroupIsRetryableAfterATransientRefusal() {
        let undo = Undo().recorded()
        let command = undo.manager.command(.undo)!
        undo.available = false
        undo.available = true
        #expect(undo.manager.canPerform(command))
    }

    @Test func aPendingActionBlocksBothNativeHistoryDirections() {
        let undo = Undo().recorded()
        undo.manager.undo()
        #expect(undo.manager.isUndoing)
        #expect(undo.manager.isBusy)
        #expect(!undo.manager.canUndo)
        #expect(!undo.manager.canRedo)
    }

    @Test func busyHistoryCannotAcceptAnUnrelatedRegistration() {
        let undo = Undo().recorded()
        undo.manager.undo()
        #expect(!undo.manager.append(undo.entry))
        #expect(undo.operations == [.undo])
    }

    @Test func repeatedInvocationWhilePendingCannotRunASecondTransaction() {
        let undo = Undo().recorded()
        undo.manager.undo()
        undo.manager.redo()
        undo.manager.undo()
        #expect(undo.operations == [.undo])
    }

    @Test func aFailedUndoPreservesTheStackPosition() {
        let undo = Undo().recorded()
        undo.manager.undo()
        undo.finish?(false)
        #expect(undo.manager.canUndo)
        #expect(!undo.manager.canRedo)
        #expect(!undo.manager.isBusy)
    }

    @Test func aCommittedUndoAloneAdvancesNativeHistory() {
        let undo = Undo().recorded().undone()
        #expect(!undo.manager.canUndo)
        #expect(undo.manager.canRedo)
        #expect(undo.manager.redoMenuItemTitle == "Redo Archive Tabs")
    }

    @Test func anEarlierUndoCommandCannotConsumeTheNowRedoGroup() {
        let undo = Undo().recorded()
        let command = undo.manager.command(.undo)!
        _ = undo.undone()
        #expect(!undo.manager.canPerform(command))
    }

    @Test func redoAwaitsRealConsent() {
        let undo = Undo().recorded().undone()
        undo.manager.redo()
        #expect(undo.manager.isRedoing)
        #expect(undo.manager.isBusy)
    }

    @Test func aCancelledBeforeUnloadRetainsRedo() {
        let undo = Undo().recorded().undone()
        undo.manager.redo()
        undo.finish?(false)
        #expect(undo.manager.canRedo)
        #expect(!undo.manager.canUndo)
    }

    @Test func aCommittedRedoRestoresUndoCapability() {
        let undo = Undo().recorded().undone()
        undo.manager.redo()
        undo.finish?(true)
        #expect(undo.manager.canUndo)
        #expect(!undo.manager.canRedo)
    }

    @Test func aPriorCyclesMenuCapabilityCannotAuthorizeTheSameGroupAfterRedo() {
        let undo = Undo().recorded()
        let command = undo.manager.command(.undo)!
        _ = undo.undone()
        undo.manager.redo()
        undo.finish?(true)
        #expect(!undo.manager.canPerform(command))
    }

    @Test func duplicateAndStaleCompletionsCannotAlterTheStack() {
        let undo = Undo().recorded()
        undo.manager.undo()
        let firstCompletion = undo.finish!
        firstCompletion(true)
        undo.manager.redo()
        let redoCompletion = undo.finish!
        redoCompletion(true)
        redoCompletion(true)
        firstCompletion(true)
        #expect(undo.manager.canUndo)
        #expect(!undo.manager.canRedo)
    }

    @Test func theNextCloseRecordsADistinctGroupAndExactTopGroupIDIsRequired() {
        let undo = Undo().recorded()
        let staleCommand = undo.manager.command(.undo)!
        #expect(undo.manager.append(undo.newer))
        #expect(!undo.manager.canPerform(staleCommand))
    }

    @Test func lifoUndoPreservesTheEarlierGroupAndNextRedo() {
        let undo = Undo().recorded()
        _ = undo.manager.append(undo.newer)
        undo.manager.undo()
        #expect(undo.manager.canUndo)
        #expect(undo.manager.canRedo)
    }

    @Test func aNewCloseDiscardsTheOldRedoBranch() {
        let undo = Undo().recorded()
        _ = undo.manager.append(undo.newer)
        undo.manager.undo()
        #expect(undo.manager.append(undo.newer))
        #expect(!undo.manager.canRedo)
    }

    @Test func anInvalidUnderlyingOriginalIsDiscardedWithoutErasingValidOppositeHistory() {
        let undo = Undo().recorded()
        _ = undo.manager.append(undo.newer)
        undo.manager.undo()
        undo.valid = false
        #expect(!undo.manager.canUndo)
        #expect(undo.manager.canRedo)
    }

    @Test func windowClosureDropsTheCacheAndPrompts() {
        let undo = Undo().recorded().undone()
        undo.manager.removeAllActions()
        #expect(!undo.manager.canUndo)
        #expect(!undo.manager.canRedo)
        #expect(undo.manager.undoMenuItemTitle == "Undo")
    }

    @Test func aLateCloseCallbackCannotResurrectAClosedWindowsCache() {
        let undo = Undo().recorded()
        undo.manager.undo()
        let late = undo.finish!
        undo.manager.removeAllActions()
        late(true)
        #expect(!undo.manager.canUndo)
        #expect(!undo.manager.canRedo)
        #expect(!undo.manager.isBusy)
    }

    @Test func anIdleStackTakesACloseGroupAtOnce() {
        let undo = Undo()
        undo.manager.appendWhenIdle(undo.newer) { undo.joined += 1 }
        #expect(undo.joined == 1)
        #expect(undo.manager.canUndo)
    }

    @Test func aCloseGroupWaitsWhileAnUndoIsPending() {
        let undo = Undo().recorded()
        undo.manager.undo()
        undo.manager.appendWhenIdle(undo.newer) { undo.joined += 1 }
        #expect(undo.joined == 0)
        #expect(undo.manager.isBusy)
    }

    @Test func aWaitingGroupJoinsUndoAndTheFinishedUndoKeepsItsRedo() {
        let undo = Undo().recorded()
        undo.manager.undo()
        undo.manager.appendWhenIdle(undo.newer) { undo.joined += 1 }
        undo.finish?(true)
        #expect(undo.joined == 1)
        #expect(undo.manager.undoMenuItemTitle == "Undo Archive Tab")
        #expect(undo.manager.redoMenuItemTitle == "Redo Archive Tabs")
    }

    @Test func closingTheWindowDropsAWaitingGroup() {
        let undo = Undo().recorded()
        undo.manager.undo()
        undo.manager.appendWhenIdle(undo.newer) { undo.joined += 1 }
        let closing = undo.finish!
        undo.manager.removeAllActions()
        closing(true)
        #expect(undo.joined == 0)
        #expect(!undo.manager.canUndo)
    }

    @Test func nativeTextEditingUsesAnIndependentOrdinaryAppKitStack() {
        let undo = Undo()
        let editing = UndoManager()
        editing.registerUndo(withTarget: NSObject()) { _ in }
        #expect(editing.canUndo)
        #expect(!undo.manager.canUndo)
    }
}
