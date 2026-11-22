import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLReaderTestsTableTests {
    private typealias Fixture = NoteHTMLReaderTestsSupport

    private func importedBlocks() -> [NoteBlock] {
        let html = """
        <table><tr><td colspan="2"><b>Plan</b></td></tr><tr><td>Mon</td><td><ul><li>Gym</li><li>Read<ol><li>Book</li></ol></li></ul></td></tr></table>
        <table role="presentation"><tr><td><h3>Inside layout</h3></td><td><p>Side text</p></td></tr></table>
        <table><tr><td><p>Only cell</p></td></tr></table>
        <table><caption>Scores</caption><tr><th>Name</th><th>Score</th></tr><tr><td>Ann<td style="text-align:right">10<tr><td>Bo</td><td>7</td></tr></table>
        <table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>
        """
        return Fixture.read(html)
    }

    private func blocks() throws -> [NoteBlock] {
        let blocks = importedBlocks()
        try #require(blocks.count == 7)
        return blocks
    }

    @Test
    func theImportKeepsTheExpectedBlockOrder() {
        let blocks = importedBlocks()
        Fixture.shape(blocks, ["table", "heading", "paragraph", "paragraph", "paragraph", "table", "table"], "Tables")
    }

    @Test
    func spanningCellsArePaddedAndListsFlattenToCellText() throws {
        let blocks = try blocks()
        let table = try #require(blocks[0].props.table)
        #expect(table.rows.map { $0.map(\.string) } == [["Plan", ""], ["Mon", "• Gym\n• Read\n  1. Book"]], "colspan pads and lists flatten into cell text: \(table.rows.map { $0.map(\.string) })")
    }

    @Test
    func aBoldSpanningRowBecomesAHeader() throws {
        let blocks = try blocks()
        let table = try #require(blocks[0].props.table)
        #expect(table.headerRow, "bold spanning row is the header")
    }

    @Test
    func presentationTablesUnwrapTheirBlocks() throws {
        let blocks = try blocks()
        #expect(blocks[1].text.string == "Inside layout" && blocks[2].text.string == "Side text", "layout tables unwrap")
    }

    @Test
    func singleCellTablesUnwrapTheirText() throws {
        let blocks = try blocks()
        #expect(blocks[3].text.string == "Only cell", "a single cell unwraps")
    }

    @Test
    func aTableCaptionComesFirst() throws {
        let blocks = try blocks()
        #expect(blocks[4].text.string == "Scores", "captions come first")
    }

    @Test
    func impliedRowAndCellEndsKeepTheTableShape() throws {
        let blocks = try blocks()
        let table = try #require(blocks[5].props.table)
        #expect(table.headerRow && table.rows.map { $0.map(\.string) } == [["Name", "Score"], ["Ann", "10"], ["Bo", "7"]], "implied tr and td ends")
    }

    @Test
    func plainTablesHaveNoHeader() throws {
        let blocks = try blocks()
        #expect(blocks[6].props.table?.headerRow == false, "plain tables have no header")
    }
}
