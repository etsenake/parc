import Foundation

@main @MainActor
struct PageClipboardTests {
    static func main() {
        copyingText()
        copyingStructure()
        pastingInline()
        pastingBlocks()
        pastingIntoSpecialPlaces()
        pastingPlainText()
        pasteUndo()
        print("PageClipboardTests passed")
    }

    static func copyingText() {
        let session = makeSession([NoteBlock.heading(1, NoteText(pieces: [("Big ", .plain), ("bold", boldMarks), (" title", .plain)]))])
        let id = session.page.blocks[0].id
        let fragment = session.fragment(of: .text(anchor: NotePosition(id, 2), head: NotePosition(id, 8)))
        expectEqual(outline(fragment), "p g bold", "part of one block copies as plain inline text")
        expect(fragment[0].text.marks(at: 2).bold && !fragment[0].text.marks(at: 0).bold, "with its marks")
        expect(fragment[0].id != id, "under a fresh id")
        expect(session.fragment(of: .caret(NotePosition(id, 2))).isEmpty, "a caret copies nothing")

        let codePage = makeSession([code("let a = 1")])
        let codeFragment = codePage.fragment(of: .text(anchor: NotePosition(codePage.page.blocks[0].id, 4), head: NotePosition(codePage.page.blocks[0].id, 9)))
        expectEqual(outline(codeFragment), "p a = 1", "part of a code block copies as text")

        let captioned = makeSession([image(caption: "A small cat")])
        let picture = captioned.page.blocks[0].id
        let captionFragment = captioned.fragment(of: .text(anchor: NotePosition(picture, 2, field: .caption), head: NotePosition(picture, 7, field: .caption)))
        expectEqual(outline(captionFragment), "p small", "caption text copies as text")

        let grid = makeSession([table([["a", "b", "c"], ["d", "e", "f"]])])
        let tableID = grid.page.blocks[0].id
        let cells = grid.fragment(of: .cells(table: tableID, anchor: NoteTableCell(row: 1, column: 2), head: NoteTableCell(row: 0, column: 1)))
        expectEqual(outline(cells), "table b|c/e|f", "a cell selection copies as a smaller table")
        expect(cells[0].props.table?.headerRow == false, "without a header row")
    }

    static func copyingStructure() {
        let session = makeSession([
            para("Start here"),
            bullet("Parent", [bullet("Child", [bullet("Grandchild")]), bullet("Second child")]),
            toggle("Closed", expanded: false, [para("secret")]),
            para("End here"),
        ])
        let fragment = session.fragment(of: .text(anchor: NotePosition(session.id("End here"), 3), head: NotePosition(session.id("Start here"), 6)))
        expectEqual(outline(fragment), trimmed("""
            p here
            ul Parent
              ul Child
                ul Grandchild
              ul Second child
            toggle- Closed
              p secret
            p End
            """), "a cross-block copy keeps nesting, closed toggles keep their insides, and the ends are trimmed")

        let partial = session.fragment(of: .text(anchor: NotePosition(session.id("Child"), 2), head: NotePosition(session.id("Second child"), 6)))
        expectEqual(outline(partial), "ul ild\n  ul Grandchild\nul Second", "starting inside a nested list keeps the inner nesting")

        let blocks = session.fragment(of: .blocks([session.id("Parent"), session.id("Child")]))
        expectEqual(outline(blocks), "ul Parent\n  ul Child\n    ul Grandchild\n  ul Second child", "a block selection copies whole subtrees once")
        expect(Set(blocks[0].children.map(\.id)).isDisjoint(with: session.page.documentOrder()), "copies never reuse ids")

        let mixed = makeSession([para("abc"), image(caption: "pic"), divider(), table([["a", "b"]]), block(.bookmark) { $0.source = "https://b" },
                                 bullet("list", [bullet("nested")]), para("xyz")])
        let mixedIDs = Set(mixed.page.documentOrder())
        let mixedFragment = mixed.fragment(of: .text(anchor: NotePosition(mixed.id("abc"), 1), head: NotePosition(mixed.id("xyz"), 2)))
        expectEqual(outline(mixedFragment), "p bc\nimage [pic]\ndivider\ntable a|b\nbookmark\nul list\n  ul nested\np xy",
                    "a cross-block copy carries the non-text blocks between the ends, in order, with partial text at the ends")
        expect(mixedFragment.allSatisfy { block in !mixedIDs.contains(block.id) && block.children.allSatisfy { !mixedIDs.contains($0.id) } },
               "every copied block gets a fresh id")
        expectEqual(mixedFragment[4].props.source, "https://b", "copied blocks keep their properties")

        let columnsPage = makeSession([columns([[para("left")], [para("right")]])])
        let across = columnsPage.fragment(of: .text(anchor: NotePosition(columnsPage.id("left"), 1), head: NotePosition(columnsPage.id("right"), 2)))
        expectEqual(outline(across), "p eft\np ri", "copying across columns gives plain blocks")
    }

    static func pastingInline() {
        let session = makeSession([NoteBlock.heading(2, "Hello world")])
        let id = session.page.blocks[0].id
        session.setSelection(.caret(NotePosition(id, 5)))
        session.paste([NoteBlock.paragraph(NoteText(pieces: [(" big", boldMarks)]))])
        expectOutline(session.page, "h2 Hello big world", "inline text pastes into the heading without changing it")
        expectEqual(session.selection, .caret(NotePosition(id, 9)), "caret after the pasted text")
        expect(session.page.blocks[0].text.marks(at: 6).bold, "the pasted marks survive")

        let replace = makeSession([para("Hello cruel world")])
        let replaceID = replace.page.blocks[0].id
        replace.setSelection(.text(anchor: NotePosition(replaceID, 6), head: NotePosition(replaceID, 11)))
        replace.paste([NoteBlock.paragraph("kind")])
        expectOutline(replace.page, "p Hello kind world", "pasting over a selection replaces it")

        let styled = makeSession([NoteBlock(.paragraph, text: NoteText(pieces: [("bold", boldMarks)]))])
        let styledID = styled.page.blocks[0].id
        styled.setSelection(.caret(NotePosition(styledID, 2)))
        styled.paste([NoteBlock.paragraph("ER")])
        expect(styled.page.blocks[0].text.allHave(.bold, in: 0..<6), "plain text pasted inside bold text turns bold")

        let empty = makeSession([para("x"), para()])
        let blank = empty.page.blocks[1].id
        empty.setSelection(.caret(NotePosition(blank, 0)))
        empty.paste(empty.fragment(of: .blocks([empty.id("x")])).map { block in
            var copy = block
            copy.kind = .heading
            copy.props.level = 3
            return copy
        })
        expectOutline(empty.page, "p x\nh3 x", "a single copied block pasted on an empty line brings its type")
        expectEqual(empty.selection, .caret(NotePosition(blank, 1)), "and the caret ends after it")
    }

    static func pastingBlocks() {
        let clip = [heading(1, "One"), bullet("Two", [bullet("Two child")]), para("Three")]

        let empty = makeSession([para("before"), para(), para("after")])
        empty.setSelection(.caret(NotePosition(empty.page.blocks[1].id, 0)))
        empty.paste(clip)
        expectOutline(empty.page, "p before\nh1 One\nul Two\n  ul Two child\np Three\np after", "blocks replace an empty line")
        expectEqual(empty.selection, .caret(NotePosition(empty.id("Three"), 5)), "caret at the end of the pasted content")

        let middle = makeSession([para("Hello world")])
        middle.setSelection(.caret(NotePosition(middle.page.blocks[0].id, 6)))
        middle.paste(clip)
        expectOutline(middle.page, "p Hello One\nul Two\n  ul Two child\np Threeworld", "pasting mid-line joins the first and last pieces to the split line")
        expectEqual(middle.selection, .caret(NotePosition(middle.id("Threeworld"), 5)), "caret sits before the old tail")

        let nestedLast = makeSession([para("abcdef")])
        nestedLast.setSelection(.caret(NotePosition(nestedLast.page.blocks[0].id, 3)))
        nestedLast.paste([para("x"), bullet("list", [bullet("deep")])])
        expectOutline(nestedLast.page, "p abcx\nul list\n  ul deepdef", "the tail follows the last visible pasted line")

        let shutLast = makeSession([para("abcdef")])
        shutLast.setSelection(.caret(NotePosition(shutLast.page.blocks[0].id, 3)))
        shutLast.paste([para("x"), toggle("fold", expanded: false, [para("hidden")])])
        expectOutline(shutLast.page, "p abcx\ntoggle- folddef\n  p hidden", "a closed toggle takes the tail on its title")

        let start = makeSession([para("Keep me")])
        start.setSelection(.caret(NotePosition(start.page.blocks[0].id, 0)))
        start.paste(clip)
        expectOutline(start.page, "h1 One\nul Two\n  ul Two child\np Three\np Keep me", "pasting at the start goes above and leaves the line alone")

        let endOfLine = makeSession([bullet("Item")])
        endOfLine.setSelection(.caret(NotePosition(endOfLine.page.blocks[0].id, 4)))
        endOfLine.paste([code("x = 1"), para("after")])
        expectOutline(endOfLine.page, "ul Item\ncode x = 1\np after", "a code block never melts into the line it's pasted after")

        let parent = makeSession([bullet("Parent", [bullet("kid")])])
        parent.setSelection(.caret(NotePosition(parent.id("Parent"), 3)))
        parent.paste([para("A"), para("B")])
        expectOutline(parent.page, "ul ParA\n  p Bent\n  ul kid", "pasting into a parent keeps new lines above its children")

        let selected = makeSession([para("a"), image(), para("z")])
        selected.setSelection(.blocks([selected.page.blocks[1].id]))
        selected.paste([para("new")])
        expectOutline(selected.page, "p a\nimage\np new\np z", "with blocks selected, pasted blocks go after them")

        let nowhere = makeSession([para("only")])
        nowhere.setSelection(.none)
        nowhere.paste([para("tail")])
        expectOutline(nowhere.page, "p only\np tail", "with nothing selected, pasting appends")
    }

    static func pastingIntoSpecialPlaces() {
        let codePage = makeSession([code("start:")])
        let codeID = codePage.page.blocks[0].id
        codePage.setSelection(.caret(NotePosition(codeID, 6)))
        codePage.paste([heading(1, "Title"), bullet("item", [bullet("nested")]), table([["a", "b"]])])
        expectEqual(codePage.page.blocks[0].text.string, "start:Title\nitem\nnested\na\tb", "code takes everything as plain lines")
        expect(codePage.page.blocks[0].text.isPlain, "and stays plain")

        let captioned = makeSession([image(caption: "Hi")])
        let picture = captioned.page.blocks[0].id
        captioned.setSelection(.caret(NotePosition(picture, 2, field: .caption)))
        captioned.paste([NoteBlock.paragraph(NoteText(pieces: [(" there", italicMarks)]))])
        captioned.paste([para(" one"), para("two")])
        expectEqual(captioned.page.blocks[0].props.caption.plainText, "Hi there one two", "captions take text on one line")
        expect(captioned.page.blocks[0].props.caption.marks(at: 3).italic, "a single rich line keeps its marks in a caption")

        let grid = makeSession([table([["a", "b"], ["c", "d"]])])
        let tableID = grid.page.blocks[0].id
        grid.setSelection(.cells(table: tableID, anchor: NoteTableCell(row: 1, column: 1), head: NoteTableCell(row: 1, column: 1)))
        grid.paste([table([["1", "2"], ["3", "4"]])])
        expectOutline(grid.page, "table a|b|/c|1|2/|3|4", "a pasted table writes from the top-left cell and grows the grid")
        grid.setSelection(.caret(NotePosition(tableID, 0, field: .cell(row: 0, column: 0))))
        grid.paste([para("x"), para("y")])
        expectEqual(grid.page.blocks[0].props.table?.cell(0, 0)?.plainText, "x ya", "pasting lines into a cell joins them")

        let column = makeSession([columns([[para("")], [para("r")]])])
        let blank = column.page.blocks[0].children[0].children[0].id
        column.setSelection(.caret(NotePosition(blank, 0)))
        column.paste([columns([[para("in1")], [para("in2")]]), NoteBlock(.column, children: [para("stray")])])
        expectOutline(column.page, "columns\n  column\n    p in1\n    p in2\n    p stray\n  column\n    p r", "columns never nest, and stray columns unwrap")
    }

    static func pastingPlainText() {
        let session = makeSession([NoteBlock(.paragraph, text: NoteText(pieces: [("ab", italicMarks)]))])
        let id = session.page.blocks[0].id
        session.setSelection(.caret(NotePosition(id, 1)))
        session.pasteText("XY")
        expectEqual(session.page.blocks[0].text.string, "aXYb", "single-line text pastes inline")
        expect(session.page.blocks[0].text.allHave(.italic, in: 0..<4), "taking the surrounding style")
        session.pasteText("one\r\ntwo\rthree")
        expectOutline(session.page, "p aXYone\np two\np threeb", "line breaks of every flavour become new lines")

        let codePage = makeSession([code("")])
        codePage.setSelection(.caret(NotePosition(codePage.page.blocks[0].id, 0)))
        codePage.pasteText("a\nb")
        expectEqual(codePage.page.blocks[0].text.string, "a\nb", "code keeps pasted line breaks")
    }

    static func pasteUndo() {
        let session = makeSession([para("Hello world")])
        let id = session.page.blocks[0].id
        session.setSelection(.text(anchor: NotePosition(id, 0), head: NotePosition(id, 5)))
        session.paste([para("A"), para("B")])
        expectOutline(session.page, "p A\np B world", "the paste replaced the selection with two lines")
        expectEqual(session.undoDepth, 1, "deleting and inserting are one paste step")
        expectEqual(session.undoActionName, "Paste", "named Paste")
        session.undo()
        expectOutline(session.page, "p Hello world", "one undo restores the original")
        expectEqual(session.selection, .text(anchor: NotePosition(id, 0), head: NotePosition(id, 5)), "with the selection back")
    }
}
