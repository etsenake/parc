import Foundation
import Testing
@testable import ParcCore

struct NoteTextTestsTypingTests: NoteFixtures {
    private var styledText: NoteText {
        let linked = marks { $0.link = "https://parc.example"; $0.bold = true }
        return NoteText(pieces: [("Bold", boldMarks), (" link", linked), (" tail", italicMarks)])
    }

    @Test
    func emptyTextTypesPlain() {
        #expect(NoteText().typingMarks(at: 0) == .plain, "empty text types plain")
    }

    @Test
    func typingAtTheStartTakesTheFirstLettersStyleWithoutALink() {
        let text = styledText
        #expect(text.typingMarks(at: 0).bold, "typing at the very start takes the first letter's marks")
        #expect(text.typingMarks(at: 0).link == nil, "but never starts a link")
    }

    @Test
    func typingInsideBoldKeepsBold() {
        let text = styledText
        #expect(text.typingMarks(at: 2).bold, "typing inside bold stays bold")
    }

    @Test
    func typingAtTheEndOfBoldKeepsBoldWithoutEnteringTheLink() {
        let text = styledText
        #expect(text.typingMarks(at: 4).bold && text.typingMarks(at: 4).link == nil, "typing at the end of bold continues bold without the link ahead")
    }

    @Test
    func typingInsideALinkExtendsIt() {
        let text = styledText
        #expect(text.typingMarks(at: 6).link == "https://parc.example", "typing inside a link extends it")
    }

    @Test
    func typingAtTheEndOfALinkKeepsOtherMarksWithoutTheLink() {
        let text = styledText
        #expect(text.typingMarks(at: 9).link == nil, "typing at the end of a link doesn't extend it")
        #expect(text.typingMarks(at: 9).bold, "but keeps its other marks")
    }

    @Test
    func typingAtTheEndKeepsTheLastStyle() {
        let text = styledText
        #expect(text.typingMarks(at: text.length).italic, "typing at the end continues the last style")
    }

    @Test
    func typingOffsetsClampToTheText() {
        let text = styledText
        #expect(text.typingMarks(at: -3).bold && text.typingMarks(at: 500).italic, "out-of-range offsets clamp")
    }

    @Test
    func typingOnEitherEdgeOfALinkUsesPlainMarks() {
        let linkFirst = NoteText(pieces: [("site", marks { $0.link = "x" })])
        #expect(linkFirst.typingMarks(at: 0) == .plain, "typing before a leading link is plain")
        #expect(linkFirst.typingMarks(at: 4) == .plain, "and so is typing after a trailing one")
    }

    @Test
    func typingAfterAMentionDoesNotCopyTheMention() {
        let mention = NoteText("Hi ") + NoteText.atom(.page(target: "a.md", title: "A"), marks: marks { $0.color = .text(.blue) })
        #expect(mention.typingMarks(at: mention.length).atom == nil, "typing after a mention never copies the mention")
    }

    @Test
    func insertingAStringUsesTypingMarks() {
        var typed = NoteText(pieces: [("ab", boldMarks)])
        typed.insert("X", at: 0)
        #expect(typed.allHave(.bold, in: 0..<3), "insert(String) uses the typing marks")
    }
}
