import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageEditingIndentationTests: NoteFixtures {
    @Test func aListItemIndentsUnderItsSibling() {
        let session = makeSession([bullet("a"), bullet("b"), para("p"), bullet("c")])
        #expect(session.indent([session.id("b")]), "a list item indents under its sibling")
        expectOutline(session.page, "ul a\n  ul b\np p\nul c")
    }

    @Test func aListItemIndentsUnderAParagraph() {
        let session = makeSession([bullet("a"), bullet("b"), para("p"), bullet("c")])
        session.indent([session.id("b")])
        #expect(session.indent([session.id("c")]), "a list item nests under a paragraph")
        expectOutline(session.page, "ul a\n  ul b\np p\n  ul c")
    }

    @Test func theFirstBlockCannotIndent() {
        let session = makeSession([bullet("a"), bullet("b"), para("p"), bullet("c")])
        #expect(!session.indent([session.id("a")]), "the first block has nothing to nest under")
    }

    @Test func indentingIntoAClosedToggleOpensItAndKeepsTheCaret() {
        let shut = makeSession([toggle("Fold", expanded: false, [para("old")]), para("new")])
        shut.setSelection(.caret(NotePosition(shut.id("new"), 1)))
        shut.indent([shut.id("new")])
        expectOutline(shut.page, "toggle Fold\n  p old\n  p new", "nesting under a closed toggle opens it and lands last")
        #expect(shut.selection == .caret(NotePosition(shut.id("new"), 1)), "the caret survives the move")
    }

    @Test func indentingSelectedSiblingsKeepsTheirSubtreesTogether() {
        let run = makeSession([bullet("a"), bullet("b", [bullet("b1")]), bullet("c"), bullet("d")])
        run.indent([run.id("b"), run.id("b1"), run.id("c")])
        expectOutline(run.page, "ul a\n  ul b\n    ul b1\n  ul c\nul d", "a selected run nests together and children ride along")
    }

    @Test func indentMovesSeparateRunsUnderTheirOwnSiblings() {
        let mixed = makeSession([bullet("a"), bullet("b"), para("x"), bullet("c"), bullet("d")])
        mixed.indent([mixed.id("b"), mixed.id("d")])
        expectOutline(mixed.page, "ul a\n  ul b\np x\nul c\n  ul d", "separate runs each nest under their own sibling")
    }

    @Test func aParagraphCanNestUnderTheParagraphBeforeIt() {
        let text = makeSession([para("one"), para("two"), heading(2, "Head"), para("three")])
        #expect(text.indent([text.id("two")]), "a paragraph nests under the paragraph before it")
    }

    @Test func aParagraphCanNestUnderAHeading() {
        let text = makeSession([para("one"), para("two"), heading(2, "Head"), para("three")])
        text.indent([text.id("two")])
        #expect(text.indent([text.id("three")]), "and under a plain heading")
        expectOutline(text.page, "p one\n  p two\nh2 Head\n  p three", "text blocks hold children like Notion")
    }

    @Test func theFirstBlockOfAColumnCannotIndentIntoThePreviousColumn() {
        let columnsPage = makeSession([columns([[bullet("x")], [bullet("y")]])])
        #expect(!columnsPage.indent([columnsPage.id("y")]), "the first block of a column can't jump into the previous column")
    }

    @Test func aNestedItemOutdents() {
        let session = makeSession([bullet("a", [bullet("b"), bullet("c"), bullet("d")])])
        #expect(session.outdent([session.id("c")]), "a nested item outdents")
        expectOutline(session.page, "ul a\n  ul b\nul c\n  ul d", "following siblings become its children")
    }

    @Test func aParagraphWithSiblingsAfterItOutdents() {
        let blocked = makeSession([toggle("T", expanded: true, [para("one"), para("two")])])
        #expect(blocked.outdent([blocked.id("one")]), "a paragraph with siblings after it outdents")
        expectOutline(blocked.page, "toggle T\np one\n  p two", "and adopts them as its children")
    }

    @Test func outdentingOpensAToggleWhenItAdoptsSiblings() {
        let shut = makeSession([bullet("a", [toggle("t", expanded: false, [para("inside")]), bullet("after")])])
        shut.outdent([shut.id("t")])
        expectOutline(shut.page, "ul a\ntoggle t\n  p inside\n  ul after", "adopting into a closed toggle opens it")
    }

    @Test func shiftTabKeepsABlockInItsColumn() {
        let columnsPage = makeSession([columns([[bullet("x", [bullet("y")])], [para("z")]])])
        #expect(!columnsPage.outdent([columnsPage.id("x")]), "Shift-Tab never pulls a block out of its column")
    }

    @Test func aNestedBlockCanOutdentWithinItsColumn() {
        let columnsPage = makeSession([columns([[bullet("x", [bullet("y")])], [para("z")]])])
        #expect(columnsPage.outdent([columnsPage.id("y")]), "nested blocks inside a column still outdent")
        expectOutline(columnsPage.page, "columns\n  column\n    ul x\n    ul y\n  column\n    p z", "and stay inside the column")
    }

    @Test func outdentWorksAcrossDifferentParents() {
        let multi = makeSession([bullet("a", [bullet("a1")]), bullet("b", [bullet("b1"), bullet("b2")])])
        multi.outdent([multi.id("a1"), multi.id("b1")])
        expectOutline(multi.page, "ul a\nul a1\nul b\nul b1\n  ul b2", "outdent works across different parents at once")
    }

    @Test func noncontiguousBlocksOutdentInOrder() {
        let runs = makeSession([bullet("p", [bullet("1"), bullet("2"), bullet("3")])])
        runs.outdent([runs.id("1"), runs.id("3")])
        expectOutline(runs.page, "ul p\nul 1\n  ul 2\nul 3", "gapped selections outdent in order")
    }
}
