import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct NotePDFBlockTestsMarkdownAndTextTests {
    private typealias Fixture = NotePDFBlockTestsSupport

    @Test
    func aPDFCommentMakesAnInlineBlockWithItsSourceAndName() {
        let source = "![report.pdf](Attachments/report.pdf) <!-- parc pdf -->\n"
        let page = NoteMarkdown.parse(source)
        #expect(page.blocks.count == 1 && page.blocks[0].kind == .pdf, "a pdf comment makes an inline PDF: \(page.blocks.map(\.kind))")
        #expect(page.blocks[0].props.source == "Attachments/report.pdf" && page.blocks[0].props.alt == "report.pdf", "source and name read back")
    }

    @Test
    func aPlainPDFBlockSavesByteForByte() {
        let source = "![report.pdf](Attachments/report.pdf) <!-- parc pdf -->\n"
        let page = NoteMarkdown.parse(source)
        #expect(NoteMarkdown.serialize(page) == source, "a plain PDF block saves byte for byte: \(NoteMarkdown.serialize(page))")
    }

    @Test
    func anImageStylePDFWithoutThePDFCommentStaysAFile() {
        let plainFile = NoteMarkdown.parse("![report.pdf](Attachments/report.pdf)\n")
        #expect(plainFile.blocks.first?.kind == .file, "an image-style PDF without the comment stays a file row")
    }

    @Test
    func aStyledPDFWritesItsWidthAlignmentAndCaption() {
        let styled = Fixture.pdf {
            $0.source = "Attachments/Big%20deck.pdf"
            $0.alt = "Big deck"
            $0.caption = NoteText("Q3 plans")
            $0.width = 0.62
            $0.alignment = .left
        }
        let written = NoteMarkdown.serialize(NotePage(blocks: [styled]))
        #expect(written == "![Big deck](Attachments/Big%20deck.pdf \"Q3 plans\") <!-- parc pdf width=\"0.62\" align=\"left\" -->\n", "width, alignment and caption ride along: \(written)")
    }

    @Test
    func aStyledPDFSurvivesAMarkdownRoundTrip() {
        let styled = Fixture.pdf {
            $0.source = "Attachments/Big%20deck.pdf"
            $0.alt = "Big deck"
            $0.caption = NoteText("Q3 plans")
            $0.width = 0.62
            $0.alignment = .left
        }
        let written = NoteMarkdown.serialize(NotePage(blocks: [styled]))
        let reread = NoteMarkdown.parse(written).blocks
        #expect(reread.count == 1 && reread[0].sameContent(as: styled), "a styled PDF round-trips: \(reread)")
    }

    @Test
    func aRemotePDFSurvivesAMarkdownRoundTrip() {
        let remote = Fixture.pdf { $0.source = "https://example.com/paper.pdf" }
        let remoteText = NoteMarkdown.serialize(NotePage(blocks: [remote]))
        #expect(NoteMarkdown.parse(remoteText).blocks.first?.sameContent(as: remote) == true, "a linked PDF round-trips: \(remoteText)")
    }

    @Test
    func anEmptyPDFBlockSurvivesAMarkdownRoundTrip() {
        let empty = NoteBlock(.pdf)
        let emptyText = NoteMarkdown.serialize(NotePage(blocks: [empty, .paragraph("after")]))
        let emptyBack = NoteMarkdown.parse(emptyText).blocks
        #expect(emptyBack.count == 2 && emptyBack[0].kind == .pdf && (emptyBack[0].props.source ?? "").isEmpty, "an empty PDF block survives a save: \(emptyText)")
    }

    @Test
    func aHandWrittenLinkWithAPDFCommentBecomesAPDFBlock() {
        let link = NoteMarkdown.parse("[Annual report](Reports/annual.pdf \"Read me\") <!-- parc pdf align=\"right\" -->\n").blocks
        #expect(link.count == 1 && link[0].kind == .pdf && link[0].props.source == "Reports/annual.pdf"
               && link[0].props.alt == "Annual report" && link[0].props.caption.string == "Read me" && link[0].props.alignment == .right, "a hand-written link with the pdf comment is a PDF too: \(link)")
    }

    @Test
    func pdfsNestUnderListItems() {
        let nested = NoteMarkdown.parse("- Item\n\n  ![a.pdf](a.pdf) <!-- parc pdf -->\n").blocks
        #expect(nested.first?.children.first?.kind == .pdf, "PDFs nest under list items")
    }

    @Test
    func plainTextKeepsAPDFAsAFileReference() {
        let page = NotePage(blocks: [.paragraph("Read this"), Fixture.pdf { $0.source = "Attachments/report.pdf" }, .paragraph("Thanks")])
        #expect(NotePlainText.serialize(page) == "Read this\nAttachments/report.pdf\nThanks", "a plain-text note keeps the PDF as a file reference: \(NotePlainText.serialize(page))")
    }

    @Test
    func plainTextKeepsAnEmptyPDFAsAnEmptyLine() {
        let empty = NotePage(blocks: [.paragraph("a"), NoteBlock(.pdf)])
        #expect(NotePlainText.serialize(empty) == "a\n", "an empty PDF is an empty line")
    }
}
