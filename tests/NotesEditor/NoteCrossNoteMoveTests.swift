import Foundation

@main @MainActor
struct NoteCrossNoteMoveTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func access(_ session: NotePageSession) -> NoteCrossNoteMove.Access {
        { body in body(session); return true }
    }

    static func texts(_ session: NotePageSession) -> [String] {
        session.page.blocks.map(\.text.plainText)
    }

    static func pair() -> (NotePageSession, NotePageSession, NoteCrossNoteMove) {
        let source = NotePageSession(page: NotePage(blocks: [.paragraph("a"), .paragraph("b"), .paragraph("c")]))
        let target = NotePageSession(page: NotePage(blocks: [.paragraph("x"), .paragraph("b")]))
        let id = source.page.blocks[1].id
        let move = NoteCrossNoteMove.perform([id], from: source, name: "Move to “T”", target: access(target), source: access(source))!
        return (source, target, move)
    }

    static func main() {
        moveLands()
        unrelatedUndoLeavesTargetAlone()
        undoInSourceRestoresBoth()
        undoInTargetRestoresSource()
        editedCopiesSurviveRoundTrip()
        unreachableSourceKeepsCopies()
        print("NoteCrossNoteMoveTests passed")
    }

    static func moveLands() {
        let (source, target, move) = pair()
        expect(texts(source) == ["a", "c"], "the block leaves the source")
        expect(texts(target) == ["x", "b", "b"], "the copy lands at the end of the target")
        expect(move.copyIDs.allSatisfy(target.page.contains), "copies carry their fresh IDs")
        expect(move.isApplied, "the move starts applied")
    }

    static func unrelatedUndoLeavesTargetAlone() {
        let (source, target, _) = pair()
        source.edit("Type") { page in page.blocks[0].text = NoteText("a!") }
        source.undo()
        expect(texts(target) == ["x", "b", "b"], "an unrelated undo never touches the target, even with identical content")
        source.redo()
        expect(texts(target) == ["x", "b", "b"], "an unrelated redo never re-adds copies")
        target.edit("Type") { page in page.blocks[0].text = NoteText("y") }
        target.undo()
        expect(texts(source) == ["a!", "c"], "an unrelated undo in the target never touches the source")
    }

    static func undoInSourceRestoresBoth() {
        let (source, target, move) = pair()
        source.undo()
        expect(texts(source) == ["a", "b", "c"], "undo puts the block back where it was")
        expect(texts(target) == ["x", "b"], "undo removes only the moved copy from the target")
        expect(!move.isApplied, "the move is reversed")
        source.redo()
        expect(texts(source) == ["a", "c"], "redo moves the block out again")
        expect(texts(target) == ["x", "b", "b"], "redo puts the copy back")
        source.undo()
        source.undo()
        expect(texts(target) == ["x", "b"], "older undos never touch a reversed move again")
    }

    static func undoInTargetRestoresSource() {
        let (source, target, move) = pair()
        target.undo()
        expect(texts(target) == ["x", "b"], "undo in the target removes the copy")
        expect(texts(source) == ["a", "b", "c"], "undo in the target restores the block to the source")
        expect(!move.isApplied, "the move is reversed from the target side")
        target.redo()
        expect(texts(target) == ["x", "b", "b"], "redo in the target brings the copy back")
        expect(texts(source) == ["a", "c"], "redo in the target removes the block from the source")
        source.undo()
        expect(texts(source) == ["a", "b", "c"] && texts(target) == ["x", "b"], "either side can reverse it next")
        target.undo()
        expect(texts(source) == ["a", "c"] && texts(target) == ["x", "b", "b"], "undoing the reversal in the target reapplies the move")
        source.undo()
        expect(texts(source) == ["a", "b", "c"] && texts(target) == ["x", "b"], "undo in the source reverses it again")
    }

    static func editedCopiesSurviveRoundTrip() {
        let (source, target, move) = pair()
        let copy = move.copyIDs[0]
        target.edit("Type") { page in page.update(copy) { $0.text = NoteText("b edited") } }
        target.edit("Move") { page in
            let block = page.remove(copy)!
            page.insert([block], .top(0))
        }
        source.undo()
        expect(texts(target) == ["x", "b"], "the moved copy is found by ID wherever it went")
        expect(texts(source) == ["a", "b", "c"], "the source gets its block back")
        source.redo()
        expect(texts(target) == ["x", "b", "b edited"], "redo restores the edited copy once, not a stale duplicate")
        source.edit("Type") { page in page.blocks[0].text = NoteText("a!") }
        source.undo()
        expect(texts(target) == ["x", "b", "b edited"], "unrelated undos never re-add copies")
    }

    static func unreachableSourceKeepsCopies() {
        let source = NotePageSession(page: NotePage(blocks: [.paragraph("a"), .paragraph("b")]))
        let target = NotePageSession(page: NotePage(blocks: [.paragraph("x")]))
        var reachable = true
        let gate: NoteCrossNoteMove.Access = { body in
            guard reachable else { return false }
            body(source)
            return true
        }
        let id = source.page.blocks[1].id
        let move = NoteCrossNoteMove.perform([id], from: source, name: "Move", target: access(target), source: gate)!
        reachable = false
        target.undo()
        expect(texts(target) == ["x", "b"], "when the source can't take the blocks back, the target keeps them")
        expect(move.isApplied, "the move stays applied so nothing is lost")
    }
}
