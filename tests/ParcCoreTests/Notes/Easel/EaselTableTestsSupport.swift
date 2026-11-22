import Foundation
import Testing
@testable import ParcCore

enum EaselTableTestsSupport {
    static func cell(_ row: Int, _ column: Int) -> EaselTableCoordinate { EaselTableCoordinate(row: row, column: column) }

    static func filled(_ rows: [[String]]) -> EaselTable {
        var table = EaselTable.blank(columns: rows.first?.count ?? 1, rows: rows.count)
        for (r, row) in rows.enumerated() { for (c, text) in row.enumerated() { table.cells[r][c].text = text } }
        return table
    }

    static func rejects(_ table: EaselTable, _ message: String) {
        do { try table.validate(); Issue.record(Comment(rawValue: message)) } catch {}
    }
}
