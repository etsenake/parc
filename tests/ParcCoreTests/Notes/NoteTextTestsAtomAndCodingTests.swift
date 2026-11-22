import Foundation
import Testing
@testable import ParcCore

struct NoteTextTestsAtomAndCodingTests {
    private var text: NoteText {
        let date = NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 5)
        return NoteText("Due ") + NoteText.atom(.date(date)) + NoteText(" for ") + NoteText.atom(.page(target: "p.md", title: "Plan"))
            + NoteText(" ") + NoteText.atom(.link(url: "https://x", title: ""))
    }

    @Test
    func atomsUseFallbackTextInPlainText() {
        #expect(text.plainText == "Due 2026-11-20 09:05 for Plan https://x", "atoms read as their fallback text")
    }

    @Test
    func eachAtomCountsAsOneCharacter() {
        #expect(text.length == 13, "each atom is one character")
    }

    @Test
    func textPreservesItsAtomsThroughCodable() {
        let decoded = try? JSONDecoder().decode(NoteText.self, from: JSONEncoder().encode(text))
        #expect(decoded == text, "text round-trips through Codable")
    }

    @Test
    func codingABlockPreservesItsTextColorAndChildren() {
        let blockData = try? JSONEncoder().encode(NoteBlock(.callout, text: text, props: NoteBlockProps(), color: .background(.red), children: [.paragraph("x")]))
        let block = blockData.flatMap { try? JSONDecoder().decode(NoteBlock.self, from: $0) }
        #expect(block?.text == text && block?.color == .background(.red) && block?.children.count == 1, "blocks round-trip through Codable")
    }

    @Test
    func codingAPagePreservesItsSettingsAndBlocks() {
        var page = NotePage(blocks: [.paragraph("a")])
        page.settings.fullWidth = true
        let decodedPage = (try? JSONEncoder().encode(page)).flatMap { try? JSONDecoder().decode(NotePage.self, from: $0) }
        #expect(decodedPage == page, "pages round-trip through Codable")
    }

    @Test
    func changingBlockPropertiesDoesNotChangeTheOriginal() {
        var copy = NoteBlock.paragraph("shared")
        let original = copy
        copy.props.level = 3
        #expect(original.props.level == 1 && copy.props.level == 3, "block props keep value semantics")
    }

    @Test
    func aPropertyChangeChangesBlockEqualityAndHash() {
        var copy = NoteBlock.paragraph("shared")
        let original = copy
        copy.props.level = 3
        #expect(original != copy && original.hashValue != copy.hashValue, "and equality sees the change")
    }
}
