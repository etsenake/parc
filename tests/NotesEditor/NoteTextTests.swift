import Foundation

@main
struct NoteTextTests {
    static func main() {
        typingMarks()
        slicingAndReplacing()
        markUpdates()
        links()
        composedCharacters()
        plainTextAndAtoms()
        print("NoteTextTests passed")
    }

    static func typingMarks() {
        expectEqual(NoteText().typingMarks(at: 0), .plain, "empty text types plain")
        let linked = marks { $0.link = "https://parc.example"; $0.bold = true }
        let text = NoteText(pieces: [("Bold", boldMarks), (" link", linked), (" tail", italicMarks)])
        expect(text.typingMarks(at: 0).bold, "typing at the very start takes the first letter's marks")
        expect(text.typingMarks(at: 0).link == nil, "but never starts a link")
        expect(text.typingMarks(at: 2).bold, "typing inside bold stays bold")
        expect(text.typingMarks(at: 4).bold && text.typingMarks(at: 4).link == nil, "typing at the end of bold continues bold without the link ahead")
        expect(text.typingMarks(at: 6).link == "https://parc.example", "typing inside a link extends it")
        expect(text.typingMarks(at: 9).link == nil, "typing at the end of a link doesn't extend it")
        expect(text.typingMarks(at: 9).bold, "but keeps its other marks")
        expect(text.typingMarks(at: text.length).italic, "typing at the end continues the last style")
        expect(text.typingMarks(at: -3).bold && text.typingMarks(at: 500).italic, "out-of-range offsets clamp")
        let linkFirst = NoteText(pieces: [("site", marks { $0.link = "x" })])
        expectEqual(linkFirst.typingMarks(at: 0), .plain, "typing before a leading link is plain")
        expectEqual(linkFirst.typingMarks(at: 4), .plain, "and so is typing after a trailing one")
        let mention = NoteText("Hi ") + NoteText.atom(.page(target: "a.md", title: "A"), marks: marks { $0.color = .text(.blue) })
        expect(mention.typingMarks(at: mention.length).atom == nil, "typing after a mention never copies the mention")
        var typed = NoteText(pieces: [("ab", boldMarks)])
        typed.insert("X", at: 0)
        expect(typed.allHave(.bold, in: 0..<3), "insert(String) uses the typing marks")
    }

    static func slicingAndReplacing() {
        let text = NoteText(pieces: [("one ", .plain), ("two", boldMarks), (" three", .plain)])
        let middle = text.slice(2..<9)
        expectEqual(middle.string, "e two t", "slices cut across spans")
        expectEqual(middle.spans.count, 3, "keeping the span boundaries")
        var edited = text
        edited.replace(4..<7, with: NoteText("2", marks: boldMarks))
        expectEqual(edited.string, "one 2 three", "replace swaps the range")
        expectEqual(edited.spans.count, 3, "and normalizes neighbouring spans")
        edited.delete(0..<100)
        expect(edited.isEmpty && edited.spans.isEmpty, "deleting everything leaves no spans")
        var joined = NoteText("a", marks: boldMarks)
        joined.append(NoteText("b", marks: boldMarks))
        expectEqual(joined.spans, [NoteSpan(length: 2, marks: boldMarks)], "equal neighbours merge")
        let atoms = NoteText.atom(.equation("x")) + NoteText.atom(.equation("y"))
        expectEqual(atoms.spans.count, 2, "atoms never merge into one span")
        expectEqual(NoteText("a\n\r\n").trimmingTrailingNewlines().string, "a", "trailing newlines trim")
    }

    static func markUpdates() {
        var text = NoteText("Hello ") + NoteText.atom(.equation("e=mc^2")) + NoteText(" world")
        text.updateMarks(in: 0..<text.length) { $0 = .plain; $0.bold = true }
        expect(text.allHave(.bold, in: 0..<text.length), "marks apply to the whole range")
        expect(text.marks(at: 6).atom == .equation("e=mc^2"), "mark changes never strip an atom")
        text.updateMarks(in: 0..<5) { $0.bold = false }
        expect(!text.allHave(.bold, in: 0..<text.length) && text.allHave(.bold, in: 5..<text.length), "partial updates split spans")
        expect(!NoteText("plain").allHave(.bold, in: 0..<0), "an empty range has no marks")
    }

    static func links() {
        let link = marks { $0.link = "https://a" }
        let other = marks { $0.link = "https://b" }
        let boldLink = marks { $0.link = "https://a"; $0.bold = true }
        let text = NoteText(pieces: [("go ", .plain), ("he", link), ("re", boldLink), (" now", .plain), ("x", other)])
        expectEqual(text.linkRange(at: 4), 3..<7, "a link spans runs with different styles")
        expectEqual(text.linkRange(at: 3), 3..<7, "a caret at the link's start finds it")
        expectEqual(text.linkRange(at: 7), 3..<7, "a caret at the link's end finds it")
        expectEqual(text.linkRange(at: 1), nil, "plain text has no link")
        expectEqual(text.linkRange(at: 11), 11..<12, "neighbouring links stay separate")
    }

    static func composedCharacters() {
        let text = NoteText("a👍🏽é\u{301}b")
        expectEqual(text.composedRange(before: 5), 1..<5, "the skin-toned emoji is one character")
        expectEqual(text.composedRange(after: 1), 1..<5, "from either side")
        expectEqual(text.composedRange(before: 0), nil, "nothing before the start")
        expectEqual(text.composedRange(after: text.length), nil, "nothing after the end")
        expectEqual(text.composedRange(before: 7), 5..<7, "an accent rides with its letter")
    }

    static func plainTextAndAtoms() {
        let date = NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 5)
        let text = NoteText("Due ") + NoteText.atom(.date(date)) + NoteText(" for ") + NoteText.atom(.page(target: "p.md", title: "Plan"))
            + NoteText(" ") + NoteText.atom(.link(url: "https://x", title: ""))
        expectEqual(text.plainText, "Due 2026-11-20 09:05 for Plan https://x", "atoms read as their fallback text")
        expectEqual(text.length, 13, "each atom is one character")
        let decoded = try? JSONDecoder().decode(NoteText.self, from: JSONEncoder().encode(text))
        expectEqual(decoded, text, "text round-trips through Codable")
        let blockData = try? JSONEncoder().encode(NoteBlock(.callout, text: text, props: NoteBlockProps(), color: .background(.red), children: [.paragraph("x")]))
        let block = blockData.flatMap { try? JSONDecoder().decode(NoteBlock.self, from: $0) }
        expect(block?.text == text && block?.color == .background(.red) && block?.children.count == 1, "blocks round-trip through Codable")
        var page = NotePage(blocks: [.paragraph("a")])
        page.settings.fullWidth = true
        let decodedPage = (try? JSONEncoder().encode(page)).flatMap { try? JSONDecoder().decode(NotePage.self, from: $0) }
        expectEqual(decodedPage, page, "pages round-trip through Codable")
        var copy = NoteBlock.paragraph("shared")
        let original = copy
        copy.props.level = 3
        expect(original.props.level == 1 && copy.props.level == 3, "block props keep value semantics")
        expect(original != copy && original.hashValue != copy.hashValue, "and equality sees the change")
    }
}
