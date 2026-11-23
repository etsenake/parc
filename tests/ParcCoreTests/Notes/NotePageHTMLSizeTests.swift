import Foundation
import Testing
@testable import ParcCore

struct NotePageHTMLSizeTests {
    private static func imagePage(width: Double) -> NotePage {
        var props = NoteBlockProps()
        props.source = "Attachments/cat.png"
        props.width = width
        return NotePage(blocks: [NoteBlock(.image, props: props)])
    }

    private static func pdfPage(width: Double) -> NotePage {
        var props = NoteBlockProps()
        props.source = "Attachments/doc.pdf"
        props.width = width
        return NotePage(blocks: [NoteBlock(.pdf, props: props)])
    }

    private static func export(_ page: NotePage) -> String {
        NotePageHTML.document(page, title: "Sizes", assets: { _ in nil }, embedImages: false)
    }

    @Test(arguments: [1e30, Double.greatestFiniteMagnitude, Double.infinity])
    func anEnormousImageWidthStillExports(width: Double) {
        #expect(Self.export(Self.imagePage(width: width)).contains("<figure"))
    }

    @Test(arguments: [1e30, Double.greatestFiniteMagnitude, Double.infinity])
    func anEnormousPDFWidthStillExports(width: Double) {
        #expect(Self.export(Self.pdfPage(width: width)).contains("data-block=\"pdf\""))
    }

    @Test func aSensibleImageWidthKeepsItsPixels() {
        #expect(Self.export(Self.imagePage(width: 320)).contains("width:320px;"))
    }

    @Test func aNonFiniteCoverPositionStillExports() {
        var settings = NotePageSettings()
        settings.cover = NoteCover(source: "Attachments/cover.jpg", position: .nan)
        let html = NotePageHTML.document(NotePage(settings: settings, blocks: [.paragraph()]), title: "Cover",
                                         assets: { _ in nil }, embedImages: false)
        #expect(html.contains("object-position:center 50%"))
    }

    @Test(arguments: ["nan", "inf", "-inf"])
    func markdownIgnoresAWidthThatIsNotANumber(width: String) {
        let page = NoteMarkdown.parse("![](Attachments/a.png) <!-- parc width=\"\(width)\" -->")
        #expect(page.blocks.first?.props.width == nil)
    }
}
