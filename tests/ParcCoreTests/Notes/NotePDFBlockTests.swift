import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

@MainActor struct NotePDFBlockTests {
    func pdf(_ configure: (inout NoteBlockProps) -> Void) -> NoteBlock {
        var props = NoteBlockProps()
        configure(&props)
        return NoteBlock(.pdf, props: props)
    }

    @Test func aPdfCommentMakesAnInlinePDF() {
        let source = "![report.pdf](Attachments/report.pdf) <!-- parc pdf -->\n"
        let page = NoteMarkdown.parse(source)
        #expect(page.blocks.count == 1 && page.blocks[0].kind == .pdf, "a pdf comment makes an inline PDF: \(page.blocks.map(\.kind))")
        #expect(page.blocks[0].props.source == "Attachments/report.pdf" && page.blocks[0].props.alt == "report.pdf", "source and name read back")
        #expect(NoteMarkdown.serialize(page) == source, "a plain PDF block saves byte for byte: \(NoteMarkdown.serialize(page))")
    }

    @Test func anImageStylePDFWithoutTheCommentStaysA() {
        let plainFile = NoteMarkdown.parse("![report.pdf](Attachments/report.pdf)\n")
        #expect(plainFile.blocks.first?.kind == .file, "an image-style PDF without the comment stays a file row")
    }

    @Test func widthAlignmentAndCaptionRideAlong() {
        let styled = pdf {
            $0.source = "Attachments/Big%20deck.pdf"
            $0.alt = "Big deck"
            $0.caption = NoteText("Q3 plans")
            $0.width = 0.62
            $0.alignment = .left
        }
        let written = NoteMarkdown.serialize(NotePage(blocks: [styled]))
        #expect(written == "![Big deck](Attachments/Big%20deck.pdf \"Q3 plans\") <!-- parc pdf width=\"0.62\" align=\"left\" -->\n", "width, alignment and caption ride along: \(written)")
        let reread = NoteMarkdown.parse(written).blocks
        #expect(reread.count == 1 && reread[0].sameContent(as: styled), "a styled PDF round-trips: \(reread)")

        let remote = pdf { $0.source = "https://example.com/paper.pdf" }
        let remoteText = NoteMarkdown.serialize(NotePage(blocks: [remote]))
        #expect(NoteMarkdown.parse(remoteText).blocks.first?.sameContent(as: remote) == true, "a linked PDF round-trips: \(remoteText)")

        let empty = NoteBlock(.pdf)
        let emptyText = NoteMarkdown.serialize(NotePage(blocks: [empty, .paragraph("after")]))
        let emptyBack = NoteMarkdown.parse(emptyText).blocks
        #expect(emptyBack.count == 2 && emptyBack[0].kind == .pdf && (emptyBack[0].props.source ?? "").isEmpty, "an empty PDF block survives a save: \(emptyText)")

        let link = NoteMarkdown.parse("[Annual report](Reports/annual.pdf \"Read me\") <!-- parc pdf align=\"right\" -->\n").blocks
        #expect(link.count == 1 && link[0].kind == .pdf && link[0].props.source == "Reports/annual.pdf"
               && link[0].props.alt == "Annual report" && link[0].props.caption.string == "Read me" && link[0].props.alignment == .right, "a hand-written link with the pdf comment is a PDF too: \(link)")
    }

    @Test func pDFsNestUnderListItems() {
        let nested = NoteMarkdown.parse("- Item\n\n  ![a.pdf](a.pdf) <!-- parc pdf -->\n").blocks
        #expect(nested.first?.children.first?.kind == .pdf, "PDFs nest under list items")
    }

    @Test func aPlainTextNoteKeepsThePDF() {
        let page = NotePage(blocks: [.paragraph("Read this"), pdf { $0.source = "Attachments/report.pdf" }, .paragraph("Thanks")])
        #expect(NotePlainText.serialize(page) == "Read this\nAttachments/report.pdf\nThanks", "a plain-text note keeps the PDF as a file reference: \(NotePlainText.serialize(page))")
        let empty = NotePage(blocks: [.paragraph("a"), NoteBlock(.pdf)])
        #expect(NotePlainText.serialize(empty) == "a\n", "an empty PDF is an empty line")
    }

    @Test func clipboardHTMLLinksThePDF() {
        let block = pdf {
            $0.source = "Attachments/report.pdf"
            $0.alt = "Report"
            $0.width = 0.5
            $0.alignment = .right
            $0.caption = NoteText("Numbers")
        }
        let fragment = NotePageHTML.fragment([block])
        #expect(fragment.contains("data-block=\"pdf\"") && fragment.contains("href=\"Attachments/report.pdf\"") && !fragment.contains("<object"), "clipboard HTML links the PDF: \(fragment)")
        let back = NoteHTMLReader.blocks(from: fragment, baseURL: nil)
        #expect(back.count == 1 && back[0].sameContent(as: block), "a PDF survives an HTML round trip: \(back)")

        let document = NotePageHTML.document(NotePage(blocks: [block]), title: "Doc", assets: { _ in nil }, embedImages: false)
        #expect(document.contains("<object class=\"pdf-frame\" data=\"Attachments/report.pdf\" type=\"application/pdf\""), "exported documents show the PDF inline")
        #expect(document.contains("class=\"pdf align-right\"") && document.contains("style=\"width:50%\""), "export keeps size and alignment")
        #expect(document.contains(".pdf-frame{"), "the stylesheet sizes the frame")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotePDF-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Data("%PDF-1.4\n%%EOF\n".utf8)
        try? bytes.write(to: folder.appendingPathComponent("report.pdf"))
        let resolve: (String) -> URL? = { folder.appendingPathComponent(($0 as NSString).lastPathComponent) }
        let embedded = NotePageHTML.document(NotePage(blocks: [block]), title: "Doc", assets: resolve, embedImages: true)
        #expect(embedded.contains("data=\"data:application/pdf;base64," + bytes.base64EncodedString() + "\""), "a self-contained export embeds the PDF")
        #expect(embedded.contains("href=\"" + folder.appendingPathComponent("report.pdf").absoluteString + "\""), "the fallback link points at the original")

        let foreign = NoteHTMLReader.blocks(from: "<p>Intro</p><embed src=\"https://example.com/a.pdf\" type=\"application/pdf\"><iframe src=\"files/b.pdf\"></iframe>",
                                            baseURL: nil)
        #expect(foreign.map(\.kind) == [.paragraph, .pdf, .pdf], "embedded PDFs from the web paste as PDF blocks: \(foreign.map(\.kind))")
        #expect(foreign.last?.props.source == "files/b.pdf", "pasted PDF keeps its address")
    }

    @Test func aFreshPDFSpansTheColumn() {
        #expect(NotePDFLayout.displayWidth(fraction: nil, columnWidth: 700) == 700, "a fresh PDF spans the column")
        #expect(NotePDFLayout.displayWidth(fraction: 0.5, columnWidth: 700) == 350, "fractions scale with the column")
        #expect(NotePDFLayout.displayWidth(fraction: 0.1, columnWidth: 700) == NotePDFLayout.minimumWidth, "PDFs keep a readable minimum")
        #expect(NotePDFLayout.displayWidth(fraction: 0.1, columnWidth: 150) == 150, "narrow columns cap the minimum")
        #expect(NotePDFLayout.displayWidth(fraction: 420, columnWidth: 700) == 420, "point widths from hand-written files work")
        #expect(NotePDFLayout.displayWidth(fraction: .nan, columnWidth: 700) == 700, "broken widths fall back to full width")
    }

    @Test func theViewerFitsOnePageAtTheWidth() {
        let letter = NotePDFLayout.viewerHeight(width: 516, aspect: 11 / 8.5)
        #expect(letter == ((516 - 16) * 11 / 8.5 + 16).rounded(), "the viewer fits one page at the width: \(letter)")
        #expect(NotePDFLayout.viewerHeight(width: 516, aspect: nil) == letter, "unknown pages assume Letter")
        #expect(NotePDFLayout.viewerHeight(width: 2000, aspect: 1.414) == NotePDFLayout.maximumHeight, "tall viewers cap")
        #expect(NotePDFLayout.viewerHeight(width: 300, aspect: 0.3) == NotePDFLayout.minimumHeight, "slim slides keep a floor")
        #expect(NotePDFLayout.viewerHeight(width: 600, aspect: 9 / 16) == ((600 - 16) * 9 / 16 + 16).rounded(), "slides make short viewers")
    }

    @Test func portraitAspect() {
        let portrait: CGFloat = 792.0 / 612.0, landscape: CGFloat = 612.0 / 792.0
        #expect(NotePDFLayout.pageAspect(width: 612, height: 792, rotation: 0) == portrait, "portrait aspect")
        #expect(NotePDFLayout.pageAspect(width: 612, height: 792, rotation: 90) == landscape, "rotated pages swap")
        #expect(NotePDFLayout.pageAspect(width: 612, height: 792, rotation: -270) == landscape, "negative rotation is normalized")
        #expect(NotePDFLayout.pageAspect(width: 0, height: 792, rotation: 0) == nil, "empty pages have no aspect")
    }

    @Test func nearFullWidthSnapsToFull() {
        #expect(NotePDFLayout.storedFraction(width: 697, columnWidth: 700) == nil, "near full width snaps to full")
        #expect(NotePDFLayout.storedFraction(width: 350, columnWidth: 700) == 0.5, "half width stores a fraction")
        #expect(NotePDFLayout.storedFraction(width: 10, columnWidth: 700) == Double((NotePDFLayout.minimumWidth / 700 * 1000).rounded() / 1000), "tiny widths settle at the minimum")
        #expect(NotePDFLayout.rawResize(start: 400, dragDelta: 20, leading: false, alignment: .center) == 440, "centred PDFs grow both ways")
        #expect(NotePDFLayout.rawResize(start: 400, dragDelta: 20, leading: true, alignment: .left) == 380, "the leading bar shrinks left PDFs")
        let banded = NotePDFLayout.rubberBanded(900, columnWidth: 700)
        #expect(banded > 700 && banded < 790, "dragging past the column rubber-bands: \(banded)")
        #expect(NotePDFLayout.originX(width: 300, alignment: .right, columnWidth: 700) == 400, "right alignment hugs the edge")
    }

    @Test func zoomingInStepsUpFromFit() {
        let fit: CGFloat = 0.8
        let first = NotePDFZoom.zoomed(current: fit, fit: fit, zoomIn: true)
        #expect(first == .init(scale: fit * 1.25, fitsWidth: false), "zooming in steps up from fit: \(first)")
        let back = NotePDFZoom.zoomed(current: first.scale, fit: fit, zoomIn: false)
        #expect(back.fitsWidth && back.scale == fit, "zooming back out lands on fit width")
        let past = NotePDFZoom.zoomed(current: fit * 1.1, fit: fit, zoomIn: false)
        #expect(past.fitsWidth, "crossing fit width snaps to it")
        var scale = fit
        for _ in 0..<40 { scale = NotePDFZoom.zoomed(current: scale, fit: fit, zoomIn: true).scale }
        #expect(abs(scale - fit * NotePDFZoom.maximumRatio) < 0.0001, "zoom tops out: \(scale)")
        #expect(!NotePDFZoom.canZoom(current: scale, fit: fit, zoomIn: true), "no more zoom at the top")
        scale = fit
        for _ in 0..<40 { scale = NotePDFZoom.zoomed(current: scale, fit: fit, zoomIn: false).scale }
        #expect(abs(scale - fit * NotePDFZoom.minimumRatio) < 0.0001, "zoom bottoms out: \(scale)")
        #expect(NotePDFZoom.percent(current: fit * 1.5, fit: fit) == 150, "percent is relative to fit width")
        #expect(NotePDFZoom.zoomed(current: .nan, fit: fit, zoomIn: true).fitsWidth, "broken scales reset to fit")
    }

    @Test func pagesCountFromOne() {
        #expect(NotePDFPages.label(current: 0, count: 12) == "1 / 12", "pages count from one")
        #expect(NotePDFPages.label(current: 40, count: 12) == "12 / 12", "page labels clamp")
        #expect(NotePDFPages.label(current: 0, count: 0) == "–", "an empty document says so")
        #expect(NotePDFPages.spokenLabel(current: 2, count: 9) == "Page 3 of 9", "VoiceOver hears the page")
        #expect(NotePDFPages.spokenLabel(current: 0, count: 1) == "One page", "single pages read naturally")
        #expect(NotePDFPages.summary(count: 1) == "1 page" && NotePDFPages.summary(count: 3) == "3 pages", "page counts read naturally")
    }

    @Test func scrollingOverAPDFScrollsThePDF() {
        let middle = NotePDFScrollLatch.Room(up: true, down: true)
        let bottom = NotePDFScrollLatch.Room(up: true, down: false)
        let fits = NotePDFScrollLatch.Room()

        var latch = NotePDFScrollLatch()
        #expect(latch.receive(.began, deltaX: 0, deltaY: -4, time: 0, room: middle) == .pdf, "scrolling over a PDF scrolls the PDF")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: -8, time: 0.01, room: middle) == .pdf, "and keeps doing so")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: -8, time: 0.02, room: bottom) == .noteHandedOver, "at the last page the note takes over")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: 8, time: 0.03, room: middle) == .noteHandedOver, "the rest of the gesture stays with the note")
        #expect(latch.receive(.momentum, deltaX: 0, deltaY: -3, time: 0.1, room: bottom) == .noteHandedOver, "momentum carries on in the note")

        #expect(latch.receive(.began, deltaX: 0, deltaY: -4, time: 1, room: bottom) == .note, "a new gesture at the bottom scrolls the note natively")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: 4, time: 1.01, room: middle) == .note, "once latched, it stays with the note")

        #expect(latch.receive(.began, deltaX: 0, deltaY: 0, time: 2, room: fits) == .pdf, "no delta yet decides nothing")
        #expect(latch.target == nil, "the latch waits for a direction")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: -2, time: 2.01, room: fits) == .note, "a PDF that fits hands scrolling to the note")

        #expect(latch.receive(.began, deltaX: 6, deltaY: 1, time: 3, room: .init(up: true, down: true, left: true, right: true)) == .pdf, "zoomed PDFs pan sideways")
        #expect(latch.receive(.began, deltaX: 6, deltaY: 1, time: 4, room: middle) == .note, "unzoomed PDFs let sideways swipes through")

        var wheel = NotePDFScrollLatch()
        #expect(wheel.receive(.discrete, deltaX: 0, deltaY: -1, time: 10, room: middle) == .pdf, "wheel ticks scroll the PDF")
        #expect(wheel.receive(.discrete, deltaX: 0, deltaY: -1, time: 10.1, room: bottom) == .noteHandedOver, "a wheel run hands over at the end")
        #expect(wheel.receive(.discrete, deltaX: 0, deltaY: 1, time: 10.2, room: middle) == .noteHandedOver, "the run stays handed over")
        #expect(wheel.receive(.discrete, deltaX: 0, deltaY: 1, time: 11, room: middle) == .pdf, "a pause starts a fresh run")

        var ending = NotePDFScrollLatch()
        _ = ending.receive(.began, deltaX: 0, deltaY: -2, time: 0, room: middle)
        #expect(ending.receive(.ended, deltaX: 0, deltaY: 0, time: 0.1, room: bottom) == .pdf, "the end of a gesture goes where it started")
        ending.reset()
        #expect(ending.target == nil, "reset forgets the latch")
    }

    @Test func aFileTurnsIntoAPDFAndKeepsEverything() {
        var file = NoteBlock(.file)
        file.props.source = "Attachments/report.pdf"
        file.props.caption = NoteText("Numbers")
        file.props.width = 0.5
        file.props.alignment = .left
        let session = NotePageSession(page: NotePage(blocks: [file]))
        session.turnInto([file.id], kind: .pdf)
        let turned = session.page.blocks[0]
        #expect(turned.kind == .pdf && turned.props.source == file.props.source && turned.props.caption == file.props.caption
               && turned.props.width == 0.5 && turned.props.alignment == .left, "a file turns into a PDF and keeps everything")
        session.undo()
        #expect(session.page.blocks[0].kind == .file, "undo turns it back")
        #expect(NoteBlockKind.pdf.isMedia && NoteBlockKind.pdf.hasCaption && !NoteBlockKind.pdf.hasText, "PDFs are captioned media")
    }
}
