import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLParserTestsEntityTests {
    @Test
    func theLatin1EntityTableCoversAllNinetySixEntries() {
        #expect(NoteHTMLEntities.latin1Count == 96, "Latin-1 entity table covers 160...255")
    }

    @Test
    func decimalHexAndNamedEntitiesDecode() {
        let decoded = NoteHTMLEntities.decode("&amp;&lt;&gt;&quot;&apos;&#x1F600;&#128512;&copy2026&notanentity;&#150;&#0;&nbsp;&eacute;&hellip;&rarr;")
        #expect(decoded == "&<>\"'😀😀©2026¬anentity;–\u{FFFD}\u{A0}é…→", "entity decoding: \(decoded.debugDescription)")
    }

    @Test
    func attributeEntitiesRespectTheEqualsSignAndDecodeNumericApostrophes() {
        let attribute = NoteHTMLParser.parse("<a href=\"?a=1&copy=2&amp;b=3\" title='it&#39;s'>x</a>").children.first
        #expect(attribute?["href"] == "?a=1&copy=2&b=3", "legacy entities stay literal before = in attributes: \(attribute?["href"] ?? "")")
        #expect(attribute?["title"] == "it's", "single-quoted attribute")
    }
}
