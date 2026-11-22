import Foundation
import Testing
@testable import ParcCore

enum NoteTableSpanTestsSupport {
    static func cell(_ row: Int, _ column: Int) -> NoteTableCell { NoteTableCell(row: row, column: column) }

    static func grid(_ rows: [[String]]) -> NoteTable {
        NoteTable(rows: rows.map { $0.map { NoteText($0) } })
    }

    static func strings(_ table: NoteTable) -> [[String]] {
        table.rows.map { $0.map(\.string) }
    }

    static func page(_ table: NoteTable) -> NotePage {
        var props = NoteBlockProps()
        props.table = table
        return NotePage(blocks: [NoteBlock(.table, props: props)])
    }
}
