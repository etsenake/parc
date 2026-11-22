import Foundation
import Testing
@testable import ParcCore

struct NoteEmbedModelMarkdownTests {
    @Test func aParcCommentPreservesTheEmbedKindAndHeight() {
        let source = "![](https://example.com/widget) <!-- parc embed height=\"640\" -->\n"
        let page = NoteMarkdown.parse(source)
        #expect(page.blocks.count == 1 && page.blocks[0].kind == .embed, "the comment keeps the embed kind")
        #expect(page.blocks[0].props.height == 640, "the height comes back from the parc comment")
        let written = NoteMarkdown.serialize(page)
        #expect(written.contains("height=\"640\""), "the height is written back")
        #expect(NoteMarkdown.parse(written).blocks[0].props == page.blocks[0].props, "props survive a second round trip")
    }

    @Test func anEmbedAtDefaultHeightWritesNoHeight() {
        let source = "![](https://example.com/widget) <!-- parc embed height=\"640\" -->\n"
        let page = NoteMarkdown.parse(source)
        var plain = page
        plain.blocks[0].props.height = nil
        #expect(!NoteMarkdown.serialize(plain).contains("height"), "an embed at the default height writes no height")
    }

    @Test func anInferredEmbedPreservesItsHeight() {
        let video = NoteMarkdown.parse("![](https://www.youtube.com/watch?v=dQw4w9WgXcQ) <!-- parc height=\"300\" -->\n")
        #expect(video.blocks[0].kind == .embed && video.blocks[0].props.height == 300, "inferred embeds read their height too")
        #expect(NoteMarkdown.serialize(video).contains("height=\"300\""), "and write it back")
    }
}
