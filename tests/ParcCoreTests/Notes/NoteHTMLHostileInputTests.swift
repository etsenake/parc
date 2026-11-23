import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLHostileInputTests {
    private typealias Fixture = NoteHTMLReaderTestsSupport

    @Test func tenThousandNestedBoxesStillImport() {
        let html = String(repeating: "<div>", count: 10_000) + "bottom" + String(repeating: "</div>", count: 10_000)
        let text = runOnLargeStack { NotePage(blocks: Fixture.read(html)).plainText }
        #expect(text.contains("bottom"))
    }

    @Test func tenThousandNestedSpansStillImport() {
        let html = "<p>" + String(repeating: "<span>", count: 10_000) + "bottom" + String(repeating: "</span>", count: 10_000) + "</p>"
        #expect(runOnLargeStack { NotePage(blocks: Fixture.read(html)).plainText }.contains("bottom"))
    }

    @Test func aListThatStartsAtTheLargestIntegerStillNumbers() {
        let blocks = Fixture.read("<ol start=\"9223372036854775807\"><li>one</li><li>two</li><li>three</li></ol>")
        let page = NotePage(blocks: blocks)
        #expect(blocks.count == 3)
        #expect(page.listNumber(for: blocks[2].id) != nil)
    }

    @Test func anOutlandishIndentLevelIsIgnored() {
        let blocks = Fixture.read("<ul data-indent=\"9223372036854775807\"><li>one</li><li>two</li></ul>")
        #expect(blocks.map(\.kind) == [.bulletedItem, .bulletedItem])
    }

    @Test(arguments: ["hsl(nan, 50%, 50%)", "hsl(inf, 50%, 50%)", "hsl(-infinity deg, 50%, 50%)"])
    func aHueThatIsNotANumberDoesNotChooseAColor(_ value: String) {
        #expect(NoteHTMLColor.parse(value) == nil)
        #expect(Fixture.read("<p style=\"color: \(value)\">text</p>").count == 1)
    }

    @Test func aSizeThatIsNotANumberIsNotKeptOnABlock() throws {
        let blocks = Fixture.read("<div data-block=\"pdf\" data-source=\"https://example.test/a.pdf\" data-width=\"nan\"></div>")
        let pdf = try #require(blocks.first)
        #expect(pdf.kind == .pdf)
        #expect(pdf.props.width == nil)
    }
}
