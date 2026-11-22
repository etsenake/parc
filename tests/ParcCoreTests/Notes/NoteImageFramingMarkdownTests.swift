import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct NoteImageFramingMarkdownTests {
    @Test func markdownKeepsFramingInTheParcCommentAcrossSaves() {
        var image = NoteBlock(.image)
        image.props.source = "Attachments/cat.png"
        image.props.alt = "A sleepy cat"
        image.props.width = 0.5
        image.props.alignment = .left
        image.props.crop = NoteImageCrop(x: 0.1, y: 0.05, width: 0.8, height: 0.9)
        image.props.mask = .circle
        let page = NotePage(blocks: [image, .paragraph(NoteText("After"))])
        let text = NoteMarkdown.serialize(page)
        #expect(text.contains("![A sleepy cat](Attachments/cat.png) <!-- parc width=\"0.5\" align=\"left\" crop=\"0.1,0.05,0.8,0.9\" mask=\"circle\" -->"), "crop and mask ride in the Parc comment:\n\(text)")
        let back = NoteMarkdown.parse(text)
        #expect(back.blocks.first?.props == image.props, "image framing survives a round trip")
        #expect(NoteMarkdown.serialize(back) == text, "a second save is identical")
    }

    @Test func handWrittenCropsAreNormalized() {
        let hand = NoteMarkdown.parse("![](a.png) <!-- parc crop=\"0.95,0,0.5,1\" mask=\"HEART\" -->\n\nWords <!-- parc crop=\"0,0,1,1\" -->\n")
        #expect(hand.blocks.first?.props.crop == NoteImageCrop(x: 0.5, y: 0, width: 0.5, height: 1), "hand-written crops are tidied")
    }

    @Test func maskNamesAreCaseInsensitive() {
        let hand = NoteMarkdown.parse("![](a.png) <!-- parc crop=\"0.95,0,0.5,1\" mask=\"HEART\" -->\n\nWords <!-- parc crop=\"0,0,1,1\" -->\n")
        #expect(hand.blocks.first?.props.mask == .heart, "mask names ignore case")
    }

    @Test func markdownIgnoresImageCropsOnText() {
        let hand = NoteMarkdown.parse("![](a.png) <!-- parc crop=\"0.95,0,0.5,1\" mask=\"HEART\" -->\n\nWords <!-- parc crop=\"0,0,1,1\" -->\n")
        #expect(hand.blocks.count > 1 && hand.blocks[1].props.crop == nil, "crops on text are ignored")
    }

    @Test func unknownMasksAndInvalidCropsAreIgnored() {
        let unknown = NoteMarkdown.parse("![](a.png) <!-- parc mask=\"blob\" crop=\"x\" -->\n")
        #expect(unknown.blocks.first?.props.mask == nil && unknown.blocks.first?.props.crop == nil, "unknown shapes and bad crops are skipped")
    }

    @Test func aLoneMaskWritesAShortComment() {
        var masked = NoteBlock(.image)
        masked.props.source = "b.png"
        masked.props.mask = .star
        let starText = NoteMarkdown.serialize(NotePage(blocks: [masked]))
        #expect(starText.contains("![](b.png) <!-- parc mask=\"star\" -->"), "a lone mask writes a short comment: \(starText)")
    }

    @Test func aCaptionRoundTripsAlongsideImageFraming() {
        var image = NoteBlock(.image)
        image.props.source = "Attachments/cat.png"
        image.props.alt = "A sleepy cat"
        image.props.width = 0.5
        image.props.alignment = .left
        image.props.crop = NoteImageCrop(x: 0.1, y: 0.05, width: 0.8, height: 0.9)
        image.props.mask = .circle
        var titled = image
        titled.props.caption = NoteText("Nap time")
        let titledText = NoteMarkdown.serialize(NotePage(blocks: [titled]))
        #expect(NoteMarkdown.parse(titledText).blocks.first?.props == titled.props, "captions and framing live together")
    }

    @Test func theBlockClipboardKeepsFraming() {
        var props = NoteBlockProps()
        props.crop = NoteImageCrop(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        props.mask = .hexagon
        let block = NoteBlock(.image, props: props)
        let data = (try? JSONEncoder().encode(block)) ?? Data()
        let decoded = try? JSONDecoder().decode(NoteBlock.self, from: data)
        #expect(decoded?.props.crop == props.crop && decoded?.props.mask == .hexagon, "the block clipboard keeps framing")
    }

    @Test func olderClipboardBlocksDecodeWithoutFraming() {
        var props = NoteBlockProps()
        props.crop = NoteImageCrop(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        props.mask = .hexagon
        let block = NoteBlock(.image, props: props)
        let data = (try? JSONEncoder().encode(block)) ?? Data()
        var old = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var oldProps = old["props"] as? [String: Any] ?? [:]
        oldProps.removeValue(forKey: "crop")
        oldProps.removeValue(forKey: "mask")
        old["props"] = oldProps
        let legacy = (try? JSONSerialization.data(withJSONObject: old)).flatMap { try? JSONDecoder().decode(NoteBlock.self, from: $0) }
        #expect(legacy != nil && legacy?.props.crop == nil && legacy?.props.mask == nil, "older clipboard blocks still decode")
    }
}
