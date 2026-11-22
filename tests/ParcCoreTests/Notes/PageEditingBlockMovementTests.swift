import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageEditingBlockMovementTests: NoteFixtures {
    @Test func movingUpSwapsWithThePreviousSiblingAndItsSubtree() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1"), bullet("b2")]), para("c")])
        session.setSelection(.caret(NotePosition(session.id("c"), 1)))
        session.moveBlocks([session.id("c")], .up)
        expectOutline(session.page, "p a\np c\nul b\n  ul b1\n  ul b2", "moving up swaps with the previous sibling and its children")
        #expect(session.selection == .caret(NotePosition(session.id("c"), 1)), "the caret rides along")
    }

    @Test func movingTheFirstChildUpTakesItOutOfItsParent() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1"), bullet("b2")]), para("c")])
        session.setSelection(.caret(NotePosition(session.id("c"), 1)))
        session.moveBlocks([session.id("c")], .up)
        session.moveBlocks([session.id("b1")], .up)
        expectOutline(session.page, "p a\np c\nul b1\nul b\n  ul b2", "the first child moves up out of its parent")
    }

    @Test func movingTheLastChildDownTakesItOutOfItsParent() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1"), bullet("b2")]), para("c")])
        session.setSelection(.caret(NotePosition(session.id("c"), 1)))
        session.moveBlocks([session.id("c")], .up)
        session.moveBlocks([session.id("b1")], .up)
        session.moveBlocks([session.id("b2")], .down)
        expectOutline(session.page, "p a\np c\nul b1\nul b\nul b2", "the last child moves down out of its parent")
    }

    @Test func movingSelectedBlocksDownKeepsThemTogether() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1"), bullet("b2")]), para("c")])
        session.setSelection(.caret(NotePosition(session.id("c"), 1)))
        session.moveBlocks([session.id("c")], .up)
        session.moveBlocks([session.id("b1")], .up)
        session.moveBlocks([session.id("b2")], .down)
        session.moveBlocks([session.id("a"), session.id("c")], .down)
        expectOutline(session.page, "ul b1\np a\np c\nul b\nul b2", "a selection moves together")
    }

    @Test func blocksCannotMoveUpOrDownAcrossColumnEdges() {
        let columnsPage = makeSession([columns([[para("x"), para("y")], [para("z")]])])
        columnsPage.moveBlocks([columnsPage.id("x")], .up)
        columnsPage.moveBlocks([columnsPage.id("y")], .down)
        expectOutline(columnsPage.page, "columns\n  column\n    p x\n    p y\n  column\n    p z", "moves stop at column edges")
    }

    @Test func aBlockCanMoveInsideAParagraph() {
        let refused = makeSession([para("a"), para("b"), code("c")])
        refused.moveBlocks([refused.id("b")], to: .firstChild(of: refused.id("a")))
        expectOutline(refused.page, "p a\n  p b\ncode c", "blocks can be moved inside a paragraph")
    }

    @Test func aBlockCannotMoveInsideCode() {
        let refused = makeSession([para("a"), para("b"), code("c")])
        refused.moveBlocks([refused.id("b")], to: .firstChild(of: refused.id("a")))
        refused.moveBlocks([refused.id("b")], to: .firstChild(of: refused.id("c")))
        expectOutline(refused.page, "p a\n  p b\ncode c", "but never inside code")
    }

    @Test func aBlockCannotMoveRelativeToItself() {
        let refused = makeSession([para("a"), para("b"), code("c")])
        refused.moveBlocks([refused.id("b")], to: .firstChild(of: refused.id("a")))
        refused.moveBlocks([refused.id("a")], to: .before(refused.id("a")))
        expectOutline(refused.page, "p a\n  p b\ncode c", "a block can't move relative to itself")
    }

    @Test func droppingIntoAClosedToggleOpensIt() {
        let shut = makeSession([toggle("t", expanded: false), para("x")])
        shut.moveBlocks([shut.id("x")], to: .lastChild(of: shut.id("t")))
        expectOutline(shut.page, "toggle t\n  p x", "dropping into a closed toggle opens it")
    }

    @Test func plainTextPagesRefuseIndentation() {
        let flat = makeSession([para("one"), para("two"), bullet("a"), bullet("b")])
        flat.isFlat = true
        #expect(!flat.indent([flat.id("b")]), "plain-text pages never nest")
    }

    @Test func plainTextPagesRefuseNestedDrops() {
        let session = makeSession([para("one"), para("two"), bullet("a"), bullet("b")])
        session.isFlat = true
        session.moveBlocks([session.id("two")], to: .firstChild(of: session.id("a")))
        expectOutline(session.page, "p one\np two\nul a\nul b")
    }

    @Test func plainTextPagesRefuseColumnDrops() {
        let session = makeSession([para("one"), para("two"), bullet("a"), bullet("b")])
        session.isFlat = true
        session.placeBeside([session.id("one")], target: session.id("two"), side: .right)
        expectOutline(session.page, "p one\np two\nul a\nul b")
    }

    @Test func blocksCanStillMoveWithinAPlainTextPage() {
        let flat = makeSession([para("one"), para("two"), bullet("a"), bullet("b")])
        flat.isFlat = true
        flat.moveBlocks([flat.id("b")], to: .before(flat.id("one")))
        expectOutline(flat.page, "ul b\np one\np two\nul a", "plain moves still work")
    }

    @Test func plainTextPagesRefuseOutdenting() {
        let nested = makeSession([bullet("a", [bullet("b")])])
        nested.isFlat = true
        #expect(!nested.outdent([nested.id("b")]), "and never reshuffle levels either")
    }
}
