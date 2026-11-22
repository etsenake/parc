import Foundation
import Testing
@testable import ParcCore

struct NoteTableSpanReferenceTests {
    struct ColumnName: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let index: Int
        let expected: String
    }

    private static let columnNames = [
        ColumnName(testDescription: "A", index: 0, expected: "A"),
        ColumnName(testDescription: "Z", index: 25, expected: "Z"),
        ColumnName(testDescription: "AA", index: 26, expected: "AA"),
        ColumnName(testDescription: "ZZ", index: 701, expected: "ZZ"),
        ColumnName(testDescription: "AAA", index: 702, expected: "AAA"),
    ]

    struct ColumnIndex: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let index: Int
    }

    private static let columnIndices = [
        ColumnIndex(testDescription: "index 0", index: 0),
        ColumnIndex(testDescription: "index 1", index: 1),
        ColumnIndex(testDescription: "index 25", index: 25),
        ColumnIndex(testDescription: "index 26", index: 26),
        ColumnIndex(testDescription: "index 51", index: 51),
        ColumnIndex(testDescription: "index 52", index: 52),
        ColumnIndex(testDescription: "index 701", index: 701),
        ColumnIndex(testDescription: "index 702", index: 702),
        ColumnIndex(testDescription: "index 5000", index: 5000),
    ]

    struct InvalidRange: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let input: String
    }

    private static let invalidRanges = [
        InvalidRange(testDescription: "off table", input: "Z9"),
        InvalidRange(testDescription: "mixed endpoints", input: "A1:B"),
        InvalidRange(testDescription: "empty", input: ""),
        InvalidRange(testDescription: "zero row", input: "A0"),
        InvalidRange(testDescription: "row without a range", input: "1"),
    ]

    @Test(arguments: columnNames) func columnNamesUseSpreadsheetLetters(_ example: ColumnName) {
        #expect(NoteTableReference.columnName(example.index) == example.expected)
    }

    @Test(arguments: columnIndices) func columnNamesRoundTripToTheirIndices(_ example: ColumnIndex) {
        #expect(NoteTableReference.columnIndex(NoteTableReference.columnName(example.index)) == example.index)
    }

    @Test func rangeCornersCanBeGivenInAnyOrder() {
        let range = NoteTableReference.range("C4:A2", rowCount: 10, columnCount: 10)
        #expect(range?.rows == 1...3 && range?.columns == 0...2, "corners in any order")
    }

    @Test func wholeColumnReferencesIncludeAllRows() {
        #expect(NoteTableReference.range("B:C", rowCount: 4, columnCount: 5)?.rows == 0...3, "whole columns")
    }

    @Test func wholeRowReferencesIncludeAllColumns() {
        #expect(NoteTableReference.range("2:3", rowCount: 4, columnCount: 5)?.columns == 0...4, "whole rows")
    }

    @Test func columnReferencesIgnoreCase() {
        #expect(NoteTableReference.range("b2", rowCount: 4, columnCount: 5)?.columns == 1...1, "lowercase is fine")
    }

    @Test(arguments: invalidRanges) func invalidAndOffTableReferencesAreIgnored(_ example: InvalidRange) {
        #expect(NoteTableReference.range(example.input, rowCount: 4, columnCount: 5) == nil)
    }

    @Test func tableRangesClipToTheTableBounds() {
        #expect(NoteTableReference.range("C2:E9", rowCount: 4, columnCount: 4)?.columns == 2...3, "ranges clip to the table")
    }
}
