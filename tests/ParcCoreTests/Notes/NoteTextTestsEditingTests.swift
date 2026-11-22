import Foundation
import Testing
@testable import ParcCore

struct NoteTextTestsEditingTests: NoteFixtures {
    @Test
    func aSliceAcrossRunsKeepsItsSpanBoundaries() {
        let text = NoteText(pieces: [("one ", .plain), ("two", boldMarks), (" three", .plain)])
        let middle = text.slice(2..<9)
        #expect(middle.string == "e two t", "slices cut across spans")
        #expect(middle.spans.count == 3, "keeping the span boundaries")
    }

    @Test
    func replacingARangeKeepsNormalizedSpans() {
        let text = NoteText(pieces: [("one ", .plain), ("two", boldMarks), (" three", .plain)])
        var edited = text
        edited.replace(4..<7, with: NoteText("2", marks: boldMarks))
        #expect(edited.string == "one 2 three", "replace swaps the range")
        #expect(edited.spans.count == 3, "and normalizes neighbouring spans")
    }

    @Test
    func deletingEverythingLeavesNoSpans() {
        let text = NoteText(pieces: [("one ", .plain), ("two", boldMarks), (" three", .plain)])
        var edited = text
        edited.replace(4..<7, with: NoteText("2", marks: boldMarks))
        edited.delete(0..<100)
        #expect(edited.isEmpty && edited.spans.isEmpty, "deleting everything leaves no spans")
    }

    @Test
    func adjacentSpansWithTheSameMarksMerge() {
        var joined = NoteText("a", marks: boldMarks)
        joined.append(NoteText("b", marks: boldMarks))
        #expect(joined.spans == [NoteSpan(length: 2, marks: boldMarks)], "equal neighbours merge")
    }

    @Test
    func neighboringAtomsStaySeparate() {
        let atoms = NoteText.atom(.equation("x")) + NoteText.atom(.equation("y"))
        #expect(atoms.spans.count == 2, "atoms never merge into one span")
    }

    @Test
    func trimmingNewlinesDropsBothNewlineSequences() {
        #expect(NoteText("a\n\r\n").trimmingTrailingNewlines().string == "a", "trailing newlines trim")
    }

    @Test
    func markUpdatesApplyAcrossTheRangeAndKeepAnAtom() {
        var text = NoteText("Hello ") + NoteText.atom(.equation("e=mc^2")) + NoteText(" world")
        text.updateMarks(in: 0..<text.length) { $0 = .plain; $0.bold = true }
        #expect(text.allHave(.bold, in: 0..<text.length), "marks apply to the whole range")
        #expect(text.marks(at: 6).atom == .equation("e=mc^2"), "mark changes never strip an atom")
    }

    @Test
    func partialMarkUpdatesSplitSpans() {
        var text = NoteText("Hello ") + NoteText.atom(.equation("e=mc^2")) + NoteText(" world")
        text.updateMarks(in: 0..<text.length) { $0 = .plain; $0.bold = true }
        text.updateMarks(in: 0..<5) { $0.bold = false }
        #expect(!text.allHave(.bold, in: 0..<text.length) && text.allHave(.bold, in: 5..<text.length), "partial updates split spans")
    }

    @Test
    func anEmptyRangeHasNoBoldMarks() {
        #expect(!NoteText("plain").allHave(.bold, in: 0..<0), "an empty range has no marks")
    }

    private var links: NoteText {
        let link = marks { $0.link = "https://a" }
        let other = marks { $0.link = "https://b" }
        let boldLink = marks { $0.link = "https://a"; $0.bold = true }
        return NoteText(pieces: [("go ", .plain), ("he", link), ("re", boldLink), (" now", .plain), ("x", other)])
    }

    struct LinkCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let offset: Int
        let expected: Range<Int>?

        init(_ label: String, _ offset: Int, _ expected: Range<Int>?) {
            testDescription = label
            self.offset = offset
            self.expected = expected
        }
    }

    @Test(arguments: [
        LinkCase("styled runs share a link", 4, 3..<7),
        LinkCase("at the start of a link", 3, 3..<7),
        LinkCase("at the end of a link", 7, 3..<7),
        LinkCase("plain text", 1, nil),
        LinkCase("neighboring link", 11, 11..<12),
    ])
    func linkRangesCoverOnlyTheMatchingLink(fixture: LinkCase) {
        #expect(links.linkRange(at: fixture.offset) == fixture.expected)
    }

    @Test
    func aSkinTonedEmojiIsOneCharacterFromEitherSide() {
        let text = NoteText("a👍🏽é\u{301}b")
        #expect(text.composedRange(before: 5) == 1..<5, "the skin-toned emoji is one character")
        #expect(text.composedRange(after: 1) == 1..<5, "from either side")
    }

    @Test
    func composedCharacterRangesStopAtTheEdges() {
        let text = NoteText("a👍🏽é\u{301}b")
        #expect(text.composedRange(before: 0) == nil, "nothing before the start")
        #expect(text.composedRange(after: text.length) == nil, "nothing after the end")
    }

    @Test
    func anAccentStaysWithItsBaseLetter() {
        let text = NoteText("a👍🏽é\u{301}b")
        #expect(text.composedRange(before: 7) == 5..<7, "an accent rides with its letter")
    }
}
