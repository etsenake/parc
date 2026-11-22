import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageStructureSelectionTests: NoteFixtures {
    private func cellCaret(_ table: NoteBlockID, _ row: Int, _ column: Int, _ offset: Int = 0) -> NotePageSelection {
        .caret(NotePosition(table, offset, field: .cell(row: row, column: column)))
    }

    @Test func selectAllFromACaretSelectsTheBlocksText() {
        let session = makeSession([para("Hello"), para(""), bullet("x", [bullet("y")])])
        let hello = session.id("Hello")
        session.setSelection(.caret(NotePosition(hello, 2)))
        #expect(session.selectAllStep() == .text(anchor: NotePosition(hello, 0), head: NotePosition(hello, 5)), "first press selects the block's text")
    }

    @Test func selectAllFromTheBlocksTextSelectsTheBlock() {
        let session = makeSession([para("Hello"), para(""), bullet("x", [bullet("y")])])
        let hello = session.id("Hello")
        session.setSelection(.caret(NotePosition(hello, 2)))
        _ = session.selectAllStep()
        #expect(session.selectAllStep() == .blocks([hello]), "second press selects the block")
    }

    @Test func selectAllFromABlockSelectsEveryBlock() {
        let session = makeSession([para("Hello"), para(""), bullet("x", [bullet("y")])])
        let hello = session.id("Hello")
        session.setSelection(.blocks([hello]))
        let all = session.page.blocks.map(\.id)
        #expect(session.selectAllStep() == .blocks(all), "third press selects every block")
    }

    @Test func selectAllKeepsAllBlocksSelected() {
        let session = makeSession([para("Hello"), para(""), bullet("x", [bullet("y")])])
        let all = session.page.blocks.map(\.id)
        session.setSelection(.blocks(all))
        #expect(session.selectAllStep() == .blocks(all), "and it stays there")
    }

    @Test func selectAllFromAnEmptyBlockSelectsThatBlock() {
        let session = makeSession([para("Hello"), para(""), bullet("x", [bullet("y")])])
        let empty = session.page.blocks[1].id
        session.setSelection(.caret(NotePosition(empty, 0)))
        #expect(session.selectAllStep() == .blocks([empty]), "an empty block skips straight to block selection")
    }

    @Test func selectAllFromANestedBlockSelectsEveryBlock() {
        let session = makeSession([para("Hello"), para(""), bullet("x", [bullet("y")])])
        let all = session.page.blocks.map(\.id)
        session.setSelection(.blocks([session.id("y")]))
        #expect(session.selectAllStep() == .blocks(all), "a nested block selection grows to everything")
    }

    @Test func selectAllFromACrossBlockRangeSelectsItsBlocks() {
        let session = makeSession([para("Hello"), para(""), bullet("x", [bullet("y")])])
        let hello = session.id("Hello")
        let empty = session.page.blocks[1].id
        session.setSelection(.text(anchor: NotePosition(hello, 3), head: NotePosition(session.id("y"), 1)))
        #expect(session.selectAllStep() == .blocks([hello, empty, session.id("x")]), "a cross-block selection becomes those blocks")
    }

    @Test func selectAllFromACellCaretSelectsTheCellText() {
        let grid = makeSession([table([["ab", "c"], ["d", "e"]])])
        let id = grid.page.blocks[0].id
        grid.setSelection(cellCaret(id, 0, 0, 1))
        #expect(grid.selectAllStep() == .text(anchor: NotePosition(id, 0, field: .cell(row: 0, column: 0)),
                                                head: NotePosition(id, 2, field: .cell(row: 0, column: 0))), "in a cell, first the cell's text")
    }

    @Test func selectAllFromTheCellTextSelectsEveryCell() {
        let grid = makeSession([table([["ab", "c"], ["d", "e"]])])
        let id = grid.page.blocks[0].id
        grid.setSelection(cellCaret(id, 0, 0, 1))
        _ = grid.selectAllStep()
        #expect(grid.selectAllStep() == .cells(table: id, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 1, column: 1)), "then every cell")
    }

    @Test func selectAllFromAllCellsSelectsTheTable() {
        let grid = makeSession([table([["ab", "c"], ["d", "e"]])])
        let id = grid.page.blocks[0].id
        grid.setSelection(cellCaret(id, 0, 0, 1))
        _ = grid.selectAllStep()
        _ = grid.selectAllStep()
        #expect(grid.selectAllStep() == .blocks([id]), "then the table")
    }

    @Test func addingACaptionPutsTheCaretInIt() {
        let session = makeSession([image(), divider()])
        let picture = session.page.blocks[0].id
        session.addCaption(to: picture)
        #expect(session.selection == .caret(NotePosition(picture, 0, field: .caption)), "adding a caption puts the caret in it")
    }

    @Test func typingInACaptionFillsIt() {
        let session = makeSession([image(), divider()])
        let picture = session.page.blocks[0].id
        session.addCaption(to: picture)
        session.type("A cat")
        expectOutline(session.page, "image [A cat]\ndivider", "typing fills the caption")
    }

    @Test func aCaptionCanBeSetDirectly() {
        let session = makeSession([image(), divider()])
        let picture = session.page.blocks[0].id
        session.addCaption(to: picture)
        session.type("A cat")
        session.setCaption(NoteText("A dog"), of: picture)
        expectOutline(session.page, "image [A dog]\ndivider", "captions can be set directly")
    }

    @Test func removingTheActiveCaptionSelectsItsBlock() {
        let session = makeSession([image(), divider()])
        let picture = session.page.blocks[0].id
        session.addCaption(to: picture)
        session.type("A cat")
        session.setCaption(NoteText("A dog"), of: picture)
        session.removeCaption(from: picture)
        expectOutline(session.page, "image\ndivider", "captions can be removed")
        #expect(session.selection == .blocks([picture]), "removing the caption you're in selects the block")
    }

    @Test func aDividerDoesNotTakeACaption() {
        let session = makeSession([image(), divider()])
        let picture = session.page.blocks[0].id
        session.addCaption(to: picture)
        session.type("A cat")
        session.setCaption(NoteText("A dog"), of: picture)
        session.removeCaption(from: picture)
        session.addCaption(to: session.page.blocks[1].id)
        #expect(session.selection == .blocks([picture]), "dividers don't take captions")
    }

    @Test func blockSelectionSegmentsIncludeCellsAndChildren() {
        let session = makeSession([para("ab"), table([["c", "de"], ["f", "g"]]), bullet("h", [bullet("ij")]), code("k"), para("lm")])
        let grid = session.page.blocks[1].id
        let fromBlocks = session.textSegments(of: .blocks([session.id("h"), grid]))
        #expect(fromBlocks.map(\.position.field) == [.cell(row: 0, column: 0), .cell(row: 0, column: 1), .cell(row: 1, column: 0),
                                                       .cell(row: 1, column: 1), .body, .body], "block segments include cells and children")
    }

    @Test func aCellSelectionYieldsItsCells() {
        let session = makeSession([para("ab"), table([["c", "de"], ["f", "g"]]), bullet("h", [bullet("ij")]), code("k"), para("lm")])
        let grid = session.page.blocks[1].id
        let rect = session.textSegments(of: .cells(table: grid, anchor: NoteTableCell(row: 1, column: 1), head: NoteTableCell(row: 0, column: 1)))
        #expect(rect.count == 2 && rect[0].range == 0..<2 && rect[1].position.field == .cell(row: 1, column: 1), "a cell selection yields its cells")
    }

    @Test func crossBlockSegmentsIncludeCellsBetweenTheEndpoints() {
        let session = makeSession([para("ab"), table([["c", "de"], ["f", "g"]]), bullet("h", [bullet("ij")]), code("k"), para("lm")])
        let across = session.textSegments(of: .text(anchor: NotePosition(session.id("lm"), 1), head: NotePosition(session.id("ab"), 1)))
        #expect(across.map(\.range) == [1..<2, 0..<1, 0..<2, 0..<1, 0..<1, 0..<1, 0..<2, 0..<1, 0..<1], "cross-block segments cover cells in between")
    }

    @Test func boldAcrossABlockRangeReachesCellsAndSkipsCode() {
        let session = makeSession([para("ab"), table([["c", "de"], ["f", "g"]]), bullet("h", [bullet("ij")]), code("k"), para("lm")])
        let grid = session.page.blocks[1].id
        session.toggleMark(.bold, in: .text(anchor: NotePosition(session.id("ab"), 0), head: NotePosition(session.id("lm"), 2)))
        #expect(session.hasMark(.bold, in: .blocks([grid])), "bold reaches table cells")
        #expect(session.page.block(session.id("k"))!.text.isPlain, "code never takes marks")
        #expect(session.hasMark(.bold, in: .text(anchor: NotePosition(session.id("ab"), 0), head: NotePosition(session.id("lm"), 2))), "and code doesn't stop the selection from reading as bold")
    }
}
