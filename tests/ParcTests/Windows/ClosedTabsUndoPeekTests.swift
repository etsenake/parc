import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct ClosedTabsUndoPeekTests {
    @MainActor private final class PeekRig {
        let f: ClosedTabsUndoSupport.ArchiveFixture
        let record: ClosedPeekRecord
        var opened: [ClosedPeekRecord] = []
        var openWorks = false
        var closeRequests: [UUID] = []
        var closeWorks = true
        var livePeeks = Set<UUID>()
        var parentElsewhere = false
        var parentMoves: [() -> Void] = []

        init() throws {
            f = try ClosedTabsUndoSupport.ArchiveFixture()
            record = ClosedPeekRecord(id: UUID(), url: URL(string: "https://peek.invalid/a")!, parentTabID: f.t1.id, profileID: f.profile.id)
        }

        func append(to manager: FolderUndoManager, appended: @escaping (ClosedPeekUndoOperation) -> Void) {
            manager.appendClosedPeek(record, state: { [unowned self] in f.store.state }, canOpen: { _ in true }, open: { [unowned self] operation, done in
                let openHere = { [unowned self] in
                    opened.append(operation.record)
                    guard openWorks else { done(false); return }
                    let adopted = UUID()
                    livePeeks.insert(adopted)
                    operation.openedPeek = adopted
                    done(true)
                }
                guard parentElsewhere else { openHere(); return }
                parentMoves.append(openHere)
            }, isOpen: { [unowned self] operation in operation.openedPeek.map(livePeeks.contains) == true },
               canClose: { [unowned self] operation in operation.openedPeek.map(livePeeks.contains) == true }, close: { [unowned self] operation, done in
                closeRequests.append(operation.openedPeek!)
                guard closeWorks else { done(nil); return }
                livePeeks.remove(operation.openedPeek!)
                done(ClosedPeekRecord(id: UUID(), url: operation.record.url, parentTabID: operation.record.parentTabID,
                                      profileID: operation.record.profileID))
            }, appended: appended)
        }
    }

    @Test func aClosedPeekReadsUndoClosePeek() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        #expect(operation != nil && window.undoMenuItemTitle == "Undo Close Peek")
    }

    @Test func aPeekThatCantOpenKeepsItsUndo() throws {
        let rig = try PeekRig()
        let window = FolderUndoManager()
        rig.append(to: window) { _ in }
        window.undo()
        #expect(rig.opened == [rig.record] && window.canUndo && !window.canRedo)
    }

    @Test func undoOpensItAgainAndRemembersThatPeekAndRedoClosePeekFollows() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.openWorks = true
        window.undo()
        #expect(rig.opened.count == 1 && operation?.openedPeek != nil && window.redoMenuItemTitle == "Redo Close Peek")
    }

    @Test func aRefusedCloseKeepsTheRedo() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.openWorks = true
        window.undo()
        let reopenedPeek = try #require(operation?.openedPeek)
        rig.closeWorks = false
        window.redo()
        #expect(rig.closeRequests == [reopenedPeek] && window.canRedo)
    }

    @Test func redoClosesThePeekUndoOpenedNotAnotherOverTheSameParentAndTakesThatClosesRecord() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.openWorks = true
        window.undo()
        let reopenedPeek = try #require(operation?.openedPeek)
        let otherPeek = UUID()
        rig.livePeeks.insert(otherPeek)
        rig.closeWorks = false
        window.redo()
        rig.closeWorks = true
        window.redo()
        #expect(rig.closeRequests == [reopenedPeek, reopenedPeek] && rig.livePeeks == [otherPeek] && window.canUndo)
        #expect(operation?.record.id != rig.record.id && operation?.openedPeek == nil)
    }

    @Test func onceReopenClosedTabTookThePeeksStepUndoHasNothingLeft() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.openWorks = true
        window.undo()
        window.redo()
        let taken = try #require(operation)
        taken.didReopen(taken.record)
        #expect(!window.canUndo)
    }

    @Test func peekUndoWaitsWhileItsParentMovesHere() throws {
        let rig = try PeekRig()
        let window = FolderUndoManager()
        rig.append(to: window) { _ in }
        rig.parentElsewhere = true
        rig.openWorks = true
        window.undo()
        #expect(window.isBusy && !window.canUndo && !window.canRedo && rig.parentMoves.count == 1 && rig.opened.isEmpty)
    }

    @Test func peekUndoFinishesAfterItsParentMovesHere() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.parentElsewhere = true
        rig.openWorks = true
        window.undo()
        rig.parentMoves.removeFirst()()
        #expect(!window.isBusy && operation?.openedPeek != nil && window.redoMenuItemTitle == "Redo Close Peek")
    }

    @Test func peekUndoWaitsForAnUnresolvedParentMove() throws {
        let rig = try PeekRig()
        let window = FolderUndoManager()
        rig.append(to: window) { _ in }
        rig.parentElsewhere = true
        window.undo()
        #expect(window.isBusy && rig.parentMoves.count == 1)
    }

    @Test func aFailedPeekReopenPreservesUndoClosePeek() throws {
        let rig = try PeekRig()
        let window = FolderUndoManager()
        rig.append(to: window) { _ in }
        rig.parentElsewhere = true
        window.undo()
        rig.parentMoves.removeFirst()()
        #expect(!window.isBusy && window.canUndo && !window.canRedo && window.undoMenuItemTitle == "Undo Close Peek")
    }

    @Test func aReopenedPeekThatLeftSomeOtherWayLeavesNothingToRedo() throws {
        let rig = try PeekRig()
        var operation: ClosedPeekUndoOperation?
        let window = FolderUndoManager()
        rig.append(to: window) { operation = $0 }
        rig.openWorks = true
        window.undo()
        rig.livePeeks.remove(try #require(operation?.openedPeek))
        #expect(!window.canRedo)
    }

    @Test func aPeekWhoseParentLeftTheSidebarCantComeBack() throws {
        let rig = try PeekRig()
        let window = FolderUndoManager()
        rig.append(to: window) { _ in }
        _ = rig.f.close([rig.f.t1.id], focused: nil)
        #expect(!window.canUndo)
    }
}
