import Foundation
import Testing
@testable import ParcCore

struct NoteCustomEmojiCodecTestsMarkdownTests {
    private typealias Fixture = NoteCustomEmojiCodecTestsSupport

    @Test
    func aKnownNameReadsAsAnEmojiAtom() {
        #expect(Fixture.firstText("Hi :party: there") == Fixture.text("Hi ", Fixture.atom("party"), " there"), "a known name reads as a custom emoji")
    }

    @Test
    func anEmptyLibraryLeavesAShortcodeAsText() {
        #expect(Fixture.firstText("Hi :party: there", names: []) == "Hi :party: there", "without a library it stays text")
    }

    @Test
    func anUnknownShortcodeStaysText() {
        #expect(Fixture.firstText("Hi :nope: there") == "Hi :nope: there", "names the library lacks stay text")
    }

    @Test
    func anEscapedColonPreventsAnEmojiMatch() {
        #expect(Fixture.firstText("Hi \\:party: there") == "Hi :party: there", "an escaped colon keeps the text")
    }

    @Test
    func aShortcodeInsideACodeSpanStaysCode() {
        #expect(Fixture.firstText("`:party:`").string == ":party:" && Fixture.firstText("`:party:`").marks(at: 0).code, "code spans stay code")
    }

    @Test
    func adjacentShortcodesProduceSeparateEmoji() {
        #expect(Fixture.firstText(":party::parrot:") == Fixture.text(Fixture.atom("party"), Fixture.atom("parrot")), "neighbours read one by one")
    }

    @Test
    func timesDoNotTurnIntoEmoji() {
        #expect(Fixture.firstText("10:30:00") == "10:30:00", "times don't turn into emoji")
    }

    @Test
    func theFirstShortcodeMatchClaimsItsClosingColon() {
        #expect(Fixture.firstText("x:a:b:") == Fixture.text("x", Fixture.atom("a"), "b:"), "the first match wins and its colon is spent")
    }

    @Test
    func emojiNamesCanContainPlusSigns() {
        #expect(Fixture.firstText("thumbs :+1:") == Fixture.text("thumbs ", Fixture.atom("+1")), "plus signs work in names")
    }

    @Test
    func plainTextSerializationKeepsTheShortcode() {
        #expect(NotePlainText.serialize(NotePage(blocks: [.paragraph(Fixture.text("Yay ", Fixture.atom("party")))])) == "Yay :party:", "plain text keeps the shortcode")
    }

    @Test
    func emojiAtomsWriteTheirShortcodes() {
        #expect(Fixture.write(Fixture.text("Hi ", Fixture.atom("party"), " there")) == "Hi :party: there\n", "a custom emoji writes as its shortcode")
    }

    @Test
    func emojiAtomsWriteShortcodesWithoutALibrary() {
        #expect(Fixture.write(Fixture.text("Hi ", Fixture.atom("party")), names: []) == "Hi :party:\n", "it writes plainly without a library too")
    }

    @Test
    func aKnownShortcodeInPlainTextIsEscaped() {
        #expect(Fixture.write("Hi :party: there") == "Hi \\:party: there\n", "text that would read as a known emoji is escaped")
    }

    @Test
    func literalShortcodesStayUnescapedWithoutALibrary() {
        #expect(Fixture.write("Hi :party: there", names: []) == "Hi :party: there\n", "unknown shortcodes are left alone")
    }

    @Test
    func anUnknownShortcodeStaysUnescaped() {
        #expect(Fixture.write("Hi :nope: there") == "Hi :nope: there\n", "names the library lacks are left alone")
    }

    @Test
    func literalShortcodesAreEscapedWhenTheSameAtomIsUsed() {
        #expect(Fixture.write(Fixture.text("Hi :party: and ", Fixture.atom("party")), names: []) == "Hi \\:party: and :party:\n", "text beside a used emoji gets escaped")
    }

    @Test
    func ordinaryColonsStayUnescaped() {
        #expect(Fixture.write("10:30:00") == "10:30:00\n", "ordinary colons are never escaped")
    }

    @Test
    func anEmojiAtomCanLeadItsParagraph() {
        #expect(Fixture.write(Fixture.text(Fixture.atom("party"), "**")).hasPrefix(":party:"), "atoms lead cleanly")
    }

    @Test
    func anEmojiAtomTakesBoldMarks() {
        let bold = Fixture.firstText("**:party:**")
        #expect(bold.length == 1 && bold.marks(at: 0).bold && bold.marks(at: 0).atom == .customEmoji("party"), "custom emoji take marks")
    }

    @Test
    func anEmojiAtomCanLiveInsideALink() {
        let linked = Fixture.firstText("[go :party:](https://example.com)")
        #expect(linked.marks(at: 3).atom == .customEmoji("party") && linked.marks(at: 3).link == "https://example.com", "custom emoji live inside links")
    }

    @Test
    func headingsCanContainEmojiAtoms() {
        let heading = NoteMarkdown.parse("## Plans :party:", customEmoji: Fixture.names).blocks.first
        #expect(heading?.kind == .heading && heading?.text == Fixture.text("Plans ", Fixture.atom("party")), "headings read them too")
    }

    @Test
    func tableCellsCanContainEmojiAtoms() {
        let table = NoteMarkdown.parse("| a | b |\n| - | - |\n| :party: | x |", customEmoji: Fixture.names).blocks.first
        #expect(table?.props.table?.rows[1][0] == Fixture.atom("party"), "table cells read them too")
    }

    struct RoundTripCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let makeText: @Sendable () -> NoteText

        init(_ label: String, _ makeText: @escaping @Sendable () -> NoteText) {
            testDescription = label
            self.makeText = makeText
        }
    }

    @Test(arguments: [
        RoundTripCase("a known shortcode in prose") { Fixture.text("Hi ", Fixture.atom("party"), " there") },
        RoundTripCase("an incomplete prefix before an atom") { Fixture.text(":b", Fixture.atom("a")) },
        RoundTripCase("colons bracketing an atom") { Fixture.text(":", Fixture.atom("a"), ":") },
        RoundTripCase("overlapping prefixes") { Fixture.text("x:a:", Fixture.atom("b"), ":a") },
        RoundTripCase("a partial suffix after an atom") { Fixture.text(Fixture.atom("a"), "b:") },
        RoundTripCase("an atom between letters") { Fixture.text("a", Fixture.atom("party"), "b") },
        RoundTripCase("literal shortcode text") { Fixture.text("Hi :party: there") },
        RoundTripCase("shortcode-shaped text on both sides") { Fixture.text(":parrot", Fixture.atom("party"), "parrot:") },
        RoundTripCase("an atom between backticks") { Fixture.text("`", Fixture.atom("party"), "`") },
        RoundTripCase("an atom in bold text") { NoteText(pieces: [("bold ", NoteMarks(bold: true)), (NoteAtom.character, { var m = NoteMarks(bold: true); m.atom = .customEmoji("party"); return m }()), (" end", .plain)]) },
    ])
    func shortcodeTextAndEmojiAtomsSurviveAnInlineRoundTrip(fixture: RoundTripCase) {
        let sample = fixture.makeText()
        let markdown = Fixture.write(sample)
        let back = Fixture.firstText(markdown)
        #expect(back == sample, "round trip keeps \(sample.plainText.debugDescription), wrote \(markdown.debugDescription)")
    }

    @Test
    func aFileWithKnownEscapedAndUnknownEmojiSavesByteForByte() {
        let file = "Plans :party:\n\nEscaped \\:party: stays\n\nUnknown :nope: stays\n"
        #expect(NoteMarkdown.serialize(NoteMarkdown.parse(file, customEmoji: Fixture.names), customEmoji: Fixture.names) == file, "files come back byte for byte")
    }

    @Test
    func gitHubShortcodesStayUntouched() {
        let readme = "Ship it :tada: and :+1:\n"
        #expect(NoteMarkdown.serialize(NoteMarkdown.parse(readme)) == readme, "GitHub shortcodes in other files stay untouched")
    }
}
