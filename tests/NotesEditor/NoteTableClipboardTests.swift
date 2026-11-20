import Foundation

@main @MainActor
struct NoteTableClipboardTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        parsing()
        writing()
        pasting()
        print("NoteTableClipboardTests passed")
    }

    static func cell(_ row: Int, _ column: Int) -> NoteTableCell { NoteTableCell(row: row, column: column) }

    static func parsing() {
        expect(NoteTableClipboard.grid(fromDelimited: "a\tb\nc\td\n") == [["a", "b"], ["c", "d"]], "tsv with a trailing newline")
        expect(NoteTableClipboard.grid(fromDelimited: "a\tb\r\nc\td") == [["a", "b"], ["c", "d"]], "tsv with windows line endings")
        expect(NoteTableClipboard.grid(fromDelimited: "a\tb\tc\nd") == [["a", "b", "c"], ["d", "", ""]], "ragged rows pad out")
        expect(NoteTableClipboard.grid(fromDelimited: "one\ttwo") == [["one", "two"]], "a single tab-separated line is tabular")
        expect(NoteTableClipboard.grid(fromDelimited: "\"line one\nline two\"\tb\nc\td") == [["line one\nline two", "b"], ["c", "d"]],
               "quoted tsv cells keep their line breaks")
        expect(NoteTableClipboard.grid(fromDelimited: "\"say \"\"hi\"\"\"\tx") == [["say \"hi\"", "x"]], "doubled quotes unescape")
        expect(NoteTableClipboard.grid(fromDelimited: "name,age\nAda,36\nAlan,41") == [["name", "age"], ["Ada", "36"], ["Alan", "41"]], "csv")
        expect(NoteTableClipboard.grid(fromDelimited: "a,\"b, c\"\nd,e") == [["a", "b, c"], ["d", "e"]], "csv quoted commas")
        expect(NoteTableClipboard.grid(fromDelimited: "Hello, world") == nil, "a sentence with a comma is just text")
        expect(NoteTableClipboard.grid(fromDelimited: "Dear Ada,\nThanks, really, for everything.") == nil, "prose lines with commas stay text")
        expect(NoteTableClipboard.grid(fromDelimited: "just words") == nil, "plain text is not tabular")
        expect(NoteTableClipboard.grid(fromDelimited: "line one\nline two") == nil, "lines without separators are not tabular")
        expect(NoteTableClipboard.grid(fromDelimited: "") == nil, "empty is nothing")
        expect(NoteTableClipboard.parse("a,,b", separator: ",") == [["a", "", "b"]], "empty fields survive")
    }

    static func writing() {
        var bold = NoteMarks.plain
        bold.bold = true
        var linked = NoteMarks.plain
        linked.link = "https://parc.example/?a=1&b=2"
        let rows: [[NoteText]] = [[NoteText("Name", marks: bold), "Notes"],
                                  [NoteText(pieces: [("see ", .plain), ("site", linked)]), "tab\there"],
                                  ["a < b", "two\nlines"]]
        expect(NoteTableClipboard.tsv(rows) == "Name\tNotes\nsee site\t\"tab\there\"\na < b\t\"two\nlines\"", "tsv quotes awkward cells")
        let tsvBack = NoteTableClipboard.grid(fromDelimited: NoteTableClipboard.tsv(rows))
        expect(tsvBack == rows.map { $0.map(\.plainText) }, "tsv round trips")
        let html = NoteTableClipboard.html(rows, headerRow: true, headerColumn: false, alignments: [nil, .center])
        expect(html.hasPrefix("<table><thead><tr><th><strong>Name</strong></th><th style=\"text-align: center\">Notes</th></tr></thead><tbody>"),
               "html header row")
        expect(html.contains("<a href=\"https://parc.example/?a=1&amp;b=2\">site</a>"), "html links escape")
        expect(html.contains("<td>a &lt; b</td>") && html.contains("two<br>lines"), "html escapes text and breaks lines")
        expect(html.hasSuffix("</tr></tbody></table>"), "html closes the body")
        let headerColumn = NoteTableClipboard.html([["x", "y"]], headerRow: false, headerColumn: true, alignments: [])
        expect(headerColumn == "<table><tbody><tr><th>x</th><td>y</td></tr></tbody></table>", "html header column")
        var source = NoteTable(rows: [["a|b", "c", "z"], ["d", "e\nf", "y"]], headerRow: true, headerColumn: true)
        source.normalize()
        source.alignments = [.right, nil, .center]
        source.columnWidths = [nil, 210, 90]
        let whole = NoteTableClipboard.slice(NoteTableRect(cell(0, 0), cell(1, 2)), of: source)
        expect(NoteTableClipboard.markdown(whole) == NoteMarkdown.serialize(NotePage(blocks: [NoteBlock(.table, props: { var props = NoteBlockProps(); props.table = source; return props }())])).trimmingCharacters(in: .newlines),
               "copied Markdown is exactly what the note file would say")
        let part = NoteTableClipboard.markdown(NoteTableClipboard.slice(NoteTableRect(cell(1, 1), cell(1, 2)), of: source))
        expect(part == "| e<br>f | y   |\n| ------ | :-: |\n<!-- parc no-header-row widths=\"210,90\" -->", "a slice keeps breaks, alignment and widths: \(part)")
        let back = NoteMarkdown.parse(part).blocks.first?.props.table
        expect(back?.rows.first?.map(\.string) == ["e\nf", "y"] && back?.columnWidths == [210, 90] && back?.headerRow == false,
               "and reads straight back into a table")
        let corner = NoteTableClipboard.slice(NoteTableRect(cell(0, 0), cell(0, 0)), of: source)
        expect(corner.headerRow && corner.headerColumn && corner.alignments == [.right], "a top-left slice keeps the headers")
    }

    static func pasting() {
        var table = NoteTable.empty(rows: 2, columns: 2)
        let grid = NoteTableClipboard.cells(from: [["1", "2", "3"], ["4", "5", "6"]])
        let pasted = NoteTableTransforms.paste(grid, into: &table, at: cell(1, 1))
        expect(pasted == NoteTableRect(cell(1, 1), cell(2, 3)), "paste reports the filled rectangle")
        expect(table.rowCount == 3 && table.columnCount == 4, "paste grows rows and columns")
        expect(table.rows[1].map(\.string) == ["", "1", "2", "3"] && table.rows[2].map(\.string) == ["", "4", "5", "6"], "paste lands at the caret cell")
        expect(table.alignments.count == 4 && table.columnWidths.count == 4, "growth keeps column metadata aligned")
        var fill = NoteTable.empty(rows: 3, columns: 3)
        let filled = NoteTableTransforms.paste([["x"]], into: &fill, at: cell(0, 0), filling: NoteTableRect(cell(0, 0), cell(1, 1)))
        expect(filled == NoteTableRect(cell(0, 0), cell(1, 1)), "a single value fills the selection")
        expect(fill.rows[0][0].string == "x" && fill.rows[1][1].string == "x" && fill.rows[2][2].isEmpty && fill.rowCount == 3, "fill stays inside")
        var start = NoteTable.empty(rows: 3, columns: 3)
        NoteTableTransforms.paste([["a", "b"]], into: &start, at: cell(2, 2), filling: NoteTableRect(cell(1, 0), cell(2, 1)))
        expect(start.rows[1][0].string == "a" && start.rows[1][1].string == "b" && start.columnCount == 3, "a range paste starts at the selection's corner")
        var ragged = NoteTable.empty(rows: 1, columns: 1)
        NoteTableTransforms.paste([["a", "b"], ["c"]], into: &ragged, at: cell(0, 0))
        expect(ragged.rows.map { $0.map(\.string) } == [["a", "b"], ["c", ""]], "ragged pastes pad with empty cells")
        expect(NoteTableTransforms.paste([], into: &ragged, at: cell(0, 0)) == nil, "nothing to paste")
        expect(NoteTableTransforms.slice(NoteTableRect(cell(0, 1), cell(1, 1)), of: ragged).map { $0.map(\.string) } == [["b"], [""]], "slice")
    }
}
