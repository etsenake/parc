import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteTableSpanSessionTests {
    @Test func mergingCellsSelectsTheirAnchor() throws {
        let session = NotePageSession(page: NoteTableSpanTestsSupport.page(NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])))
        let id = try #require(session.page.blocks.first?.id, "no table")
        session.setSelection(.cells(table: id, anchor: NoteTableSpanTestsSupport.cell(0, 0), head: NoteTableSpanTestsSupport.cell(1, 1)))
        #expect(session.mergeTableCells(id, rows: 0...1, columns: 0...1), "session merge")
        #expect(session.selection == .cells(table: id, anchor: NoteTableSpanTestsSupport.cell(0, 0), head: NoteTableSpanTestsSupport.cell(0, 0)), "the merged cell stays selected")
    }

    @Test func undoingAMergeRestoresTheCoveredText() throws {
        let session = NotePageSession(page: NoteTableSpanTestsSupport.page(NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])))
        let id = try #require(session.page.blocks.first?.id, "no table")
        session.setSelection(.cells(table: id, anchor: NoteTableSpanTestsSupport.cell(0, 0), head: NoteTableSpanTestsSupport.cell(1, 1)))
        _ = session.mergeTableCells(id, rows: 0...1, columns: 0...1)
        session.undo()
        #expect(session.page.blocks.first?.props.table?.merges.isEmpty == true && session.page.blocks.first?.props.table?.rows[1][1].string == "e", "undo brings the hidden text back")
    }

    @Test func copyExpandsToIncludeWholeMerges() throws {
        let session = NotePageSession(page: NoteTableSpanTestsSupport.page(NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])))
        let id = try #require(session.page.blocks.first?.id, "no table")
        session.setSelection(.cells(table: id, anchor: NoteTableSpanTestsSupport.cell(0, 0), head: NoteTableSpanTestsSupport.cell(1, 1)))
        _ = session.mergeTableCells(id, rows: 0...1, columns: 0...1)
        session.undo()
        session.redo()
        let fragment = session.fragment(of: .cells(table: id, anchor: NoteTableSpanTestsSupport.cell(1, 1), head: NoteTableSpanTestsSupport.cell(2, 2)))
        #expect(fragment.first?.props.table?.rowCount == 3 && fragment.first?.props.table?.merges.count == 1, "copy grows to whole merges")
    }

    @Test func fillingASessionColumnCopiesTheTopCell() throws {
        let session = NotePageSession(page: NoteTableSpanTestsSupport.page(NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])))
        let id = try #require(session.page.blocks.first?.id, "no table")
        #expect(session.fillTableCells(id, .down, rows: 0...2, columns: 2...2), "session fill")
        #expect(session.page.blocks.first?.props.table?.rows[2][2].string == "c", "filled")
    }

    @Test func aSessionCanColorItsCells() throws {
        let session = NotePageSession(page: NoteTableSpanTestsSupport.page(NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])))
        let id = try #require(session.page.blocks.first?.id, "no table")
        #expect(session.setTableCellColor(id, .background(.red), rows: 0...0, columns: 2...2), "session colour")
    }

    @Test func aSessionCanResizeItsTable() throws {
        let session = NotePageSession(page: NoteTableSpanTestsSupport.page(NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])))
        let id = try #require(session.page.blocks.first?.id, "no table")
        #expect(session.resizeTable(id, rows: 5, columns: 4), "session resize")
        #expect(session.page.blocks.first?.props.table?.rowCount == 5, "resized")
    }

    @Test func aSessionCanUnmergeFromACoveredCell() throws {
        let session = NotePageSession(page: NoteTableSpanTestsSupport.page(NoteTableSpanTestsSupport.grid([["a", "b", "c"], ["d", "e", "f"], ["g", "h", "i"]])))
        let id = try #require(session.page.blocks.first?.id, "no table")
        session.setSelection(.cells(table: id, anchor: NoteTableSpanTestsSupport.cell(0, 0), head: NoteTableSpanTestsSupport.cell(1, 1)))
        _ = session.mergeTableCells(id, rows: 0...1, columns: 0...1)
        #expect(session.unmergeTableCells(id, rows: 1...1, columns: 1...1), "session unmerge")
        #expect(session.page.blocks.first?.props.table?.merges.isEmpty == true, "unmerged")
    }
}
