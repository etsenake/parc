import Combine
import Foundation

@main @MainActor
struct PageUndoTests {
    static func main() {
        typingCoalesces()
        typingAndDeletingSplit()
        selectionRestoresExactly()
        groupsMakeOneStep()
        markdownShortcutUndoesToLiteral()
        typingOverSelection()
        historyLimitsAndResets()
        readOnlyRefuses()
        changeNotifications()
        adjustmentsCoalesce()
        print("PageUndoTests passed")
    }

    static func typingCoalesces() {
        let clock = TestClock()
        let session = makeSession([para(""), para("other")], clock: clock)
        let first = session.page.blocks[0].id
        session.setSelection(.caret(NotePosition(first, 0)))
        for letter in ["H", "e", "y"] { session.type(letter); clock.advance(0.3) }
        expectEqual(session.undoDepth, 1, "quick typing in one block is one step")
        expectEqual(session.undoActionName, "Typing", "and it's called Typing")
        clock.advance(5)
        session.type("!")
        expectEqual(session.undoDepth, 2, "a pause starts a new step")
        session.caret("other", 5)
        session.type("s")
        expectEqual(session.undoDepth, 3, "typing somewhere else starts a new step")
        session.undo()
        expectOutline(session.page, "p Hey!\np other", "undo removes the last burst")
        session.undo()
        expectOutline(session.page, "p Hey\np other", "then the one before")
        session.undo()
        expectOutline(session.page, "p\np other", "then the first burst")
        expectEqual(session.selection, .caret(NotePosition(first, 0)), "and the caret goes back to where typing began")
        session.redo()
        expectEqual(session.selection, .caret(NotePosition(first, 3)), "redo puts the caret where typing ended")
        session.redo()
        session.redo()
        expectOutline(session.page, "p Hey!\np others", "redo replays everything")
        expect(!session.canRedo, "and runs out")
    }

    static func typingAndDeletingSplit() {
        let session = makeSession([para("")])
        let id = session.page.blocks[0].id
        session.setSelection(.caret(NotePosition(id, 0)))
        session.type("abc")
        session.deleteBackward()
        session.deleteBackward()
        session.type("Z")
        expectEqual(session.page.blocks[0].text.string, "aZ", "typing and deleting both landed")
        expectEqual(session.undoDepth, 3, "typing, deleting and typing again are three steps")
        session.undo()
        expectEqual(session.page.blocks[0].text.string, "a", "undo takes back the last typing")
        session.undo()
        expectEqual(session.page.blocks[0].text.string, "abc", "then the deletions together")
    }

    static func selectionRestoresExactly() {
        let session = makeSession([bullet("one"), bullet("two")])
        let two = session.id("two")
        session.setSelection(.text(anchor: NotePosition(two, 1), head: NotePosition(two, 3)))
        session.indent([two])
        session.setSelection(.caret(NotePosition(session.id("one"), 0)))
        session.undo()
        expectEqual(session.selection, .text(anchor: NotePosition(two, 1), head: NotePosition(two, 3)), "undo restores the selection from before the step")
        session.setSelection(.none)
        session.redo()
        expectEqual(session.selection, .text(anchor: NotePosition(two, 1), head: NotePosition(two, 3)), "redo restores the selection from after the step")

        let split = makeSession([para("abcd")])
        let id = split.page.blocks[0].id
        split.setSelection(.caret(NotePosition(id, 2)))
        let fresh = split.splitBlock(at: NotePosition(id, 2))!
        split.undo()
        expectEqual(split.selection, .caret(NotePosition(id, 2)), "undoing a split puts the caret back mid-word")
        split.redo()
        expectEqual(split.selection, .caret(NotePosition(fresh, 0)), "redo lands in the new block")
        expectEqual(split.redoActionName, nil, "nothing left to redo")
        expectEqual(split.undoActionName, "New Block", "the step keeps its name")

        let moved = makeSession([para("x")])
        moved.setSelection(.caret(NotePosition(moved.page.blocks[0].id, 1)))
        expectEqual(moved.undoDepth, 0, "selection changes alone never make undo steps")
    }

    static func groupsMakeOneStep() {
        let session = makeSession([para("a"), para("b")])
        session.group("Rearrange") {
            session.moveBlocks([session.id("b")], .up)
            session.group("Inner") {
                session.turnInto([session.id("a")], kind: .heading)
            }
            session.setColor(.text(.red), in: .blocks([session.id("b")]))
        }
        expectEqual(session.undoDepth, 1, "a group with nested groups is one step")
        expectEqual(session.undoActionName, "Rearrange", "named after the outer group")
        session.undo()
        expectOutline(session.page, "p a\np b", "one undo reverts the whole group")
        expect(session.page.blocks[1].color == nil, "including the colour")
        session.redo()
        expectOutline(session.page, "p b\nh1 a", "and one redo replays it")

        let quiet = makeSession([para("a")])
        let value = quiet.group("Nothing") { 42 }
        expect(value == 42 && quiet.undoDepth == 0, "a group that changes nothing leaves no step and returns its value")

        let typed = makeSession([para("")])
        typed.setSelection(.caret(NotePosition(typed.page.blocks[0].id, 0)))
        typed.type("a")
        typed.group("Shortcut") { typed.turnInto([typed.page.blocks[0].id], kind: .quote) }
        typed.type("b")
        expectEqual(typed.undoDepth, 3, "typing never coalesces across a group")
    }

    static func markdownShortcutUndoesToLiteral() {
        let session = makeSession([para("")])
        let id = session.page.blocks[0].id
        session.setSelection(.caret(NotePosition(id, 0)))
        session.type("#")
        session.type(" ")
        session.applyBlockShortcut(id, prefixLength: 2, conversion: .heading(1))
        session.type("Title")
        expectOutline(session.page, "h1 Title", "the shortcut made a heading")
        session.undo()
        expectOutline(session.page, "h1", "undo first takes back the typing")
        session.undo()
        expectOutline(session.page, "p #", "then the shortcut, leaving the literal characters")
        expectEqual(session.page.blocks[0].text.string, "# ", "including the space")
        expectEqual(session.selection, .caret(NotePosition(id, 2)), "with the caret after them")
        session.redo()
        expectOutline(session.page, "h1", "redo converts again")
        expectEqual(session.selection, .caret(NotePosition(id, 0)), "with the caret at the start of the heading")

        let list = makeSession([para("")])
        let item = list.page.blocks[0].id
        list.setSelection(.caret(NotePosition(item, 0)))
        list.type("- ")
        list.applyBlockShortcut(item, prefixLength: 2, conversion: .bulletedList)
        list.undo()
        expectEqual(list.page.blocks[0].text.string, "- ", "a list shortcut undoes to its dash and space")
    }

    static func typingOverSelection() {
        let session = makeSession([para("Hello world")])
        let id = session.page.blocks[0].id
        session.setSelection(.text(anchor: NotePosition(id, 6), head: NotePosition(id, 11)))
        session.insertText(NoteText("t"))
        session.type("here")
        expectOutline(session.page, "p Hello there", "typing replaced the selection")
        expectEqual(session.undoDepth, 1, "replacing and the typing after it are one step")
        session.undo()
        expectOutline(session.page, "p Hello world", "one undo brings the word back")
        expectEqual(session.selection, .text(anchor: NotePosition(id, 6), head: NotePosition(id, 11)), "still selected")

        let cross = makeSession([para("abc"), para("def")])
        cross.setSelection(.text(anchor: NotePosition(cross.id("abc"), 1), head: NotePosition(cross.id("def"), 2)))
        cross.insertText(NoteText("X"))
        expectOutline(cross.page, "p aXf", "typing over a cross-block selection merges the ends")
        cross.undo()
        expectOutline(cross.page, "p abc\np def", "and undoes in one go")

        let deletion = makeSession([para("abc")])
        let block = deletion.page.blocks[0].id
        deletion.setSelection(.caret(NotePosition(block, 3)))
        deletion.type("d")
        deletion.setSelection(.text(anchor: NotePosition(block, 0), head: NotePosition(block, 2)))
        deletion.deleteSelection()
        expectEqual(deletion.undoDepth, 2, "deleting a selection is its own step, not more typing")
    }

    static func historyLimitsAndResets() {
        let session = makeSession([para("x")])
        session.undoLimit = 3
        for index in 0..<6 { session.updateBlock(session.page.blocks[0].id) { $0.text = NoteText("v\(index)") } }
        expectEqual(session.undoDepth, 3, "history keeps only the newest steps")
        session.undo()
        expect(session.canRedo, "undo makes redo possible")
        session.updateBlock(session.page.blocks[0].id) { $0.text = NoteText("fresh") }
        expect(!session.canRedo, "a new edit clears redo")
        session.replacePage(NotePage(blocks: [para("loaded")]))
        expect(!session.canUndo && !session.canRedo, "replacing the page clears history")
        session.updateBlock(session.page.blocks[0].id) { $0.text = NoteText("edited") }
        session.replacePage(NotePage(blocks: [para("reloaded")]), keepHistory: true)
        expect(session.canUndo, "unless asked to keep it")
        session.clearHistory()
        expect(!session.canUndo, "clearHistory forgets everything")
    }

    static func readOnlyRefuses() {
        let session = makeSession([para("x")])
        session.updateBlock(session.page.blocks[0].id) { $0.text = NoteText("y") }
        session.isReadOnly = true
        session.updateBlock(session.page.blocks[0].id) { $0.text = NoteText("z") }
        session.undo()
        expectOutline(session.page, "p y", "a locked page ignores edits and undo")
        session.isReadOnly = false
        session.undo()
        expectOutline(session.page, "p x", "unlocked, undo works again")
    }

    static func changeNotifications() {
        let session = makeSession([para("a"), bullet("b", [bullet("c")]), para("d")])
        var received: [NotePageChange] = []
        let subscription = session.changes.sink { received.append($0) }
        let a = session.id("a"), b = session.id("b"), c = session.id("c"), d = session.id("d")
        session.outdent([c])
        expectEqual(received.last?.blocks, [b, c, d], "a move reports the old parent, the moved block and its new neighbour")
        session.moveBlocks([d], .up)
        expectEqual(received.last?.blocks, [c, d], "a top-level reorder reports the blocks that traded places")
        session.moveBlocks([d], .down)
        session.deleteBlocks([d])
        expectEqual(received.last?.blocks, [d], "a delete reports the removed block")
        session.undo()
        expect(received.last?.isUndoRedo == true && received.last?.blocks == [d], "undo reports what came back")
        session.setText(NoteText("A"), of: (a, .body))
        expectEqual(received.last?.kind, .text, "typing reports a text change")
        expectEqual(received.last?.blocks, [a], "for that block only")
        let before = session.revision
        session.setSelection(.caret(NotePosition(a, 0)))
        expect(received.last?.kind == .selection && session.revision == before, "selection changes don't bump the revision")
        let old = NotePage(blocks: [para("same"), bullet("x", [bullet("y")])])
        var new = old
        new.update(new.blocks[1].children[0].id) { $0.text = NoteText("changed") }
        new.insert([para("added")], .top(0))
        expectEqual(NotePageSession.changedBlocks(from: old, to: new), [new.blocks[0].id, new.blocks[1].id, new.blocks[2].children[0].id],
                    "the diff finds additions, edits and shifted neighbours, and skips untouched blocks")
        subscription.cancel()
    }

    static func adjustmentsCoalesce() {
        let clock = TestClock()
        let session = makeSession([columns([[para("l")], [para("r")]])], clock: clock)
        let group = session.page.blocks[0].id
        for step in 1...5 {
            session.setColumnWidths(group, [0.5 + Double(step) * 0.02, 0.5 - Double(step) * 0.02])
            clock.advance(0.05)
        }
        expectEqual(session.undoDepth, 1, "a column drag is one undo step")
        let fractions = session.page.columnFractions(of: group)
        expect(abs(fractions[0] - 0.6) < 0.0001 && abs(fractions[1] - 0.4) < 0.0001, "the widths land where the drag ended")
        session.undo()
        expectEqual(session.page.columnFractions(of: group), [0.5, 0.5], "undo returns to equal columns")
    }
}
