import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct NotePDFBlockTestsHTMLTests {
    private typealias Fixture = NotePDFBlockTestsSupport

    private func styledPDF() -> NoteBlock {
        return Fixture.pdf {
            $0.source = "Attachments/report.pdf"
            $0.alt = "Report"
            $0.width = 0.5
            $0.alignment = .right
            $0.caption = NoteText("Numbers")
        }
    }

    @Test
    func clipboardHTMLLinksThePDF() {
        let block = styledPDF()
        let fragment = NotePageHTML.fragment([block])
        #expect(fragment.contains("data-block=\"pdf\"") && fragment.contains("href=\"Attachments/report.pdf\"") && !fragment.contains("<object"), "clipboard HTML links the PDF: \(fragment)")
    }

    @Test
    func aPDFBlockSurvivesAnHTMLRoundTrip() {
        let block = styledPDF()
        let fragment = NotePageHTML.fragment([block])
        let back = NoteHTMLReader.blocks(from: fragment, baseURL: nil)
        #expect(back.count == 1 && back[0].sameContent(as: block), "a PDF survives an HTML round trip: \(back)")
    }

    @Test
    func aDocumentEmbedsAnInlineObjectWithThePDFSizeAndAlignment() {
        let block = styledPDF()
        let document = NotePageHTML.document(NotePage(blocks: [block]), title: "Doc", assets: { _ in nil }, embedImages: false)
        #expect(document.contains("<object class=\"pdf-frame\" data=\"Attachments/report.pdf\" type=\"application/pdf\""), "exported documents show the PDF inline")
        #expect(document.contains("class=\"pdf align-right\"") && document.contains("style=\"width:50%\""), "export keeps size and alignment")
    }

    @Test
    func theDocumentStylesheetSizesThePDFFrame() {
        let block = styledPDF()
        let document = NotePageHTML.document(NotePage(blocks: [block]), title: "Doc", assets: { _ in nil }, embedImages: false)
        #expect(document.contains(".pdf-frame{"), "the stylesheet sizes the frame")
    }

    @Test
    func aSelfContainedExportEmbedsThePDFAndLinksItsOriginal() {
        let block = styledPDF()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotePDF-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Data("%PDF-1.4\n%%EOF\n".utf8)
        try? bytes.write(to: folder.appendingPathComponent("report.pdf"))
        let resolve: (String) -> URL? = { folder.appendingPathComponent(($0 as NSString).lastPathComponent) }
        let embedded = NotePageHTML.document(NotePage(blocks: [block]), title: "Doc", assets: resolve, embedImages: true)
        #expect(embedded.contains("data=\"data:application/pdf;base64," + bytes.base64EncodedString() + "\""), "a self-contained export embeds the PDF")
        #expect(embedded.contains("href=\"" + folder.appendingPathComponent("report.pdf").absoluteString + "\""), "the fallback link points at the original")
    }

    @Test
    func pastedWebPDFsBecomePDFBlocksWithTheirSource() {
        let foreign = NoteHTMLReader.blocks(from: "<p>Intro</p><embed src=\"https://example.com/a.pdf\" type=\"application/pdf\"><iframe src=\"files/b.pdf\"></iframe>",
                                            baseURL: nil)
        #expect(foreign.map(\.kind) == [.paragraph, .pdf, .pdf], "embedded PDFs from the web paste as PDF blocks: \(foreign.map(\.kind))")
        #expect(foreign.last?.props.source == "files/b.pdf", "pasted PDF keeps its address")
    }
}
