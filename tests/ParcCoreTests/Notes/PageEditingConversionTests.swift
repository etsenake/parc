import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageEditingConversionTests: NoteFixtures {
    @Test func aParagraphConversionKeepsChildren() {
        let session = makeSession([bullet("Parent", [bullet("kid")])])
        let parent = session.id("Parent")
        session.turnInto([parent], kind: .paragraph)
        expectOutline(session.page, "p Parent\n  ul kid", "text keeps its children")
    }

    @Test func aHeadingConversionKeepsChildren() {
        let session = makeSession([bullet("Parent", [bullet("kid")])])
        let parent = session.id("Parent")
        session.turnInto([parent], kind: .paragraph)
        session.turnInto([parent], conversion: .heading(2))
        expectOutline(session.page, "h2 Parent\n  ul kid", "and so do plain headings")
    }

    @Test func aCodeConversionMovesChildrenOut() {
        let session = makeSession([bullet("Parent", [bullet("kid")])])
        let parent = session.id("Parent")
        session.turnInto([parent], kind: .paragraph)
        session.turnInto([parent], conversion: .heading(2))
        session.turnInto([parent], conversion: .code)
        expectOutline(session.page, "code Parent\nul kid", "code can't hold children, so they move out after it")
    }

    @Test func convertingSelectedBlocksToTextKeepsTheirLevels() {
        let nestedTargets = makeSession([bullet("P", [bullet("C", [bullet("G")]), bullet("D")]), bullet("Q")])
        nestedTargets.turnInto([nestedTargets.id("P"), nestedTargets.id("C"), nestedTargets.id("Q")], kind: .paragraph)
        expectOutline(nestedTargets.page, "p P\n  p C\n    ul G\n  ul D\np Q", "turning nested blocks into text keeps every level")
    }

    @Test func convertingToAToggleKeepsChildrenVisible() {
        let toToggle = makeSession([bullet("Parent", [bullet("kid")])])
        toToggle.turnInto([toToggle.id("Parent")], conversion: .toggle)
        expectOutline(toToggle.page, "toggle Parent\n  ul kid", "a toggle keeps the children inside, open")
    }

    @Test func convertingAClosedToggleToAHeadingKeepsItClosed() {
        let fold = makeSession([toggle("Fold", expanded: false, [para("kid")])])
        fold.turnInto([fold.id("Fold")], conversion: .heading(2))
        expectOutline(fold.page, "th2- Fold\n  p kid", "a toggle turned into a heading becomes a toggle heading and stays closed")
    }

    @Test func convertingAToggleHeadingToAPlainHeadingShowsItsChildren() {
        let fold = makeSession([toggle("Fold", expanded: false, [para("kid")])])
        fold.turnInto([fold.id("Fold")], conversion: .heading(2))
        fold.turnInto([fold.id("Fold")], conversion: .heading(1))
        expectOutline(fold.page, "h1 Fold\n  p kid", "a toggle heading turned into a plain heading keeps its children, always shown")
        #expect(fold.page.blocks[0].showsChildren, "plain headings never hide children")
    }

    @Test func aNewToggleHeadingStartsOpen() {
        let fold = makeSession([toggle("Fold", expanded: false, [para("kid")])])
        fold.turnInto([fold.id("Fold")], conversion: .heading(2))
        fold.turnInto([fold.id("Fold")], conversion: .heading(1))
        fold.turnInto([fold.id("Fold")], conversion: .toggleHeading(3))
        expectOutline(fold.page, "th3 Fold\n  p kid", "a new toggle heading starts open")
    }

    @Test func codeFlattensMarksAndMentionsToPlainText() {
        let rich = NoteText(pieces: [("Sum ", boldMarks)]) + NoteText.atom(.equation("x^2"))
        let converted = makeSession([NoteBlock(.paragraph, text: rich)])
        let richID = converted.page.blocks[0].id
        converted.setSelection(.caret(NotePosition(richID, 5)))
        converted.turnInto([richID], conversion: .code)
        #expect(converted.page.blocks[0].text.isPlain && converted.page.blocks[0].text.string == "Sum x^2", "code flattens marks and mentions to plain text")
        #expect(converted.selection == .caret(NotePosition(richID, 5)), "the caret stays put")
    }

    @Test func convertingCodeToTextKeepsLineBreaks() {
        let rich = NoteText(pieces: [("Sum ", boldMarks)]) + NoteText.atom(.equation("x^2"))
        let converted = makeSession([NoteBlock(.paragraph, text: rich)])
        let richID = converted.page.blocks[0].id
        converted.setSelection(.caret(NotePosition(richID, 5)))
        converted.turnInto([richID], conversion: .code)
        converted.updateBlock(richID) { $0.text = NoteText("line 1\nline 2") }
        converted.turnInto([richID], conversion: .text)
        expectOutline(converted.page, "p line 1⏎line 2", "code becomes text with its line breaks")
    }

    @Test func bulletsDropCheckmarksAndListStarts() {
        let props = makeSession([todo("Task", checked: true), numbered("Seven", start: 7), para("Idea")])
        props.turnInto([props.id("Task"), props.id("Seven"), props.id("Idea")], conversion: .bulletedList)
        #expect(props.page.blocks.allSatisfy { $0.kind == .bulletedItem && !$0.props.checked && $0.props.listStart == nil }, "bullets drop checkmarks and list starts")
    }

    @Test func convertingToACalloutAddsItsDefaultIcon() {
        let props = makeSession([todo("Task", checked: true), numbered("Seven", start: 7), para("Idea")])
        props.turnInto([props.id("Task"), props.id("Seven"), props.id("Idea")], conversion: .bulletedList)
        props.turnInto([props.id("Idea")], conversion: .callout)
        #expect(props.page.block(props.id("Idea"))?.props.icon == "💡", "callouts get an icon")
        #expect(props.page.block(props.id("Idea"))?.conversion == .callout, "the style reads back")
    }

    @Test func applyingABlockShortcutRemovesItsTriggerAndMovesTheCaret() {
        let session = makeSession([para("# Title")])
        let id = session.page.blocks[0].id
        session.setSelection(.caret(NotePosition(id, 2)))
        session.applyBlockShortcut(id, prefixLength: 2, conversion: .heading(1))
        expectOutline(session.page, "h1 Title", "the trigger characters disappear")
        #expect(session.selection == .caret(NotePosition(id, 0)), "the caret moves back with them")
    }

    @Test func aDividerShortcutMovesTheCaretBelowTheDivider() {
        let rule = makeSession([para("---")])
        let ruleID = rule.page.blocks[0].id
        rule.applyBlockShortcut(ruleID, prefixLength: 3, conversion: .divider)
        expectOutline(rule.page, "divider\np", "--- makes a divider and a fresh line")
        #expect(rule.selection.caret?.block == rule.page.blocks[1].id, "typing continues below the divider")
    }

    @Test func aDividerShortcutKeepsTextAfterTheTrigger() {
        let ruleWithText = makeSession([para("---keep")])
        ruleWithText.applyBlockShortcut(ruleWithText.page.blocks[0].id, prefixLength: 3, conversion: .divider)
        expectOutline(ruleWithText.page, "divider\np keep", "a divider shortcut before text keeps the text")
    }
}
