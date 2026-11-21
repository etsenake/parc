import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageStructureTests: NoteFixtures {
    func cellCaret(_ table: NoteBlockID, _ row: Int, _ column: Int, _ offset: Int = 0) -> NotePageSelection {
        .caret(NotePosition(table, offset, field: .cell(row: row, column: column)))
    }

    @Test func theCaretFollowsItsCellDown() {
        let session = makeSession([table([["a", "b"], ["c", "d"]])])
        let id = session.page.blocks[0].id
        session.setSelection(cellCaret(id, 1, 1, 1))
        session.insertTableRow(id, at: 0)
        expectOutline(session.page, "table |/a|b/c|d", "a row goes in above")
        #expect(session.selection == cellCaret(id, 2, 1, 1), "the caret follows its cell down")
        session.insertTableColumn(id, at: 1)
        expectOutline(session.page, "table ||/a||b/c||d", "a column goes in at the index")
        #expect(session.selection == cellCaret(id, 2, 2, 1), "the caret follows its cell right")
        session.moveTableRow(id, from: 2, to: 0)
        expectOutline(session.page, "table c||d/||/a||b", "rows move")
        #expect(session.selection == cellCaret(id, 0, 2, 1), "the caret rides with the moved row")
        session.moveTableColumn(id, from: 2, to: 0)
        expectOutline(session.page, "table d|c|/||/b|a|", "columns move")
        #expect(session.selection == cellCaret(id, 0, 0, 1), "the caret rides with the moved column")
        session.deleteTableRow(id, at: 0)
        expectOutline(session.page, "table ||/b|a|", "rows delete")
        #expect(session.selection == cellCaret(id, 0, 0, 0), "a caret in a deleted row moves to the row that took its place")
        session.duplicateTableRow(id, at: 1)
        session.duplicateTableColumn(id, at: 0)
        expectOutline(session.page, "table |||/b|b|a|/b|b|a|", "rows and columns duplicate")
        session.deleteTableColumn(id, at: 3)
        session.deleteTableColumn(id, at: 2)
        session.deleteTableColumn(id, at: 1)
        #expect(!session.deleteTableColumn(id, at: 0), "the last column can't be deleted")
        session.deleteTableRow(id, at: 2)
        session.deleteTableRow(id, at: 1)
        #expect(!session.deleteTableRow(id, at: 0), "the last row can't be deleted")
        expectOutline(session.page, "table", "one empty cell remains")
        #expect(!session.moveTableRow(id, from: 0, to: 3), "out-of-range moves are refused")
    }

    @Test func aCellSelectionShrinksWithTheTable() {
        let cells = makeSession([table([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]])])
        let grid = cells.page.blocks[0].id
        cells.setSelection(.cells(table: grid, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 2, column: 2)))
        cells.deleteTableRow(grid, at: 2)
        #expect(cells.selection == .cells(table: grid, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 1, column: 2)), "a cell selection shrinks with the table")
        cells.deleteSelection()
        expectOutline(cells.page, "table ||/||", "clearing selected cells empties them")
    }

    @Test func headerColumnTurnsOn() {
        let clock = NoteTestClock()
        let session = makeSession([table([["a", "b"], ["c", "d"]])], clock: clock)
        let id = session.page.blocks[0].id
        #expect(session.setTableHeaderColumn(id, true), "header column turns on")
        #expect(!session.setTableHeaderColumn(id, true), "turning it on twice is a no-op")
        session.setTableHeaderRow(id, false)
        let grid = session.page.blocks[0].props.table!
        #expect(grid.headerColumn && !grid.headerRow, "header flags stick")
        let before = session.undoDepth
        for width in stride(from: 100.0, through: 180.0, by: 20.0) {
            session.setTableColumnWidth(id, column: 1, width: width)
            clock.advance(0.05)
        }
        #expect(session.page.blocks[0].props.table?.columnWidths == [nil, 180], "the width lands where the drag ended")
        #expect(session.undoDepth == before + 1, "a width drag is one step")
        session.setTableColumnWidth(id, column: 0, width: 2)
        #expect(session.page.blocks[0].props.table?.columnWidths[0] == NoteTable.minimumColumnWidth, "widths respect a minimum")
        session.setTableColumnAlignment(id, column: 0, .right)
        session.moveTableColumn(id, from: 0, to: 1)
        let moved = session.page.blocks[0].props.table!
        #expect(moved.alignments == [nil, .right] && moved.columnWidths == [180, NoteTable.minimumColumnWidth], "alignment and width travel with their column")
        #expect(!session.setTableColumnAlignment(id, column: 9, .left), "missing columns are refused")
    }

    @Test func callersCanNameATableStep() {
        let named = makeSession([table([["a", "b"], ["c", "d"]])])
        let grid2 = named.page.blocks[0].id
        let landing = cellCaret(grid2, 2, 1)
        named.insertTableRow(grid2, at: 2, name: "Add Row", select: landing)
        #expect(named.undoActionName == "Add Row", "callers can name a table step")
        #expect(named.selection == landing, "and say where the caret lands")
        var changes: [NotePageChange.Kind] = []
        let subscription = named.changes.sink { changes.append($0.kind) }
        named.setTableHeaderRow(grid2, false)
        named.setTableColumnAlignment(grid2, column: 0, .center)
        named.insertTableColumn(grid2, at: 0)
        #expect(changes == [.text, .text, .structure], "flag and alignment tweaks are light, new columns are structural")
        subscription.cancel()
        #expect(named.setTableColumnWidths(grid2, [120, nil, 240], name: "Resize Column"), "widths can be set all at once")
        #expect(named.page.blocks[0].props.table?.columnWidths == [120, nil, 240], "every column takes its width")
        #expect(!named.setTableColumnWidths(grid2, [120, nil, 240]), "setting the same widths again changes nothing")
        #expect(named.setTableColumnWidths(grid2, [], name: "Fit to Width"), "an empty list fits the table to the page")
        #expect(named.page.blocks[0].props.table?.columnWidths == [nil, nil, nil], "all widths clear")
        #expect(named.undoActionName == "Fit to Width", "with the caller's name")
    }

    @Test func columnsStartEqual() {
        let session = makeSession([para("a"), para("b"), para("c")])
        session.placeBeside([session.id("b")], target: session.id("a"), side: .right)
        expectOutline(session.page, "columns\n  column\n    p a\n  column\n    p b\np c", "dropping beside a block makes two columns")
        session.placeBeside([session.id("c")], target: session.id("a"), side: .left)
        expectOutline(session.page, "columns\n  column\n    p c\n  column\n    p a\n  column\n    p b", "dropping beside a column block adds a column")
        let group = session.page.blocks[0].id
        #expect(session.page.columnFractions(of: group).map { ($0 * 3).rounded() } == [1, 1, 1], "columns start equal")
        session.setColumnWidths(group, [2, 1, 1])
        #expect(session.page.columnFractions(of: group) == [0.5, 0.25, 0.25], "widths normalize to fractions")
        session.setColumnWidths(group, [100, 1, 1])
        #expect(session.page.columnFractions(of: group).allSatisfy { $0 >= NotePageSession.minimumColumnFraction * 0.9 }, "no column gets squeezed away")
        session.setColumnWidths(group, [1, 1])
        #expect(session.page.block(group)!.children[2].props.width != nil, "a width list of the wrong length is ignored")
        session.resetColumnWidths(group)
        #expect(session.page.block(group)!.children.allSatisfy { $0.props.width == nil }, "reset clears custom widths")

        session.placeBeside([session.id("b")], target: session.id("c"), side: .left)
        expectOutline(session.page, "columns\n  column\n    p b\n  column\n    p c\n  column\n    p a", "moving a block from one column beside another reshuffles columns")
    }

    @Test func columnLayouts2() {
        var crowded = [[para("1")], [para("2")], [para("3")], [para("4")], [para("5")]]
        crowded[0].append(para("6"))
        let full = makeSession([columns(crowded), para("extra")])
        full.placeBeside([full.id("extra")], target: full.id("3"), side: .right)
        expectOutline(full.page, "columns\n  column\n    p 1\n    p 6\n  column\n    p 2\n  column\n    p 3\n  column\n    p 4\n  column\n    p 5\np extra",
                      "a full set of columns refuses one more")
    }

    @Test func droppingBesideANestedBlockInAColumnAdds() {
        let nested = makeSession([columns([[bullet("x", [bullet("y")])], [para("z")]]), para("w")])
        nested.placeBeside([nested.id("w")], target: nested.id("y"), side: .right)
        #expect(nested.page.blocks[0].children.count == 3 && nested.page.allBlocks().filter { $0.kind == .columns }.count == 1, "dropping beside a nested block in a column adds a column instead of nesting columns")
    }

    @Test func aWholeRowWithFiveColumnsRefusesInsteadOf() {
        let fullRow = makeSession([columns([[para("1")], [para("2")], [para("3")], [para("4")], [para("5")]]), para("more")])
        fullRow.placeBeside([fullRow.id("more")], target: fullRow.page.blocks[0].id, side: .right)
        #expect(fullRow.page.blocks.count == 2 && fullRow.page.allBlocks().filter { $0.kind == .columns }.count == 1 && !fullRow.canUndo, "a whole row with five columns refuses instead of nesting columns")
        fullRow.placeBeside([fullRow.id("more")], target: fullRow.page.blocks[0].children[2].id, side: .left)
        #expect(fullRow.page.blocks.count == 2 && !fullRow.canUndo, "so does one of its columns")
        let pair = makeSession([columns([[para("l")], [para("r")]]), para("new")])
        pair.placeBeside([pair.id("new")], target: pair.page.blocks[0].id, side: .left)
        expectOutline(pair.page, "columns\n  column\n    p new\n  column\n    p l\n  column\n    p r", "dropping beside a whole row adds an edge column")
    }

    @Test func columnsCanTBeDroppedBesideABlock() {
        let refuse = makeSession([columns([[para("x")], [para("y")]]), para("z")])
        refuse.placeBeside([refuse.page.blocks[0].id], target: refuse.id("z"), side: .right)
        #expect(refuse.page.blocks.count == 2, "columns can't be dropped beside a block")
    }

    @Test func theEmptyColumnIsGone() {
        let session = makeSession([columns([[para("a"), para("b")], [para("c")]]), para("d")])
        let left = session.page.blocks[0].children[0].id, right = session.page.blocks[0].children[1].id
        session.moveBlocks([session.id("d")], toColumn: right, at: 0)
        expectOutline(session.page, "columns\n  column\n    p a\n    p b\n  column\n    p d\n    p c", "blocks move into a column at an index")
        session.moveBlocks([session.id("a")], toColumn: right, at: 9)
        expectOutline(session.page, "columns\n  column\n    p b\n  column\n    p d\n    p c\n    p a", "a large index appends")
        session.moveBlocks([session.id("b")], toColumn: right, at: 1)
        expectOutline(session.page, "p d\np b\np c\np a", "emptying a column folds the layout away")
        #expect(!session.page.contains(left), "the empty column is gone")
    }

    @Test func columnsCanTMoveInsideAnotherColumn() {
        let invalid = makeSession([columns([[para("a")], [para("b")]]), columns([[para("c")], [para("d")]])])
        invalid.moveBlocks([invalid.page.blocks[1].id], to: .lastChild(of: invalid.page.blocks[0].children[0].id))
        #expect(invalid.page.blocks.count == 2, "columns can't move inside another column")
        invalid.moveBlocks([invalid.id("a")], to: .firstChild(of: invalid.page.blocks[0].id))
        #expect(invalid.page.blocks[0].children.allSatisfy { $0.kind == .column }, "only columns can sit directly in a column set")
    }

    @Test func theFirstColumnsTakeTheExtraBlocks() {
        #expect(NotePageSession.columnGroups([1, 2, 3, 4, 5], count: 2) == [[1, 2, 3], [4, 5]], "the first columns take the extra blocks")
        #expect(NotePageSession.columnGroups([1, 2, 3], count: 3) == [[1], [2], [3]], "one block per column when they match")
        #expect(NotePageSession.columnGroups([1, 2], count: 5) == [[1], [2]], "never more columns than blocks")
    }

    @Test func fourBlocksCanMakeUpToFourColumns() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1")]), para("c"), para("d"), para("e")])
        let picked = [session.id("a"), session.id("b"), session.id("c"), session.id("d")]
        #expect(session.columnSplitLimit(picked) == 4, "four blocks can make up to four columns")
        #expect(session.columnSplitLimit([session.id("a")]) == 0, "one block can't become columns")
        #expect(session.columnSplitLimit([session.id("a"), session.id("b1")]) == 0, "blocks at different levels can't become columns")
        session.setSelection(.blocks(picked))
        session.turnIntoColumns(picked, count: 2)
        expectOutline(session.page, "columns\n  column\n    p a\n    ul b\n      ul b1\n  column\n    p c\n    p d\np e",
                      "Turn into 2 columns splits the selection in order, children and all")
        #expect(session.selection == .blocks(picked), "the same blocks stay selected")
        #expect(session.undoActionName == "Turn Into", "it's one Turn Into step")
        #expect(session.columnSplitLimit([session.id("a"), session.id("c")]) == 0, "blocks already in columns can't nest more columns")
        session.undo()
        expectOutline(session.page, "p a\nul b\n  ul b1\np c\np d\np e", "undo puts the blocks back")
    }

    @Test func sixBlocksStillStopAtFiveColumns() {
        let six = makeSession((1...6).map { para(String($0)) })
        let all = six.page.blocks.map(\.id)
        #expect(six.columnSplitLimit(all) == 5, "six blocks still stop at five columns")
        six.turnIntoColumns(all, count: 5)
        #expect(six.page.blocks[0].children.map { $0.children.count } == [2, 1, 1, 1, 1], "five columns share six blocks")
        six.turnIntoColumns([six.id("1"), six.id("2")], count: 2)
        #expect(six.page.allBlocks().filter { $0.kind == .columns }.count == 1, "no columns inside columns")
    }

    @Test func columnsCanFormInsideAToggle() {
        let toggle = makeSession([NoteBlock(.toggle, text: "t", children: [para("x"), para("y")])])
        toggle.turnIntoColumns([toggle.id("x"), toggle.id("y")], count: 2)
        let inner = toggle.page.blocks[0].children
        #expect(inner.count == 1 && inner[0].kind == .columns && inner[0].children.map { $0.children.map(\.text.plainText) } == [["x"], ["y"]], "columns can form inside a toggle")
    }

    @Test func aSelectionHoldingColumnsCanTNestThem() {
        let carrying = makeSession([columns([[para("l")], [para("r")]]), para("z")])
        #expect(carrying.columnSplitLimit([carrying.page.blocks[0].id, carrying.id("z")]) == 0, "a selection holding columns can't nest them")
        let flat = makeSession([para("p"), para("q")])
        flat.isFlat = true
        #expect(flat.columnSplitLimit([flat.id("p"), flat.id("q")]) == 0, "plain-text notes stay flat")
    }

    @Test func firstPressSelectsTheBlockSText() {
        let session = makeSession([para("Hello"), para(""), bullet("x", [bullet("y")])])
        let hello = session.id("Hello")
        session.setSelection(.caret(NotePosition(hello, 2)))
        #expect(session.selectAllStep() == .text(anchor: NotePosition(hello, 0), head: NotePosition(hello, 5)), "first press selects the block's text")
        #expect(session.selectAllStep() == .blocks([hello]), "second press selects the block")
        let all = session.page.blocks.map(\.id)
        #expect(session.selectAllStep() == .blocks(all), "third press selects every block")
        #expect(session.selectAllStep() == .blocks(all), "and it stays there")
        let empty = session.page.blocks[1].id
        session.setSelection(.caret(NotePosition(empty, 0)))
        #expect(session.selectAllStep() == .blocks([empty]), "an empty block skips straight to block selection")
        session.setSelection(.blocks([session.id("y")]))
        #expect(session.selectAllStep() == .blocks(all), "a nested block selection grows to everything")
        session.setSelection(.text(anchor: NotePosition(hello, 3), head: NotePosition(session.id("y"), 1)))
        #expect(session.selectAllStep() == .blocks([hello, empty, session.id("x")]), "a cross-block selection becomes those blocks")
    }

    @Test func inACellFirstTheCellSText() {
        let grid = makeSession([table([["ab", "c"], ["d", "e"]])])
        let id = grid.page.blocks[0].id
        grid.setSelection(cellCaret(id, 0, 0, 1))
        #expect(grid.selectAllStep() == .text(anchor: NotePosition(id, 0, field: .cell(row: 0, column: 0)),
                                                head: NotePosition(id, 2, field: .cell(row: 0, column: 0))), "in a cell, first the cell's text")
        #expect(grid.selectAllStep() == .cells(table: id, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 1, column: 1)), "then every cell")
        #expect(grid.selectAllStep() == .blocks([id]), "then the table")
    }

    @Test func addingACaptionPutsTheCaret() {
        let session = makeSession([image(), divider()])
        let picture = session.page.blocks[0].id
        session.addCaption(to: picture)
        #expect(session.selection == .caret(NotePosition(picture, 0, field: .caption)), "adding a caption puts the caret in it")
        session.type("A cat")
        expectOutline(session.page, "image [A cat]\ndivider", "typing fills the caption")
        session.setCaption(NoteText("A dog"), of: picture)
        expectOutline(session.page, "image [A dog]\ndivider", "captions can be set directly")
        session.removeCaption(from: picture)
        expectOutline(session.page, "image\ndivider", "captions can be removed")
        #expect(session.selection == .blocks([picture]), "removing the caption you're in selects the block")
        session.addCaption(to: session.page.blocks[1].id)
        #expect(session.selection == .blocks([picture]), "dividers don't take captions")
    }

    @Test func blockSegmentsIncludeCellsAndChildren() {
        let session = makeSession([para("ab"), table([["c", "de"], ["f", "g"]]), bullet("h", [bullet("ij")]), code("k"), para("lm")])
        let grid = session.page.blocks[1].id
        let fromBlocks = session.textSegments(of: .blocks([session.id("h"), grid]))
        #expect(fromBlocks.map(\.position.field) == [.cell(row: 0, column: 0), .cell(row: 0, column: 1), .cell(row: 1, column: 0),
                                                       .cell(row: 1, column: 1), .body, .body], "block segments include cells and children")
        let rect = session.textSegments(of: .cells(table: grid, anchor: NoteTableCell(row: 1, column: 1), head: NoteTableCell(row: 0, column: 1)))
        #expect(rect.count == 2 && rect[0].range == 0..<2 && rect[1].position.field == .cell(row: 1, column: 1), "a cell selection yields its cells")
        let across = session.textSegments(of: .text(anchor: NotePosition(session.id("lm"), 1), head: NotePosition(session.id("ab"), 1)))
        #expect(across.map(\.range) == [1..<2, 0..<1, 0..<2, 0..<1, 0..<1, 0..<1, 0..<2, 0..<1, 0..<1], "cross-block segments cover cells in between")
        session.toggleMark(.bold, in: .text(anchor: NotePosition(session.id("ab"), 0), head: NotePosition(session.id("lm"), 2)))
        #expect(session.hasMark(.bold, in: .blocks([grid])), "bold reaches table cells")
        #expect(session.page.block(session.id("k"))!.text.isPlain, "code never takes marks")
        #expect(session.hasMark(.bold, in: .text(anchor: NotePosition(session.id("ab"), 0), head: NotePosition(session.id("lm"), 2))), "and code doesn't stop the selection from reading as bold")
    }

    @Test func caretAtTheJoin() {
        let nested = makeSession([para("Start"), bullet("list", [bullet("child", [bullet("grand")]), bullet("sibling")]), para("after")])
        nested.setSelection(.text(anchor: NotePosition(nested.id("Start"), 2), head: NotePosition(nested.id("child"), 3)))
        nested.deleteSelection()
        expectOutline(nested.page, "p Stld\n  ul grand\nul sibling\np after", "deleting into a nested item keeps what follows in order, children nested")
        #expect(nested.selection == .caret(NotePosition(nested.id("Stld"), 2)), "caret at the join")
    }

    @Test func crossBlockDeletes2() {
        let adopt = makeSession([bullet("one"), bullet("two", [bullet("kid")])])
        adopt.setSelection(.text(anchor: NotePosition(adopt.id("one"), 1), head: NotePosition(adopt.id("two"), 1)))
        adopt.deleteSelection()
        expectOutline(adopt.page, "ul owo\n  ul kid", "the start block adopts the end block's children")
    }

    @Test func crossBlockDeletes3() {
        let parent = makeSession([bullet("parent", [bullet("first"), bullet("second")])])
        parent.setSelection(.text(anchor: NotePosition(parent.id("parent"), 3), head: NotePosition(parent.id("first"), 2)))
        parent.deleteSelection()
        expectOutline(parent.page, "ul parrst\n  ul second", "deleting from a parent into its child keeps the other children")
    }

    @Test func crossBlockDeletes4() {
        let mixed = makeSession([para("abc"), image(), toggle("fold", expanded: false, [para("secret")]), divider(), para("xyz")])
        mixed.setSelection(.text(anchor: NotePosition(mixed.id("abc"), 1), head: NotePosition(mixed.id("xyz"), 2)))
        mixed.deleteSelection()
        expectOutline(mixed.page, "p az", "media, dividers and closed toggles in the middle go away entirely")
    }

    @Test func andOneUndoBringsEveryOneOfThemBack() {
        let everyKind = makeSession([para("abc"), table([["t"]]), block(.bookmark) { $0.source = "https://b" },
                                     block(.embed) { $0.source = "https://e" }, divider(), image(), code("let x"),
                                     bullet("mid", [bullet("mid child", [bullet("deeper")])]), para("xyz"), para("untouched")])
        everyKind.setSelection(.text(anchor: NotePosition(everyKind.id("abc"), 1), head: NotePosition(everyKind.id("xyz"), 2)))
        everyKind.deleteSelection()
        expectOutline(everyKind.page, "p az\np untouched", "every block strictly between the ends goes, text or not, with all its descendants")
        everyKind.undo()
        #expect(everyKind.page.blocks.count == 10, "and one undo brings every one of them back")
    }

    @Test func matchingExactlyWhatACopyOfThatSelectionHolds() {
        let closedStart = makeSession([toggle("Fold", expanded: false, [para("hidden"), bullet("also hidden")]), para("after"), para("kept")])
        let foldSelection = NotePageSelection.text(anchor: NotePosition(closedStart.id("Fold"), 2), head: NotePosition(closedStart.id("after"), 3))
        let copied = closedStart.fragment(of: foldSelection)
        closedStart.setSelection(foldSelection)
        closedStart.deleteSelection()
        expectOutline(closedStart.page, "toggle- Foer\np kept", "a closed toggle's hidden insides sit between the ends, so they go too")
        #expect(outline(copied) == "toggle- ld\n  p hidden\n  ul also hidden\np aft", "matching exactly what a copy of that selection holds")
    }

    @Test func crossBlockDeletes7() {
        let columnsPage = makeSession([columns([[para("left"), para("l2")], [para("right"), para("r2")]])])
        columnsPage.setSelection(.text(anchor: NotePosition(columnsPage.id("l2"), 1), head: NotePosition(columnsPage.id("right"), 2)))
        columnsPage.deleteSelection()
        expectOutline(columnsPage.page, "columns\n  column\n    p left\n    p lght\n  column\n    p r2", "deleting across columns keeps the column structure")
    }

    @Test func textMergedIntoCodeTurnsPlain() {
        let toCode = makeSession([code("let"), NoteBlock(.paragraph, text: NoteText(pieces: [("bold", boldMarks)]))])
        toCode.setSelection(.text(anchor: NotePosition(toCode.id("let"), 3), head: NotePosition(toCode.id("bold"), 1)))
        toCode.deleteSelection()
        #expect(toCode.page.blocks.count == 1 && toCode.page.blocks[0].text.string == "letold" && toCode.page.blocks[0].text.isPlain, "text merged into code turns plain")
    }

    @Test func crossBlockDeletes9() {
        let fields = makeSession([image(caption: "caption"), para("body")])
        let picture = fields.page.blocks[0].id
        fields.setSelection(.text(anchor: NotePosition(picture, 3, field: .caption), head: NotePosition(fields.id("body"), 2)))
        fields.deleteSelection()
        expectOutline(fields.page, "image [cap]\np dy", "a selection from a caption trims both ends without merging")
    }

    @Test func indexStaysTrueOnBigPages() {
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
            #expect(session.page.numberLabel(for: id) != nil, "every numbered item has a label")
            labels += 1
        }
        #expect(labels > 0, "the big page still has numbered items")
        while session.canUndo { session.undo() }
        #expect(session.page.blocks == blocks, "undoing everything returns the original page")
        verifyIndex(session.page)
    }

    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state ^ (state >> 33)
        }
    }
}
