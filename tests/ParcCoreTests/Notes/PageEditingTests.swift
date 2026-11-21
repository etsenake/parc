import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageEditingTests: NoteFixtures {
    @Test func enterSplitsAndContinues() {
        let session = makeSession([NoteBlock(.paragraph, text: NoteText(pieces: [("Hello ", .plain), ("world", boldMarks)]))])
        let first = session.page.blocks[0].id
        let fresh = session.splitBlock(at: NotePosition(first, 8))!
        expectOutline(session.page, "p Hello wo\np rld")
        #expect(session.page.block(fresh)!.text.marks(at: 0).bold, "the split tail keeps its bold")
        #expect(session.selection == .caret(NotePosition(fresh, 0)), "caret lands at the start of the new block")

        let headings = makeSession([heading(2, "Title"), heading(1, "Split me")])
        headings.splitBlock(at: NotePosition(headings.id("Title"), 5))
        headings.splitBlock(at: NotePosition(headings.id("Split me"), 5))
        expectOutline(headings.page, "h2 Title\np\nh1 Split\np  me", "Enter after or inside a heading continues as text")

        let lists = makeSession([todo("Done", checked: true), numbered("One"), bullet("Dot")])
        lists.splitBlock(at: NotePosition(lists.id("Done"), 4))
        lists.splitBlock(at: NotePosition(lists.id("One"), 3))
        lists.splitBlock(at: NotePosition(lists.id("Dot"), 3))
        expectOutline(lists.page, "done Done\ntodo\nol One\nol\nul Dot\nul", "lists continue with the same kind, and new to-dos start unchecked")

        let coloured = makeSession([NoteBlock(.paragraph, text: "Redden", color: .background(.red))])
        let colouredID = coloured.page.blocks[0].id
        let tail = coloured.splitBlock(at: NotePosition(colouredID, 3))!
        let end = coloured.splitBlock(at: NotePosition(tail, 3))!
        #expect(coloured.page.block(tail)!.color == .background(.red), "a mid-block split keeps the colour on both halves")
        #expect(coloured.page.block(end)!.color == nil, "a fresh empty line after a coloured block starts plain")

        let parent = makeSession([bullet("Parent", [bullet("Child")])])
        parent.splitBlock(at: NotePosition(parent.id("Parent"), 6))
        expectOutline(parent.page, "ul Parent\n  ul\n  ul Child", "Enter at the end of a parent opens a first child")
    }

    @Test func enterOnEmptyBlocks() {
        let top = makeSession([bullet("a"), bullet()])
        let empty = top.page.blocks[1].id
        top.setSelection(.caret(NotePosition(empty, 0)))
        #expect(top.splitBlock(at: NotePosition(empty, 0)) == empty, "Enter on an empty item reports the same block")
        expectOutline(top.page, "ul a\np", "an empty top-level list item turns into text")

        let underText = makeSession([block(.paragraph, "lead", [bullet()])])
        underText.splitBlock(at: NotePosition(underText.page.blocks[0].children[0].id, 0))
        expectOutline(underText.page, "p lead\nul", "an empty item nested under text outdents first")
        let textParent = makeSession([block(.heading, "Head", [para("kid")]) { $0.level = 2 }])
        textParent.splitBlock(at: NotePosition(textParent.id("Head"), 4))
        expectOutline(textParent.page, "h2 Head\n  p\n  p kid", "Enter at the end of a heading with children opens a first child")

        let nested = makeSession([bullet("a", [bullet("b"), bullet(), bullet("c")])])
        let blank = nested.page.blocks[0].children[1].id
        nested.splitBlock(at: NotePosition(blank, 0))
        expectOutline(nested.page, "ul a\n  ul b\nul\n  ul c", "the first Enter outdents a nested empty item and adopts what follows")
        #expect(nested.selection == .caret(NotePosition(blank, 0)), "the caret stays in the outdented item")
        nested.splitBlock(at: NotePosition(blank, 0))
        expectOutline(nested.page, "ul a\n  ul b\nul\n  ul\n  ul c", "an empty item with children opens a first child instead of converting")

        let inCallout = makeSession([callout("Note", [bullet("x"), bullet()])])
        inCallout.splitBlock(at: NotePosition(inCallout.page.blocks[0].children[1].id, 0))
        expectOutline(inCallout.page, "callout Note\n  ul x\n  p", "an empty item inside a callout turns into text in place")

        let toggles = makeSession([toggle("", expanded: true), quote()])
        toggles.splitBlock(at: NotePosition(toggles.page.blocks[0].id, 0))
        toggles.splitBlock(at: NotePosition(toggles.page.blocks[1].id, 0))
        expectOutline(toggles.page, "p\np", "empty toggles and quotes turn into text")

        let paragraphs = makeSession([para(), heading(1)])
        paragraphs.splitBlock(at: NotePosition(paragraphs.page.blocks[0].id, 0))
        paragraphs.splitBlock(at: NotePosition(paragraphs.page.blocks[2].id, 0))
        expectOutline(paragraphs.page, "p\np\nh1\np", "empty text and headings just open a new line")
    }

    @Test func enterAtStart() {
        let session = makeSession([numbered("First", start: 5), numbered("Second")])
        let first = session.id("First")
        let above = session.splitBlock(at: NotePosition(first, 0))!
        expectOutline(session.page, "ol@5\nol First\nol Second", "Enter at the start inserts an item above and hands it the list start")
        #expect(session.selection == .caret(NotePosition(first, 0)), "the caret stays with the text")
        #expect(session.page.numberLabel(for: above) == "5.", "the new first item keeps the run's number")
        #expect(session.page.numberLabel(for: first) == "6.", "the old first item counts on")

        let headed = makeSession([heading(1, "Big"), toggle("Fold", expanded: true, [para("inside")])])
        headed.splitBlock(at: NotePosition(headed.id("Big"), 0))
        headed.splitBlock(at: NotePosition(headed.id("Fold"), 0))
        expectOutline(headed.page, "p\nh1 Big\ntoggle\ntoggle Fold\n  p inside", "headings get a text line above; toggles get a toggle above")
    }

    @Test func theSiblingToggleStartsClosedLikeItsNeighbour() {
        let open = makeSession([toggle("Open", expanded: true, [para("kid")]), toggle("Shut", expanded: false, [para("hidden")])])
        open.splitBlock(at: NotePosition(open.id("Open"), 4))
        let shut = open.id("Shut")
        let sibling = open.splitBlock(at: NotePosition(shut, 4))!
        expectOutline(open.page, "toggle Open\n  p\n  p kid\ntoggle- Shut\n  p hidden\ntoggle-", "open toggles grow a child; closed ones a closed sibling")
        #expect(open.page.block(sibling)!.isCollapsed, "the sibling toggle starts closed like its neighbour")

        let headingToggle = makeSession([toggleHeading(2, "Section", expanded: true), toggleHeading(2, "Closed", expanded: false, [para("x")])])
        headingToggle.splitBlock(at: NotePosition(headingToggle.id("Section"), 7))
        headingToggle.splitBlock(at: NotePosition(headingToggle.id("Closed"), 6))
        expectOutline(headingToggle.page, "th2 Section\n  p\nth2- Closed\n  p x\np", "toggle headings open a child when open and a text line when closed")
    }

    @Test func enterInContainers2() {
        let boxes = makeSession([callout("Tip"), callout(), quote("Said")])
        boxes.splitBlock(at: NotePosition(boxes.id("Tip"), 1))
        boxes.splitBlock(at: NotePosition(boxes.page.blocks[1].id, 0))
        boxes.splitBlock(at: NotePosition(boxes.id("Said"), 4))
        expectOutline(boxes.page, "callout T\n  p ip\ncallout\n  p\nquote Said\np", "callouts keep new lines inside; quotes hand off to text")
    }

    @Test func theCaretMovesToTheNewLine() {
        let session = makeSession([image(caption: "A cat"), code("let x = 1")])
        let picture = session.page.blocks[0].id
        let fresh = session.splitBlock(at: NotePosition(picture, 2, field: .caption))!
        expectOutline(session.page, "image [A cat]\np\ncode let x = 1", "Enter in a caption opens a line below the media")
        #expect(session.selection == .caret(NotePosition(fresh, 0)), "the caret moves to the new line")
        #expect(session.splitBlock(at: NotePosition(session.id("let x = 1"), 3)) == nil, "code keeps Enter for itself")
    }

    @Test func enterInCaptionsAndSelections2() {
        let range = makeSession([para("Hello there"), para("General")])
        range.setSelection(.text(anchor: NotePosition(range.id("Hello there"), 5), head: NotePosition(range.id("General"), 3)))
        range.insertBlockBreak()
        expectOutline(range.page, "p Hello\np eral", "Enter over a selection deletes it and splits")
        range.undo()
        expectOutline(range.page, "p Hello there\np General", "one undo puts the selection back")
    }

    @Test func theCaretStaysAtTheStart() {
        let session = makeSession([bullet("a", [bullet("b")])])
        let b = session.id("b")
        session.mergeBackward(b)
        expectOutline(session.page, "ul a\n  p b", "the first Backspace turns the item into text in place")
        #expect(session.selection == .caret(NotePosition(b, 0)), "the caret stays at the start")
        session.mergeBackward(b)
        expectOutline(session.page, "ul a\np b", "the second Backspace outdents")
        session.mergeBackward(b)
        expectOutline(session.page, "ul ab", "the third Backspace merges into the line above")
        #expect(session.selection == .caret(NotePosition(session.id("ab"), 1)), "the caret sits at the join")
    }

    @Test func backspaceAtStart2() {
        let heading = makeSession([para("x"), NoteBlock.heading(1, "Head")])
        heading.mergeBackward(heading.id("Head"))
        expectOutline(heading.page, "p x\np Head", "Backspace turns headings into text first")
    }

    @Test func mergingKeepsBothSidesMarks() {
        let styled = makeSession([NoteBlock(.paragraph, text: NoteText(pieces: [("bold", boldMarks)])), para("plain")])
        styled.mergeBackward(styled.id("plain"))
        let merged = styled.page.blocks[0].text
        #expect(merged.string == "boldplain" && merged.marks(at: 0).bold && !merged.marks(at: 4).bold, "merging keeps both sides' marks")
    }

    @Test func backspaceAtStart4() {
        let middle = makeSession([toggle("T", expanded: true, [para("one"), para("two")])])
        middle.mergeBackward(middle.id("one"))
        expectOutline(middle.page, "toggle T\np one\n  p two", "a nested line outdents first and adopts the lines after it")
        middle.mergeBackward(middle.id("one"))
        expectOutline(middle.page, "toggle Tone\n  p two", "then merges, and its children stay nested")
    }

    @Test func backspaceAtStart5() {
        let underText = makeSession([block(.paragraph, "lead", [para("kid")])])
        underText.mergeBackward(underText.id("kid"))
        expectOutline(underText.page, "p lead\np kid", "Backspace outdents a line nested under text")
        underText.mergeBackward(underText.id("kid"))
        expectOutline(underText.page, "p leadkid", "then merges it into the line above")
    }

    @Test func backspaceAtTheVeryStartDoesNothing() {
        let first = makeSession([para("Only")])
        #expect(!first.mergeBackward(first.id("Only")), "Backspace at the very start does nothing")
    }

    @Test func nonEmptyCodeIgnoresBackspaceAtItsStart() {
        let codeBlocks = makeSession([para("x"), code("body"), code()])
        #expect(!codeBlocks.mergeBackward(codeBlocks.id("body")), "non-empty code ignores Backspace at its start")
        codeBlocks.mergeBackward(codeBlocks.page.blocks[2].id)
        expectOutline(codeBlocks.page, "p x\ncode body\np", "an empty code block turns into text")
    }

    @Test func backspaceNeverMergesAcrossColumns() {
        let columnsPage = makeSession([columns([[para("left")], [para("right")]])])
        #expect(!columnsPage.mergeBackward(columnsPage.id("right")), "Backspace never merges across columns")
        expectOutline(columnsPage.page, "columns\n  column\n    p left\n  column\n    p right")
    }

    @Test func theCaretSitsAtTheJoinInTheTitle() {
        let collapsed = makeSession([toggle("Fold", expanded: false, [para("hidden")]), para("after")])
        collapsed.mergeBackward(collapsed.id("after"))
        expectOutline(collapsed.page, "toggle- Foldafter\n  p hidden", "merging into a closed toggle joins its title, not a hidden child")
        #expect(collapsed.selection == .caret(NotePosition(collapsed.id("Foldafter"), 4)), "the caret sits at the join in the title")
    }

    @Test func backspaceAroundSpecialNeighbours() {
        let session = makeSession([image(), para("text"), divider(), para()])
        let picture = session.page.blocks[0].id, rule = session.page.blocks[2].id
        session.mergeBackward(session.id("text"))
        #expect(session.selection == .blocks([picture]), "Backspace after media selects it")
        expectOutline(session.page, "image\np text\ndivider\np")
        session.mergeBackward(session.page.blocks[3].id)
        expectOutline(session.page, "image\np text\ndivider", "an empty line after a divider goes away")
        #expect(session.selection == .blocks([rule]), "and the divider is selected")
    }

    @Test func caretAtTheJoin() {
        let session = makeSession([para("Join"), heading(1, "Heading")])
        session.mergeForward(session.id("Join"))
        expectOutline(session.page, "p JoinHeading", "Delete at the end pulls the next block's text up")
        #expect(session.selection == .caret(NotePosition(session.page.blocks[0].id, 4)), "caret at the join")
    }

    @Test func caretAtTheStartOfTheNextBlock() {
        let empty = makeSession([para(), heading(1, "Keep")])
        empty.mergeForward(empty.page.blocks[0].id)
        expectOutline(empty.page, "h1 Keep", "Delete in an empty line removes it so the next block keeps its type")
        #expect(empty.selection == .caret(NotePosition(empty.id("Keep"), 0)), "caret at the start of the next block")

        let nested = makeSession([bullet("A", [bullet("B", [bullet("B1")]), bullet("C")])])
        nested.mergeForward(nested.id("A"))
        expectOutline(nested.page, "ul AB\n  ul B1\n  ul C", "merging a first child lifts its children into its place")

        let divided = makeSession([para("x"), divider(), para(), divider()])
        let firstRule = divided.page.blocks[1].id, secondRule = divided.page.blocks[3].id
        divided.mergeForward(divided.id("x"))
        #expect(divided.selection == .blocks([firstRule]), "Delete before a divider selects it")
        divided.mergeForward(divided.page.blocks[2].id)
        expectOutline(divided.page, "p x\ndivider\ndivider", "an empty line before a divider disappears")
        #expect(divided.selection == .blocks([secondRule]), "and the divider is selected")
    }

    @Test func textMergedIntoCodeTurnsPlain() {
        let codePage = makeSession([code("a = 1"), NoteBlock(.paragraph, text: NoteText(pieces: [("b", boldMarks)]))])
        codePage.mergeForward(codePage.id("a = 1"))
        #expect(codePage.page.blocks[0].text.isPlain && codePage.page.blocks[0].text.string == "a = 1b", "text merged into code turns plain")
    }

    @Test func deleteAtEnd4() {
        let columnsPage = makeSession([columns([[para("left")], [para("right")]])])
        columnsPage.mergeForward(columnsPage.id("left"))
        expectOutline(columnsPage.page, "columns\n  column\n    p left\n  column\n    p right", "Delete never merges across columns")
    }

    @Test func backspaceRemovesAWholeEmojiWithItsSkinTone() {
        let session = makeSession([para("a👍🏽b")])
        let id = session.page.blocks[0].id
        session.setSelection(.caret(NotePosition(id, 5)))
        session.deleteBackward()
        #expect(session.page.blocks[0].text.string == "ab", "Backspace removes a whole emoji with its skin tone")
        #expect(session.selection == .caret(NotePosition(id, 1)), "caret steps back over it")
        session.deleteForward()
        #expect(session.page.blocks[0].text.string == "a", "Delete removes the next character")
    }

    @Test func backspaceInAnEmptyCaptionStepsOutToThe() {
        let caption = makeSession([image(caption: "")])
        let picture = caption.page.blocks[0].id
        caption.addCaption(to: picture)
        caption.deleteBackward()
        #expect(caption.selection == .blocks([picture]), "Backspace in an empty caption steps out to the block")
    }

    @Test func aListItemIndentsUnderItsSibling() {
        let session = makeSession([bullet("a"), bullet("b"), para("p"), bullet("c")])
        #expect(session.indent([session.id("b")]), "a list item indents under its sibling")
        expectOutline(session.page, "ul a\n  ul b\np p\nul c")
        #expect(session.indent([session.id("c")]), "a list item nests under a paragraph")
        expectOutline(session.page, "ul a\n  ul b\np p\n  ul c")
        #expect(!session.indent([session.id("a")]), "the first block has nothing to nest under")
    }

    @Test func theCaretSurvivesTheMove() {
        let shut = makeSession([toggle("Fold", expanded: false, [para("old")]), para("new")])
        shut.setSelection(.caret(NotePosition(shut.id("new"), 1)))
        shut.indent([shut.id("new")])
        expectOutline(shut.page, "toggle Fold\n  p old\n  p new", "nesting under a closed toggle opens it and lands last")
        #expect(shut.selection == .caret(NotePosition(shut.id("new"), 1)), "the caret survives the move")
    }

    @Test func indentRules3() {
        let run = makeSession([bullet("a"), bullet("b", [bullet("b1")]), bullet("c"), bullet("d")])
        run.indent([run.id("b"), run.id("b1"), run.id("c")])
        expectOutline(run.page, "ul a\n  ul b\n    ul b1\n  ul c\nul d", "a selected run nests together and children ride along")
    }

    @Test func indentRules4() {
        let mixed = makeSession([bullet("a"), bullet("b"), para("x"), bullet("c"), bullet("d")])
        mixed.indent([mixed.id("b"), mixed.id("d")])
        expectOutline(mixed.page, "ul a\n  ul b\np x\nul c\n  ul d", "separate runs each nest under their own sibling")
    }

    @Test func aParagraphNestsUnderTheParagraphBeforeIt() {
        let text = makeSession([para("one"), para("two"), heading(2, "Head"), para("three")])
        #expect(text.indent([text.id("two")]), "a paragraph nests under the paragraph before it")
        #expect(text.indent([text.id("three")]), "and under a plain heading")
        expectOutline(text.page, "p one\n  p two\nh2 Head\n  p three", "text blocks hold children like Notion")
    }

    @Test func theFirstBlockOfAColumnCanTJump() {
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

    @Test func outdentRules3() {
        let shut = makeSession([bullet("a", [toggle("t", expanded: false, [para("inside")]), bullet("after")])])
        shut.outdent([shut.id("t")])
        expectOutline(shut.page, "ul a\ntoggle t\n  p inside\n  ul after", "adopting into a closed toggle opens it")
    }

    @Test func shiftTabNeverPullsABlockOutOfIts() {
        let columnsPage = makeSession([columns([[bullet("x", [bullet("y")])], [para("z")]])])
        #expect(!columnsPage.outdent([columnsPage.id("x")]), "Shift-Tab never pulls a block out of its column")
        #expect(columnsPage.outdent([columnsPage.id("y")]), "nested blocks inside a column still outdent")
        expectOutline(columnsPage.page, "columns\n  column\n    ul x\n    ul y\n  column\n    p z", "and stay inside the column")
    }

    @Test func outdentRules5() {
        let multi = makeSession([bullet("a", [bullet("a1")]), bullet("b", [bullet("b1"), bullet("b2")])])
        multi.outdent([multi.id("a1"), multi.id("b1")])
        expectOutline(multi.page, "ul a\nul a1\nul b\nul b1\n  ul b2", "outdent works across different parents at once")
    }

    @Test func outdentRules6() {
        let runs = makeSession([bullet("p", [bullet("1"), bullet("2"), bullet("3")])])
        runs.outdent([runs.id("1"), runs.id("3")])
        expectOutline(runs.page, "ul p\nul 1\n  ul 2\nul 3", "gapped selections outdent in order")
    }

    @Test func turnIntoRules1() {
        let session = makeSession([bullet("Parent", [bullet("kid")])])
        let parent = session.id("Parent")
        session.turnInto([parent], kind: .paragraph)
        expectOutline(session.page, "p Parent\n  ul kid", "text keeps its children")
        session.turnInto([parent], conversion: .heading(2))
        expectOutline(session.page, "h2 Parent\n  ul kid", "and so do plain headings")
        session.turnInto([parent], conversion: .code)
        expectOutline(session.page, "code Parent\nul kid", "code can't hold children, so they move out after it")
    }

    @Test func turnIntoRules2() {
        let nestedTargets = makeSession([bullet("P", [bullet("C", [bullet("G")]), bullet("D")]), bullet("Q")])
        nestedTargets.turnInto([nestedTargets.id("P"), nestedTargets.id("C"), nestedTargets.id("Q")], kind: .paragraph)
        expectOutline(nestedTargets.page, "p P\n  p C\n    ul G\n  ul D\np Q", "turning nested blocks into text keeps every level")
    }

    @Test func turnIntoRules3() {
        let toToggle = makeSession([bullet("Parent", [bullet("kid")])])
        toToggle.turnInto([toToggle.id("Parent")], conversion: .toggle)
        expectOutline(toToggle.page, "toggle Parent\n  ul kid", "a toggle keeps the children inside, open")
    }

    @Test func plainHeadingsNeverHideChildren() {
        let fold = makeSession([toggle("Fold", expanded: false, [para("kid")])])
        fold.turnInto([fold.id("Fold")], conversion: .heading(2))
        expectOutline(fold.page, "th2- Fold\n  p kid", "a toggle turned into a heading becomes a toggle heading and stays closed")
        fold.turnInto([fold.id("Fold")], conversion: .heading(1))
        expectOutline(fold.page, "h1 Fold\n  p kid", "a toggle heading turned into a plain heading keeps its children, always shown")
        #expect(fold.page.blocks[0].showsChildren, "plain headings never hide children")
        fold.turnInto([fold.id("Fold")], conversion: .toggleHeading(3))
        expectOutline(fold.page, "th3 Fold\n  p kid", "a new toggle heading starts open")
    }

    @Test func codeFlattensMarksAndMentionsToPlainText() {
        var atomMarks = NoteMarks.plain
        atomMarks.atom = .equation("x^2")
        let rich = NoteText(pieces: [("Sum ", boldMarks)]) + NoteText.atom(.equation("x^2"))
        let converted = makeSession([NoteBlock(.paragraph, text: rich)])
        let richID = converted.page.blocks[0].id
        converted.setSelection(.caret(NotePosition(richID, 5)))
        converted.turnInto([richID], conversion: .code)
        #expect(converted.page.blocks[0].text.isPlain && converted.page.blocks[0].text.string == "Sum x^2", "code flattens marks and mentions to plain text")
        #expect(converted.selection == .caret(NotePosition(richID, 5)), "the caret stays put")
        converted.updateBlock(richID) { $0.text = NoteText("line 1\nline 2") }
        converted.turnInto([richID], conversion: .text)
        expectOutline(converted.page, "p line 1⏎line 2", "code becomes text with its line breaks")
    }

    @Test func bulletsDropCheckmarksAndListStarts() {
        let props = makeSession([todo("Task", checked: true), numbered("Seven", start: 7), para("Idea")])
        props.turnInto([props.id("Task"), props.id("Seven"), props.id("Idea")], conversion: .bulletedList)
        #expect(props.page.blocks.allSatisfy { $0.kind == .bulletedItem && !$0.props.checked && $0.props.listStart == nil }, "bullets drop checkmarks and list starts")
        props.turnInto([props.id("Idea")], conversion: .callout)
        #expect(props.page.block(props.id("Idea"))?.props.icon == "💡", "callouts get an icon")
        #expect(props.page.block(props.id("Idea"))?.conversion == .callout, "the style reads back")
    }

    @Test func theCaretMovesBackWithThem() {
        let session = makeSession([para("# Title")])
        let id = session.page.blocks[0].id
        session.setSelection(.caret(NotePosition(id, 2)))
        session.applyBlockShortcut(id, prefixLength: 2, conversion: .heading(1))
        expectOutline(session.page, "h1 Title", "the trigger characters disappear")
        #expect(session.selection == .caret(NotePosition(id, 0)), "the caret moves back with them")
    }

    @Test func typingContinuesBelowTheDivider() {
        let rule = makeSession([para("---")])
        let ruleID = rule.page.blocks[0].id
        rule.applyBlockShortcut(ruleID, prefixLength: 3, conversion: .divider)
        expectOutline(rule.page, "divider\np", "--- makes a divider and a fresh line")
        #expect(rule.selection.caret?.block == rule.page.blocks[1].id, "typing continues below the divider")
    }

    @Test func blockShortcuts3() {
        let ruleWithText = makeSession([para("---keep")])
        ruleWithText.applyBlockShortcut(ruleWithText.page.blocks[0].id, prefixLength: 3, conversion: .divider)
        expectOutline(ruleWithText.page, "divider\np keep", "a divider shortcut before text keeps the text")
    }

    @Test func theCaretRidesAlong() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1"), bullet("b2")]), para("c")])
        session.setSelection(.caret(NotePosition(session.id("c"), 1)))
        session.moveBlocks([session.id("c")], .up)
        expectOutline(session.page, "p a\np c\nul b\n  ul b1\n  ul b2", "moving up swaps with the previous sibling and its children")
        #expect(session.selection == .caret(NotePosition(session.id("c"), 1)), "the caret rides along")
        session.moveBlocks([session.id("b1")], .up)
        expectOutline(session.page, "p a\np c\nul b1\nul b\n  ul b2", "the first child moves up out of its parent")
        session.moveBlocks([session.id("b2")], .down)
        expectOutline(session.page, "p a\np c\nul b1\nul b\nul b2", "the last child moves down out of its parent")
        session.moveBlocks([session.id("a"), session.id("c")], .down)
        expectOutline(session.page, "ul b1\np a\np c\nul b\nul b2", "a selection moves together")
    }

    @Test func moveRules2() {
        let columnsPage = makeSession([columns([[para("x"), para("y")], [para("z")]])])
        columnsPage.moveBlocks([columnsPage.id("x")], .up)
        columnsPage.moveBlocks([columnsPage.id("y")], .down)
        expectOutline(columnsPage.page, "columns\n  column\n    p x\n    p y\n  column\n    p z", "moves stop at column edges")
    }

    @Test func moveRules3() {
        let refused = makeSession([para("a"), para("b"), code("c")])
        refused.moveBlocks([refused.id("b")], to: .firstChild(of: refused.id("a")))
        expectOutline(refused.page, "p a\n  p b\ncode c", "blocks can be moved inside a paragraph")
        refused.moveBlocks([refused.id("b")], to: .firstChild(of: refused.id("c")))
        expectOutline(refused.page, "p a\n  p b\ncode c", "but never inside code")
        refused.moveBlocks([refused.id("a")], to: .before(refused.id("a")))
        expectOutline(refused.page, "p a\n  p b\ncode c", "a block can't move relative to itself")
        let shut = makeSession([toggle("t", expanded: false), para("x")])
        shut.moveBlocks([shut.id("x")], to: .lastChild(of: shut.id("t")))
        expectOutline(shut.page, "toggle t\n  p x", "dropping into a closed toggle opens it")
    }

    @Test func plainTextPagesNeverNest() {
        let flat = makeSession([para("one"), para("two"), bullet("a"), bullet("b")])
        flat.isFlat = true
        #expect(!flat.indent([flat.id("b")]), "plain-text pages never nest")
        flat.moveBlocks([flat.id("two")], to: .firstChild(of: flat.id("a")))
        flat.placeBeside([flat.id("one")], target: flat.id("two"), side: .right)
        expectOutline(flat.page, "p one\np two\nul a\nul b", "drops never nest or make columns in a plain-text page")
        flat.moveBlocks([flat.id("b")], to: .before(flat.id("one")))
        expectOutline(flat.page, "ul b\np one\np two\nul a", "plain moves still work")
    }

    @Test func andNeverReshuffleLevelsEither() {
        let nested = makeSession([bullet("a", [bullet("b")])])
        nested.isFlat = true
        #expect(!nested.outdent([nested.id("b")]), "and never reshuffle levels either")
    }

    @Test func theCopiesAreSelected() {
        let session = makeSession([bullet("a", [bullet("a1")]), para("b")])
        let copies = session.duplicateBlocks([session.id("a"), session.id("a1")])
        expectOutline(session.page, "ul a\n  ul a1\nul a\n  ul a1\np b", "duplicate copies the block with its children right after")
        #expect(session.selection == .blocks(copies), "the copies are selected")
        #expect(Set(session.page.documentOrder()).count == 5, "every copy gets fresh ids")
    }

    @Test func theCaretLandsAtTheEndOfTheBlock() {
        let removal = makeSession([para("keep"), image(), bullet("x", [bullet("y")]), para("tail")])
        removal.deleteBlocks([removal.page.blocks[1].id, removal.id("x")])
        expectOutline(removal.page, "p keep\np tail", "deleting removes blocks with their children")
        #expect(removal.selection == .caret(NotePosition(removal.id("keep"), 4)), "the caret lands at the end of the block above")
    }

    @Test func withNothingAboveTheNextBlockIsSelected() {
        let leading = makeSession([para("gone"), image()])
        leading.deleteBlocks([leading.id("gone")])
        #expect(leading.selection == .blocks([leading.page.blocks[0].id]), "with nothing above, the next block is selected")
    }

    @Test func withTheCaretInIt() {
        let all = makeSession([para("one"), para("two")])
        all.deleteBlocks(all.page.blocks.map(\.id))
        expectOutline(all.page, "p", "deleting everything leaves one empty line")
        #expect(all.selection == .caret(NotePosition(all.page.blocks[0].id, 0)), "with the caret in it")
        all.undo()
        expectOutline(all.page, "p one\np two", "and one undo brings it all back")
    }

    @Test func duplicateAndDelete5() {
        let columnsPage = makeSession([columns([[para("x")], [para("y")]]), para("z")])
        columnsPage.deleteBlocks([columnsPage.id("y")])
        expectOutline(columnsPage.page, "p x\np z", "deleting the last block of a column folds the columns away")
    }

    @Test func theCaretFollowsTheTypedLetter() {
        let typed = makeSession([para("a"), image(), para("c")])
        typed.setSelection(.blocks([typed.page.blocks[1].id]))
        typed.insertText(NoteText("Z"))
        expectOutline(typed.page, "p a\np Z\np c", "typing over selected blocks replaces them with a text line")
        #expect(typed.selection == .caret(NotePosition(typed.id("Z"), 1)), "the caret follows the typed letter")
    }

    @Test func withJustACaretTheBlockGetsTheColour() {
        let session = makeSession([para("Hello world"), divider(), para("Other")])
        let hello = session.id("Hello world"), rule = session.page.blocks[1].id
        session.setSelection(.caret(NotePosition(hello, 3)))
        session.setColor(.background(.yellow))
        #expect(session.page.block(hello)!.color == .background(.yellow), "with just a caret, the block gets the colour")
        session.setSelection(.text(anchor: NotePosition(hello, 0), head: NotePosition(hello, 5)))
        session.setColor(.text(.red))
        let text = session.page.block(hello)!.text
        #expect(text.marks(at: 0).color == .text(.red) && text.marks(at: 6).color == nil, "a text selection colours just those letters")
        #expect(session.page.block(hello)!.color == .background(.yellow), "the block colour stays")
        session.setColor(.text(.blue), in: .blocks([rule, session.id("Other")]))
        #expect(session.page.block(rule)!.color == nil, "dividers don't take colour")
        #expect(session.page.block(session.id("Other"))!.color == .text(.blue), "selected blocks take the colour")
        session.setColor(nil, in: .blocks([hello]))
        #expect(session.page.block(hello)!.color == nil, "Default clears the block colour")

        let linked = makeSession([NoteBlock(.paragraph, text: NoteText(pieces: [("see ", .plain), ("the site", marks { $0.link = "https://a" }), (" now", .plain)]))])
        let linkedID = linked.page.blocks[0].id
        linked.setSelection(.caret(NotePosition(linkedID, 6)))
        linked.setLink(nil)
        #expect(linked.page.blocks[0].text.runs().allSatisfy { $0.marks.link == nil }, "removing a link at a caret clears the whole link")
        linked.setSelection(.text(anchor: NotePosition(linkedID, 0), head: NotePosition(linkedID, 3)))
        linked.setLink("https://b")
        #expect(linked.page.blocks[0].text.linkRange(at: 1) == 0..<3, "linking a selection marks just that range")
    }

    @Test func theCaretFollowsTheTyping() {
        let grid = makeSession([table([["a", "b"], ["c", "d"]])])
        let gridID = grid.page.blocks[0].id
        grid.setSelection(.cells(table: gridID, anchor: NoteTableCell(row: 1, column: 1), head: NoteTableCell(row: 0, column: 0)))
        grid.insertText(NoteText("z"))
        expectOutline(grid.page, "table z|/|", "typing over selected cells clears them and types into the first")
        #expect(grid.selection == .caret(NotePosition(gridID, 1, field: .cell(row: 0, column: 0))), "the caret follows the typing")
        #expect(grid.undoDepth == 1, "and it's one step")
    }

    @Test func numberedLabels() {
        let page = NotePage(blocks: [
            numbered("one"), numbered("two", [numbered("a", [numbered("i", [numbered("deep")]), numbered("ii")]), numbered("b")]),
            numbered("three"), para("break"), numbered("again"), bullet("dot"), numbered("five", start: 5), numbered("six"),
        ])
        func label(_ text: String) -> String? {
            page.numberLabel(for: page.allBlocks().first { $0.text.plainText == text }!.id)
        }
        #expect(label("one") == "1.", "lists start at 1")
        #expect(label("three") == "3.", "children don't interrupt the count")
        #expect(label("a") == "a.", "the second level uses letters")
        #expect(label("b") == "b.", "letters count on")
        #expect(label("i") == "i.", "the third level uses roman numerals")
        #expect(label("ii") == "ii.", "roman numerals count on")
        #expect(label("deep") == "1.", "the fourth level wraps back to numbers")
        #expect(label("again") == "1.", "a non-numbered block restarts the count")
        #expect(label("five") == "5.", "a list start is honoured")
        #expect(label("six") == "6.", "and counted on from")
        #expect(label("dot") == nil, "bullets have no number")
        #expect(NoteListNumber(value: 27, level: 1).label == "aa.", "letters roll over like spreadsheet columns")
        #expect(NoteListNumber(value: 1994, level: 2).label == "mcmxciv.", "big roman numerals work")
        #expect(NoteListNumber(value: 0, level: 1).label == "0.", "letters fall back to digits below one")
    }

    @Test func toggles() {
        let session = makeSession([toggle("Fold", expanded: true, [para("inside")]), todo("a"), todo("b", checked: true)])
        let fold = session.id("Fold")
        session.setSelection(.caret(NotePosition(session.id("inside"), 2)))
        session.toggleExpanded(fold)
        #expect(session.page.block(fold)!.isCollapsed, "the toggle closes")
        #expect(session.selection == .caret(NotePosition(fold, 4)), "a caret inside a closing toggle moves to its title")
        session.setAllToggles(expanded: true)
        #expect(!session.page.block(fold)!.isCollapsed, "expand all opens it")
        session.toggleChecked([session.id("a"), session.id("b")])
        #expect(session.page.blocks[1].props.checked && session.page.blocks[2].props.checked, "mixed to-dos all get checked")
        session.toggleChecked([session.id("a"), session.id("b")])
        #expect(!session.page.blocks[1].props.checked && !session.page.blocks[2].props.checked, "then all get unchecked")
        session.setSelection(.blocks([fold]))
        session.toggleExpanded(fold)
        session.insertBlockBreak()
        #expect(!session.page.block(fold)!.isCollapsed, "Enter on selected closed toggles opens them")
    }
}
