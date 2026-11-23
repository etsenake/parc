import Foundation
import Testing
@testable import ParcCore

struct NoteTableDecodeTests {
    @Test func aDecodedTableWithCorruptMergesIsRepairedOnTheWay() throws {
        var table = NoteTable.empty(rows: 1, columns: 1)
        table.merges = [NoteTableMerge(row: 0, column: 0, rowSpan: .max, columnSpan: .max)]
        let decoded = try JSONDecoder().decode(NoteTable.self, from: JSONEncoder().encode(table))
        #expect(decoded.merges.isEmpty)
        #expect(decoded.visibleCells.count == 1)
    }
}
