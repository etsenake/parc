import Foundation
import Testing
@testable import ParcCore

struct NoteCustomEmojiCodecTestsNameTests {
    private typealias Fixture = NoteCustomEmojiCodecTestsSupport

    struct NameCase: Sendable, CustomTestStringConvertible {
        let input: String
        let expected: String?

        init(_ input: String, _ expected: String?) {
            self.input = input
            self.expected = expected
        }

        var testDescription: String { input.debugDescription }
    }

    @Test(arguments: [
        NameCase("Party Parrot!", "party-parrot"), NameCase("  :Fiesta: ", "fiesta"),
        NameCase("Crème brûlée", "creme-brulee"), NameCase("😀", nil),
        NameCase("__--__", nil), NameCase("thumbs_up+1", "thumbs_up+1"),
    ])
    func emojiNamesNormalizeToTheExpectedShortcode(fixture: NameCase) {
        #expect(NoteCustomEmojiName.normalized(fixture.input) == fixture.expected)
    }

    @Test
    func normalizedNamesStopAtTheMaximumLength() {
        #expect(NoteCustomEmojiName.normalized(String(repeating: "a", count: 80))?.count == NoteCustomEmojiName.maximumLength, "names are capped")
    }

    struct ValidationCase: Sendable, CustomTestStringConvertible {
        let input: String
        let expected: Bool

        init(_ input: String, _ expected: Bool) {
            self.input = input
            self.expected = expected
        }

        var testDescription: String { input.debugDescription }
    }

    @Test(arguments: [
        ValidationCase("party", true), ValidationCase("Party", false), ValidationCase("par ty", false),
    ])
    func onlyLowercaseEmojiNamesAreValid(fixture: ValidationCase) {
        #expect(NoteCustomEmojiName.isValid(fixture.input) == fixture.expected)
    }

    struct ReferenceCase: Sendable, CustomTestStringConvertible {
        let input: String
        let expected: String?

        init(_ input: String, _ expected: String?) {
            self.input = input
            self.expected = expected
        }

        var testDescription: String { input.debugDescription }
    }

    @Test(arguments: [
        ReferenceCase(":party:", "party"), ReferenceCase("party", nil), ReferenceCase("::", nil), ReferenceCase("🎉", nil),
    ])
    func onlyColonDelimitedNamesReadAsReferences(fixture: ReferenceCase) {
        #expect(NoteCustomEmojiName.name(inReference: fixture.input) == fixture.expected)
    }

    @Test
    func anEmojiAtomFallsBackToItsShortcode() {
        #expect(NoteAtom.customEmoji("party").fallbackText == ":party:", "a custom emoji falls back to its shortcode")
    }

    @Test
    func aPageListsEmojiFromTextAndTableCells() {
        let page = NotePage(blocks: [NoteBlock.paragraph(Fixture.text("Hi ", Fixture.atom("party"))), NoteBlock(.table, props: {
            var props = NoteBlockProps()
            props.table = NoteTable(rows: [[Fixture.atom("parrot")]])
            return props
        }())])
        #expect(NoteCustomEmojiName.names(in: page) == ["party", "parrot"], "pages list the custom emoji they use, cells included")
    }
}
