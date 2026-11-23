import Foundation
import Testing
@testable import ParcCore

struct NoteSavedTextTests {
    private func tampered(string: String, spanLengths: [Int]) throws -> Data {
        var bold = NoteMarks.plain
        bold.bold = true
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteText("abc", marks: bold))) as? [String: Any])
        let template = try #require((object["spans"] as? [[String: Any]])?.first)
        object["string"] = string
        object["spans"] = spanLengths.map { length -> [String: Any] in
            var span = template
            span["length"] = length
            return span
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test(arguments: [[2, 50], [2], [-3, 6], [0, 3], [4, -1], [3, 3]] as [[Int]])
    func spansThatDisagreeWithTheTextAreRejected(_ lengths: [Int]) throws {
        let data = try tampered(string: "abc", spanLengths: lengths)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(NoteText.self, from: data) }
    }

    @Test func textWithCharactersButNoSpansIsRejected() throws {
        let data = try tampered(string: "abc", spanLengths: [])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(NoteText.self, from: data) }
    }

    @Test func spansThatSplitAnEmojiPairAreAcceptedBecauseTheyCoverTheText() throws {
        let data = try tampered(string: "😀", spanLengths: [1, 1])
        let text = try JSONDecoder().decode(NoteText.self, from: data)
        #expect(text.length == 2)
    }

    @Test func anAtomSpanLongerThanOneCharacterIsRejected() throws {
        var marks = NoteMarks.plain
        marks.atom = .equation("x")
        let data = try JSONEncoder().encode(NoteText(NoteAtom.character, marks: marks))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["string"] = NoteAtom.character + NoteAtom.character
        var spans = try #require(object["spans"] as? [[String: Any]])
        spans[0]["length"] = 2
        object["spans"] = spans
        let bad = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(NoteText.self, from: bad) }
    }

    @Test func anAtomSpanOverARegularCharacterIsRejected() throws {
        var marks = NoteMarks.plain
        marks.atom = .equation("x")
        let data = try JSONEncoder().encode(NoteText(NoteAtom.character, marks: marks))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["string"] = "a"
        let bad = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(NoteText.self, from: bad) }
    }

    @Test func validTextWithMarksAndObjectsRoundTrips() throws {
        var bold = NoteMarks.plain
        bold.bold = true
        var link = NoteMarks.plain
        link.link = "https://example.test"
        let original = NoteText(pieces: [("plain ", .plain), ("bold", bold), ("😀 é", link)])
            + NoteText.atom(.equation("x^2"))
            + NoteText("tail")
        let reread = try JSONDecoder().decode(NoteText.self, from: JSONEncoder().encode(original))
        #expect(reread == original)
        #expect(NoteText().string.isEmpty)
        #expect(try JSONDecoder().decode(NoteText.self, from: JSONEncoder().encode(NoteText())) == NoteText())
    }

    @Test func aBlockWithOutOfRangeSettingsIsRejected() throws {
        var block = NoteBlock(.paragraph, text: NoteText("a"))
        var props = block.props
        props.listStart = Int.max
        block.props = props
        let data = try JSONEncoder().encode(block)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(NoteBlock.self, from: data) }
        props.listStart = nil
        props.level = 40
        block.props = props
        let levelData = try JSONEncoder().encode(block)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(NoteBlock.self, from: levelData) }
    }

    @Test func aBlockWithOrdinarySettingsRoundTrips() throws {
        var block = NoteBlock.heading(3, NoteText("Title"))
        var props = block.props
        props.listStart = 7
        block.props = props
        let reread = try JSONDecoder().decode(NoteBlock.self, from: JSONEncoder().encode(block))
        #expect(reread == block)
    }

    @Test func aSavedTableWithNoRowsGetsOne() throws {
        let table = try JSONDecoder().decode(NoteTable.self, from: Data(#"{"rows":[]}"#.utf8))
        #expect(table.rowCount == 1)
        #expect(table.columnCount == 1)
    }

    @Test func aSavedTableWithRaggedRowsIsMadeRectangular() throws {
        let table = NoteTable(rows: [[NoteText("a"), NoteText("b")], [NoteText("c")]])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(table)) as? [String: Any])
        var rows = try #require(object["rows"] as? [[Any]])
        rows[1].removeLast()
        object["rows"] = rows
        let reread = try JSONDecoder().decode(NoteTable.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(reread.rows.allSatisfy { $0.count == 2 })
    }

    @Test func columnWidthsThatAreNotNumbersAreForgotten() {
        var table = NoteTable(rows: [[NoteText("a"), NoteText("b"), NoteText("c")]])
        table.columnWidths = [.infinity, .nan, 80]
        table.normalize()
        #expect(table.columnWidths == [nil, nil, 80])
    }
}
