import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteCrossNoteMoveTests {
    final class PendingJobs: @unchecked Sendable {
        private var jobs: [@Sendable () -> Void] = []

        func schedule(_ job: @escaping @Sendable () -> Void) { jobs.append(job) }

        func runAll() {
            while !jobs.isEmpty { jobs.removeFirst()() }
        }
    }

    final class Reach {
        var open = true
    }

    let jobs = PendingJobs()

    func schedule() -> @Sendable (@escaping @Sendable () -> Void) -> Void {
        let jobs = jobs
        return { jobs.schedule($0) }
    }

    func access(_ session: NotePageSession) -> NoteCrossNoteMove.Access {
        { body in body(session); return true }
    }

    func texts(_ session: NotePageSession) -> [String] {
        session.page.blocks.map(\.text.plainText)
    }

    func pair() -> (NotePageSession, NotePageSession, NoteCrossNoteMove) {
        let source = NotePageSession(page: NotePage(blocks: [.paragraph("a"), .paragraph("b"), .paragraph("c")]))
        let target = NotePageSession(page: NotePage(blocks: [.paragraph("x"), .paragraph("b")]))
        let id = source.page.blocks[1].id
        let move = NoteCrossNoteMove.perform([id], from: source, name: "Move to “T”", target: access(target), source: access(source), schedule: schedule())!
        return (source, target, move)
    }

    func expectMoved(_ source: NotePageSession, _ target: NotePageSession, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(texts(source) == ["a", "c"], sourceLocation: sourceLocation)
        #expect(texts(target) == ["x", "b", "b"], sourceLocation: sourceLocation)
    }

    func expectReversed(_ source: NotePageSession, _ target: NotePageSession, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(texts(source) == ["a", "b", "c"], sourceLocation: sourceLocation)
        #expect(texts(target) == ["x", "b"], sourceLocation: sourceLocation)
    }

    @Test func theBlockLeavesTheSource() {
        let (source, _, _) = pair()
        #expect(texts(source) == ["a", "c"])
    }

    @Test func theCopyLandsAtTheEndOfTheTargetWithFreshIDs() {
        let (_, target, move) = pair()
        #expect(texts(target) == ["x", "b", "b"])
        #expect(move.copyIDs.allSatisfy(target.page.contains))
    }

    @Test func theMoveStartsApplied() {
        #expect(pair().2.isApplied)
    }

    @Test func anUnrelatedUndoAndRedoInTheSourceNeverTouchTheTarget() {
        let (source, target, _) = pair()
        source.edit("Type") { page in page.blocks[0].text = NoteText("a!") }
        source.undo()
        #expect(texts(target) == ["x", "b", "b"])
        source.redo()
        #expect(texts(target) == ["x", "b", "b"])
    }

    @Test func anUnrelatedUndoInTheTargetNeverTouchesTheSource() {
        let (source, target, _) = pair()
        target.edit("Type") { page in page.blocks[0].text = NoteText("y") }
        target.undo()
        #expect(texts(source) == ["a", "c"])
    }

    @Test func undoInTheSourcePutsTheBlockBackAndRemovesOnlyTheCopy() {
        let (source, target, move) = pair()
        source.undo()
        expectReversed(source, target)
        #expect(!move.isApplied)
    }

    @Test func redoInTheSourceMovesTheBlockOutAgain() {
        let (source, target, _) = pair()
        source.undo()
        source.redo()
        expectMoved(source, target)
    }

    @Test func olderUndosNeverTouchAReversedMoveAgain() {
        let (source, target, _) = pair()
        source.undo()
        source.redo()
        source.undo()
        source.undo()
        #expect(texts(target) == ["x", "b"])
    }

    @Test func undoInTheTargetRestoresTheSource() {
        let (source, target, move) = pair()
        target.undo()
        expectReversed(source, target)
        #expect(!move.isApplied)
    }

    @Test func redoInTheTargetReappliesTheMove() {
        let (source, target, _) = pair()
        target.undo()
        target.redo()
        expectMoved(source, target)
    }

    @Test func eitherSideCanReverseAMoveTheOtherReapplied() {
        let (source, target, _) = pair()
        target.undo()
        target.redo()
        source.undo()
        expectReversed(source, target)
    }

    @Test func redoInTheTargetReappliesAMoveTheSourceReversed() {
        let (source, target, _) = pair()
        target.undo()
        target.redo()
        source.undo()
        target.redo()
        expectMoved(source, target)
    }

    @Test func undoInTheSourceReversesAMoveTheTargetReapplied() {
        let (source, target, _) = pair()
        target.undo()
        target.redo()
        source.undo()
        target.redo()
        source.undo()
        expectReversed(source, target)
    }

    @Test func undoingInTheSourceUndoesTheTargetsHalfAsARealStep() {
        let (source, target, _) = pair()
        source.undo()
        #expect(texts(target) == ["x", "b"])
        #expect(!target.canUndo && target.redoActionName == "Move Here")
    }

    @Test func redoInTheTargetAfterASourceUndoPutsTheStepBackInBothHistories() {
        let (source, target, move) = pair()
        source.undo()
        target.redo()
        expectMoved(source, target)
        #expect(move.isApplied && source.undoDepth == 1 && target.undoDepth == 1 && !source.canRedo && !target.canRedo)
    }

    @Test func undoInTheTargetThenRedoInTheSourceStillWorkAfterward() {
        let (source, target, move) = pair()
        source.undo()
        target.redo()
        target.undo()
        expectReversed(source, target)
        source.redo()
        expectMoved(source, target)
        #expect(move.isApplied)
    }

    @Test func undoingInTheTargetUndoesTheSourcesHalfAsARealStep() {
        let (source, target, _) = pair()
        target.undo()
        #expect(texts(source) == ["a", "b", "c"])
        #expect(!source.canUndo && source.redoActionName == "Move to “T”")
    }

    @Test func redoInTheSourceAfterATargetUndoPutsTheStepBackInBothHistories() {
        let (source, target, move) = pair()
        target.undo()
        source.redo()
        expectMoved(source, target)
        #expect(move.isApplied && source.undoDepth == 1 && target.undoDepth == 1 && !source.canRedo && !target.canRedo)
    }

    @Test func undoInTheSourceThenRedoInTheTargetStillWorkAfterward() {
        let (source, target, move) = pair()
        target.undo()
        source.redo()
        source.undo()
        expectReversed(source, target)
        target.redo()
        expectMoved(source, target)
        #expect(move.isApplied)
    }

    func editedOnTop() -> (NotePageSession, NotePageSession, NoteCrossNoteMove) {
        let (source, target, move) = pair()
        target.edit("Type") { page in page.blocks[0].text = NoteText("y") }
        return (source, target, move)
    }

    @Test func undoRemovesTheCopyPastTheTargetsNewerEdit() {
        let (source, target, _) = editedOnTop()
        source.undo()
        #expect(texts(source) == ["a", "b", "c"] && texts(target) == ["y", "b"])
    }

    @Test func theTargetRecordsTheUndoneMoveOnTopOfItsOwnSteps() {
        let (source, target, _) = editedOnTop()
        source.undo()
        #expect(target.undoDepth == 3 && target.undoActionName == "Undo Move")
    }

    @Test func redoInTheSourceBringsTheCopyBackPastTheTargetsEdit() {
        let (source, target, move) = editedOnTop()
        source.undo()
        source.redo()
        #expect(texts(source) == ["a", "c"] && texts(target) == ["y", "b", "b"] && move.isApplied)
    }

    @Test func theTargetsOwnEditIsStillThereToUndoBeforeTheMove() {
        let (source, target, _) = editedOnTop()
        source.undo()
        source.redo()
        target.undo()
        #expect(texts(target) == ["x", "b", "b"] && texts(source) == ["a", "c"])
        target.undo()
        #expect(texts(target) == ["x", "b"] && texts(source) == ["a", "b", "c"])
    }

    func editedCopy() -> (NotePageSession, NotePageSession) {
        let (source, target, move) = pair()
        let copy = move.copyIDs[0]
        target.edit("Type") { page in page.update(copy) { $0.text = NoteText("b edited") } }
        target.edit("Move") { page in
            let block = page.remove(copy)!
            page.insert([block], .top(0))
        }
        source.undo()
        return (source, target)
    }

    @Test func theMovedCopyIsFoundByIDWhereverItWent() {
        let (source, target) = editedCopy()
        expectReversed(source, target)
    }

    @Test func redoRestoresTheEditedCopyOnceWhereItWas() {
        let (source, target) = editedCopy()
        source.redo()
        #expect(texts(target) == ["b edited", "x", "b"])
    }

    @Test func unrelatedUndosNeverReAddAnEditedCopy() {
        let (source, target) = editedCopy()
        source.redo()
        source.edit("Type") { page in page.blocks[0].text = NoteText("a!") }
        source.undo()
        #expect(texts(target) == ["b edited", "x", "b"])
    }

    func bouncedBySource() -> (NotePageSession, NotePageSession, NoteCrossNoteMove) {
        let source = NotePageSession(page: NotePage(blocks: [.paragraph("a"), .paragraph("b")]))
        let target = NotePageSession(page: NotePage(blocks: [.paragraph("x")]))
        let reach = Reach()
        let gate: NoteCrossNoteMove.Access = { body in
            guard reach.open else { return false }
            body(source)
            return true
        }
        let move = NoteCrossNoteMove.perform([source.page.blocks[1].id], from: source, name: "Move", target: access(target), source: gate,
                                             schedule: schedule())!
        reach.open = false
        target.undo()
        jobs.runAll()
        return (source, target, move)
    }

    @Test func whenTheSourceCannotTakeTheBlocksBackTheTargetKeepsThem() {
        let (_, target, move) = bouncedBySource()
        #expect(texts(target) == ["x", "b"])
        #expect(move.isApplied)
    }

    @Test func aRedoAfterTheSourceBounceKeepsOneCopy() {
        let (source, target, _) = bouncedBySource()
        target.redo()
        jobs.runAll()
        #expect(texts(target) == ["x", "b"] && texts(source) == ["a"])
    }

    func readOnlyTarget() -> (NotePageSession, NotePageSession, NoteCrossNoteMove) {
        let source = NotePageSession(page: NotePage(blocks: [.paragraph("a"), .paragraph("b")]))
        let target = NotePageSession(page: NotePage(blocks: [.paragraph("x")]))
        let move = NoteCrossNoteMove.perform([source.page.blocks[1].id], from: source, name: "Move", target: access(target), source: access(source),
                                             schedule: schedule())!
        source.undo()
        return (source, target, move)
    }

    @Test func undoRestoresTheSourceFirst() {
        let (source, target, _) = readOnlyTarget()
        #expect(texts(source) == ["a", "b"] && texts(target) == ["x"])
    }

    @Test func whenTheTargetCannotTakeTheBlocksARedoLeavesThemInTheSource() {
        let (source, target, move) = readOnlyTarget()
        target.isReadOnly = true
        source.redo()
        jobs.runAll()
        #expect(texts(source) == ["a", "b"])
        #expect(texts(target) == ["x"] && !move.isApplied)
    }

    @Test func onceTheTargetIsWritableUndoingTheBounceMovesTheBlocksForReal() {
        let (source, target, _) = readOnlyTarget()
        target.isReadOnly = true
        source.redo()
        jobs.runAll()
        target.isReadOnly = false
        source.undo()
        #expect(texts(source) == ["a"] && texts(target) == ["x", "b"])
    }

    final class Reopenable {
        var target: NotePageSession
        init(_ target: NotePageSession) { self.target = target }
    }

    func reopened() -> (NotePageSession, Reopenable, NoteCrossNoteMove, [NoteBlockID]) {
        let source = NotePageSession(page: NotePage(blocks: [.paragraph("a"), .paragraph("b")]))
        let note = Reopenable(NotePageSession(page: NotePage(blocks: [.paragraph("b"), .paragraph("x")])))
        let reach: NoteCrossNoteMove.Access = { body in body(note.target); return true }
        let move = NoteCrossNoteMove.perform([source.page.blocks[1].id], from: source, name: "Move", target: reach, source: access(source),
                                             schedule: schedule())!
        let stale = move.copyIDs
        note.target = NotePageSession(page: NotePage(blocks: note.target.page.blocks.map { $0.withFreshIDs() }))
        note.target.edit("Type") { page in page.insert([.paragraph("new")], .top(0)) }
        source.undo()
        return (source, note, move, stale)
    }

    @Test func aReopenedNoteLosesExactlyTheMovedCopyNotItsTwin() {
        let (source, note, _, _) = reopened()
        #expect(texts(note.target) == ["new", "b", "x"])
        #expect(texts(source) == ["a", "b"])
    }

    @Test func theMoveFollowsTheReopenedNotesBlockIDs() {
        let (_, _, move, stale) = reopened()
        #expect(move.copyIDs != stale)
    }

    @Test func redoLandsInTheReopenedNote() {
        let (source, note, _, _) = reopened()
        source.redo()
        #expect(texts(note.target) == ["new", "b", "x", "b"] && texts(source) == ["a"])
    }
}
