import Foundation

@main @MainActor
struct PageStructureTests {
    static func main() {
        tableRowsAndColumns()
        tableHeadersWidthsAlignment()
        columnLayouts()
        columnMoves()
        selectAllProgression()
        captions()
        segments()
        crossBlockDeletes()
        indexStaysTrueOnBigPages()
        print("PageStructureTests passed")
    }

    static func cellCaret(_ table: NoteBlockID, _ row: Int, _ column: Int, _ offset: Int = 0) -> NotePageSelection {
        .caret(NotePosition(table, offset, field: .cell(row: row, column: column)))
    }

    static func tableRowsAndColumns() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        session.setSelection(cellCaret(id, 1, 1, 1))
        session.insertTableRow(id, at: 0)
        expectOutline(session.page, "table |/a|b/c|d", "a row goes in above")
        expectEqual(session.selection, cellCaret(id, 2, 1, 1), "the caret follows its cell down")
        session.insertTableColumn(id, at: 1)
        expectOutline(session.page, "table ||/a||b/c||d", "a column goes in at the index")
        expectEqual(session.selection, cellCaret(id, 2, 2, 1), "the caret follows its cell right")
        session.moveTableRow(id, from: 2, to: 0)
        expectOutline(session.page, "table c||d/||/a||b", "rows move")
        expectEqual(session.selection, cellCaret(id, 0, 2, 1), "the caret rides with the moved row")
        session.moveTableColumn(id, from: 2, to: 0)
        expectOutline(session.page, "table d|c|/||/b|a|", "columns move")
        expectEqual(session.selection, cellCaret(id, 0, 0, 1), "the caret rides with the moved column")
        session.deleteTableRow(id, at: 0)
        expectOutline(session.page, "table ||/b|a|", "rows delete")
        expectEqual(session.selection, cellCaret(id, 0, 0, 0), "a caret in a deleted row moves to the row that took its place")
        session.duplicateTableRow(id, at: 1)
        session.duplicateTableColumn(id, at: 0)
        expectOutline(session.page, "table |||/b|b|a|/b|b|a|", "rows and columns duplicate")
        session.deleteTableColumn(id, at: 3)
        session.deleteTableColumn(id, at: 2)
        session.deleteTableColumn(id, at: 1)
        expect(!session.deleteTableColumn(id, at: 0), "the last column can't be deleted")
        session.deleteTableRow(id, at: 2)
        session.deleteTableRow(id, at: 1)
        expect(!session.deleteTableRow(id, at: 0), "the last row can't be deleted")
        expectOutline(session.page, "table", "one empty cell remains")
        expect(!session.moveTableRow(id, from: 0, to: 3), "out-of-range moves are refused")

        let cells = makeSession([table([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]])])
        let grid = cells.page.blocks[0].id
        cells.setSelection(.cells(table: grid, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 2, column: 2)))
        cells.deleteTableRow(grid, at: 2)
        expectEqual(cells.selection, .cells(table: grid, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 1, column: 2)),
                    "a cell selection shrinks with the table")
        cells.deleteSelection()
        expectOutline(cells.page, "table ||/||", "clearing selected cells empties them")
    }

    static func tableHeadersWidthsAlignment() {
        let clock = TestClock()
        let session = makeSession([table([["a", "b"], ["c", "d"]])], clock: clock)
        let id = session.page.blocks[0].id
        expect(session.setTableHeaderColumn(id, true), "header column turns on")
        expect(!session.setTableHeaderColumn(id, true), "turning it on twice is a no-op")
        session.setTableHeaderRow(id, false)
        let grid = session.page.blocks[0].props.table!
        expect(grid.headerColumn && !grid.headerRow, "header flags stick")
        let before = session.undoDepth
        for width in stride(from: 100.0, through: 180.0, by: 20.0) {
            session.setTableColumnWidth(id, column: 1, width: width)
            clock.advance(0.05)
        }
        expectEqual(session.page.blocks[0].props.table?.columnWidths, [nil, 180], "the width lands where the drag ended")
        expectEqual(session.undoDepth, before + 1, "a width drag is one step")
        session.setTableColumnWidth(id, column: 0, width: 2)
        expectEqual(session.page.blocks[0].props.table?.columnWidths[0], NoteTable.minimumColumnWidth, "widths respect a minimum")
        session.setTableColumnAlignment(id, column: 0, .right)
        session.moveTableColumn(id, from: 0, to: 1)
        let moved = session.page.blocks[0].props.table!
        expect(moved.alignments == [nil, .right] && moved.columnWidths == [180, NoteTable.minimumColumnWidth], "alignment and width travel with their column")
        expect(!session.setTableColumnAlignment(id, column: 9, .left), "missing columns are refused")
    }

    static func columnLayouts() {
        let session = makeSession([para("a"), para("b"), para("c")])
        session.placeBeside([session.id("b")], target: session.id("a"), side: .right)
        expectOutline(session.page, "columns\n  column\n    p a\n  column\n    p b\np c", "dropping beside a block makes two columns")
        session.placeBeside([session.id("c")], target: session.id("a"), side: .left)
        expectOutline(session.page, "columns\n  column\n    p c\n  column\n    p a\n  column\n    p b", "dropping beside a column block adds a column")
        let group = session.page.blocks[0].id
        expectEqual(session.page.columnFractions(of: group).map { ($0 * 3).rounded() }, [1, 1, 1], "columns start equal")
        session.setColumnWidths(group, [2, 1, 1])
        expectEqual(session.page.columnFractions(of: group), [0.5, 0.25, 0.25], "widths normalize to fractions")
        session.setColumnWidths(group, [100, 1, 1])
        expect(session.page.columnFractions(of: group).allSatisfy { $0 >= NotePageSession.minimumColumnFraction * 0.9 }, "no column gets squeezed away")
        session.setColumnWidths(group, [1, 1])
        expect(session.page.block(group)!.children[2].props.width != nil, "a width list of the wrong length is ignored")
        session.resetColumnWidths(group)
        expect(session.page.block(group)!.children.allSatisfy { $0.props.width == nil }, "reset clears custom widths")

        session.placeBeside([session.id("b")], target: session.id("c"), side: .left)
        expectOutline(session.page, "columns\n  column\n    p b\n  column\n    p c\n  column\n    p a", "moving a block from one column beside another reshuffles columns")

        var crowded = [[para("1")], [para("2")], [para("3")], [para("4")], [para("5")]]
        crowded[0].append(para("6"))
        let full = makeSession([columns(crowded), para("extra")])
        full.placeBeside([full.id("extra")], target: full.id("3"), side: .right)
        expectOutline(full.page, "columns\n  column\n    p 1\n    p 6\n  column\n    p 2\n  column\n    p 3\n  column\n    p 4\n  column\n    p 5\np extra",
                      "a full set of columns refuses one more")

        let nested = makeSession([columns([[bullet("x", [bullet("y")])], [para("z")]]), para("w")])
        nested.placeBeside([nested.id("w")], target: nested.id("y"), side: .right)
        expect(nested.page.blocks[0].children.count == 3 && nested.page.allBlocks().filter { $0.kind == .columns }.count == 1,
               "dropping beside a nested block in a column adds a column instead of nesting columns")

        let refuse = makeSession([columns([[para("x")], [para("y")]]), para("z")])
        refuse.placeBeside([refuse.page.blocks[0].id], target: refuse.id("z"), side: .right)
        expectEqual(refuse.page.blocks.count, 2, "columns can't be dropped beside a block")
    }

    static func columnMoves() {
        let session = makeSession([columns([[para("a"), para("b")], [para("c")]]), para("d")])
        let left = session.page.blocks[0].children[0].id, right = session.page.blocks[0].children[1].id
        session.moveBlocks([session.id("d")], toColumn: right, at: 0)
        expectOutline(session.page, "columns\n  column\n    p a\n    p b\n  column\n    p d\n    p c", "blocks move into a column at an index")
        session.moveBlocks([session.id("a")], toColumn: right, at: 9)
        expectOutline(session.page, "columns\n  column\n    p b\n  column\n    p d\n    p c\n    p a", "a large index appends")
        session.moveBlocks([session.id("b")], toColumn: right, at: 1)
        expectOutline(session.page, "p d\np b\np c\np a", "emptying a column folds the layout away")
        expect(!session.page.contains(left), "the empty column is gone")

        let invalid = makeSession([columns([[para("a")], [para("b")]]), columns([[para("c")], [para("d")]])])
        invalid.moveBlocks([invalid.page.blocks[1].id], to: .lastChild(of: invalid.page.blocks[0].children[0].id))
        expectEqual(invalid.page.blocks.count, 2, "columns can't move inside another column")
        invalid.moveBlocks([invalid.id("a")], to: .firstChild(of: invalid.page.blocks[0].id))
        expect(invalid.page.blocks[0].children.allSatisfy { $0.kind == .column }, "only columns can sit directly in a column set")
    }

    static func selectAllProgression() {
        let session = makeSession([para("Hello"), para(""), bullet("x", [bullet("y")])])
        let hello = session.id("Hello")
        session.setSelection(.caret(NotePosition(hello, 2)))
        expectEqual(session.selectAllStep(), .text(anchor: NotePosition(hello, 0), head: NotePosition(hello, 5)), "first press selects the block's text")
        expectEqual(session.selectAllStep(), .blocks([hello]), "second press selects the block")
        let all = session.page.blocks.map(\.id)
        expectEqual(session.selectAllStep(), .blocks(all), "third press selects every block")
        expectEqual(session.selectAllStep(), .blocks(all), "and it stays there")
        let empty = session.page.blocks[1].id
        session.setSelection(.caret(NotePosition(empty, 0)))
        expectEqual(session.selectAllStep(), .blocks([empty]), "an empty block skips straight to block selection")
        session.setSelection(.blocks([session.id("y")]))
        expectEqual(session.selectAllStep(), .blocks(all), "a nested block selection grows to everything")
        session.setSelection(.text(anchor: NotePosition(hello, 3), head: NotePosition(session.id("y"), 1)))
        expectEqual(session.selectAllStep(), .blocks([hello, empty, session.id("x")]), "a cross-block selection becomes those blocks")

        let grid = makeSession([table([["ab", "c"], ["d", "e"]])])
        let id = grid.page.blocks[0].id
        grid.setSelection(cellCaret(id, 0, 0, 1))
        expectEqual(grid.selectAllStep(), .text(anchor: NotePosition(id, 0, field: .cell(row: 0, column: 0)),
                                                head: NotePosition(id, 2, field: .cell(row: 0, column: 0))), "in a cell, first the cell's text")
        expectEqual(grid.selectAllStep(), .cells(table: id, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 1, column: 1)), "then every cell")
        expectEqual(grid.selectAllStep(), .blocks([id]), "then the table")
    }

    static func captions() {
        let session = makeSession([image(), divider()])
        let picture = session.page.blocks[0].id
        session.addCaption(to: picture)
        expectEqual(session.selection, .caret(NotePosition(picture, 0, field: .caption)), "adding a caption puts the caret in it")
        session.type("A cat")
        expectOutline(session.page, "image [A cat]\ndivider", "typing fills the caption")
        session.setCaption(NoteText("A dog"), of: picture)
        expectOutline(session.page, "image [A dog]\ndivider", "captions can be set directly")
        session.removeCaption(from: picture)
        expectOutline(session.page, "image\ndivider", "captions can be removed")
        expectEqual(session.selection, .blocks([picture]), "removing the caption you're in selects the block")
        session.addCaption(to: session.page.blocks[1].id)
        expectEqual(session.selection, .blocks([picture]), "dividers don't take captions")
    }

    static func segments() {
        let session = makeSession([para("ab"), table([["c", "de"], ["f", "g"]]), bullet("h", [bullet("ij")]), code("k"), para("lm")])
        let grid = session.page.blocks[1].id
        let fromBlocks = session.textSegments(of: .blocks([session.id("h"), grid]))
        expectEqual(fromBlocks.map(\.position.field), [.cell(row: 0, column: 0), .cell(row: 0, column: 1), .cell(row: 1, column: 0),
                                                       .cell(row: 1, column: 1), .body, .body], "block segments include cells and children")
        let rect = session.textSegments(of: .cells(table: grid, anchor: NoteTableCell(row: 1, column: 1), head: NoteTableCell(row: 0, column: 1)))
        expect(rect.count == 2 && rect[0].range == 0..<2 && rect[1].position.field == .cell(row: 1, column: 1), "a cell selection yields its cells")
        let across = session.textSegments(of: .text(anchor: NotePosition(session.id("lm"), 1), head: NotePosition(session.id("ab"), 1)))
        expectEqual(across.map(\.range), [1..<2, 0..<1, 0..<2, 0..<1, 0..<1, 0..<1, 0..<2, 0..<1, 0..<1], "cross-block segments cover cells in between")
        session.toggleMark(.bold, in: .text(anchor: NotePosition(session.id("ab"), 0), head: NotePosition(session.id("lm"), 2)))
        expect(session.hasMark(.bold, in: .blocks([grid])), "bold reaches table cells")
        expect(session.page.block(session.id("k"))!.text.isPlain, "code never takes marks")
        expect(session.hasMark(.bold, in: .text(anchor: NotePosition(session.id("ab"), 0), head: NotePosition(session.id("lm"), 2))),
               "and code doesn't stop the selection from reading as bold")
    }

    static func crossBlockDeletes() {
        let nested = makeSession([para("Start"), bullet("list", [bullet("child", [bullet("grand")]), bullet("sibling")]), para("after")])
        nested.setSelection(.text(anchor: NotePosition(nested.id("Start"), 2), head: NotePosition(nested.id("child"), 3)))
        nested.deleteSelection()
        expectOutline(nested.page, "p Stld\nul grand\nul sibling\np after", "deleting into a nested item keeps what follows in order")
        expectEqual(nested.selection, .caret(NotePosition(nested.id("Stld"), 2)), "caret at the join")

        let adopt = makeSession([bullet("one"), bullet("two", [bullet("kid")])])
        adopt.setSelection(.text(anchor: NotePosition(adopt.id("one"), 1), head: NotePosition(adopt.id("two"), 1)))
        adopt.deleteSelection()
        expectOutline(adopt.page, "ul owo\n  ul kid", "the start block adopts the end block's children")

        let parent = makeSession([bullet("parent", [bullet("first"), bullet("second")])])
        parent.setSelection(.text(anchor: NotePosition(parent.id("parent"), 3), head: NotePosition(parent.id("first"), 2)))
        parent.deleteSelection()
        expectOutline(parent.page, "ul parrst\n  ul second", "deleting from a parent into its child keeps the other children")

        let mixed = makeSession([para("abc"), image(), toggle("fold", expanded: false, [para("secret")]), divider(), para("xyz")])
        mixed.setSelection(.text(anchor: NotePosition(mixed.id("abc"), 1), head: NotePosition(mixed.id("xyz"), 2)))
        mixed.deleteSelection()
        expectOutline(mixed.page, "p az", "media, dividers and closed toggles in the middle go away entirely")

        let everyKind = makeSession([para("abc"), table([["t"]]), block(.bookmark) { $0.source = "https://b" },
                                     block(.embed) { $0.source = "https://e" }, divider(), image(), code("let x"),
                                     bullet("mid", [bullet("mid child", [bullet("deeper")])]), para("xyz"), para("untouched")])
        everyKind.setSelection(.text(anchor: NotePosition(everyKind.id("abc"), 1), head: NotePosition(everyKind.id("xyz"), 2)))
        everyKind.deleteSelection()
        expectOutline(everyKind.page, "p az\np untouched", "every block strictly between the ends goes, text or not, with all its descendants")
        everyKind.undo()
        expectEqual(everyKind.page.blocks.count, 10, "and one undo brings every one of them back")

        let closedStart = makeSession([toggle("Fold", expanded: false, [para("hidden"), bullet("also hidden")]), para("after"), para("kept")])
        let foldSelection = NotePageSelection.text(anchor: NotePosition(closedStart.id("Fold"), 2), head: NotePosition(closedStart.id("after"), 3))
        let copied = closedStart.fragment(of: foldSelection)
        closedStart.setSelection(foldSelection)
        closedStart.deleteSelection()
        expectOutline(closedStart.page, "toggle- Foer\np kept", "a closed toggle's hidden insides sit between the ends, so they go too")
        expectEqual(outline(copied), "toggle- ld\n  p hidden\n  ul also hidden\np aft", "matching exactly what a copy of that selection holds")

        let columnsPage = makeSession([columns([[para("left"), para("l2")], [para("right"), para("r2")]])])
        columnsPage.setSelection(.text(anchor: NotePosition(columnsPage.id("l2"), 1), head: NotePosition(columnsPage.id("right"), 2)))
        columnsPage.deleteSelection()
        expectOutline(columnsPage.page, "columns\n  column\n    p left\n    p lght\n  column\n    p r2", "deleting across columns keeps the column structure")

        let toCode = makeSession([code("let"), NoteBlock(.paragraph, text: NoteText(pieces: [("bold", boldMarks)]))])
        toCode.setSelection(.text(anchor: NotePosition(toCode.id("let"), 3), head: NotePosition(toCode.id("bold"), 1)))
        toCode.deleteSelection()
        expect(toCode.page.blocks.count == 1 && toCode.page.blocks[0].text.string == "letold" && toCode.page.blocks[0].text.isPlain,
               "text merged into code turns plain")

        let fields = makeSession([image(caption: "caption"), para("body")])
        let picture = fields.page.blocks[0].id
        fields.setSelection(.text(anchor: NotePosition(picture, 3, field: .caption), head: NotePosition(fields.id("body"), 2)))
        fields.deleteSelection()
        expectOutline(fields.page, "image [cap]\np dy", "a selection from a caption trims both ends without merging")
    }

    static func indexStaysTrueOnBigPages() {
        var blocks: [NoteBlock] = []
        for index in 0..<2000 {
            switch index % 10 {
            case 3: blocks.append(bullet("item \(index)", [bullet("child \(index)")]))
            case 6: blocks.append(toggle("toggle \(index)", expanded: index % 20 == 6, [para("inside \(index)")]))
            case 9: blocks.append(numbered("number \(index)"))
            default: blocks.append(para("line \(index)"))
            }
        }
        let session = makeSession(blocks)
        verifyIndex(session.page)
        var generator = SeededGenerator(seed: 2026)
        for round in 0..<150 {
            let order = session.page.documentOrder(includingCollapsed: false)
            let pick = order[Int.random(in: 0..<order.count, using: &generator)]
            let block = session.page.block(pick)!
            switch round % 9 {
            case 0: if block.kind.hasRichText { session.splitBlock(at: NotePosition(pick, min(2, block.text.length))) }
            case 1: if block.kind.hasText { session.mergeBackward(pick) }
            case 2: session.indent([pick])
            case 3: session.outdent([pick])
            case 4: session.moveBlocks([pick], round % 2 == 0 ? .up : .down)
            case 5: session.turnInto([pick], kind: [.bulletedItem, .toggle, .paragraph, .numberedItem][round % 4])
            case 6: session.duplicateBlocks([pick])
            case 7: session.deleteBlocks([pick])
            default:
                if block.kind.hasText {
                    session.setSelection(.caret(NotePosition(pick, 0)))
                    session.type("x")
                }
            }
            verifyIndex(session.page)
            if round % 25 == 0 {
                session.undo()
                verifyIndex(session.page)
                session.redo()
                verifyIndex(session.page)
            }
        }
        var labels = 0
        for id in session.page.documentOrder() where session.page.block(id)?.kind == .numberedItem {
            expect(session.page.numberLabel(for: id) != nil, "every numbered item has a label")
            labels += 1
        }
        expect(labels > 0, "the big page still has numbered items")
        while session.canUndo { session.undo() }
        expectEqual(session.page.blocks, blocks, "undoing everything returns the original page")
        verifyIndex(session.page)
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state ^ (state >> 33)
    }
}
