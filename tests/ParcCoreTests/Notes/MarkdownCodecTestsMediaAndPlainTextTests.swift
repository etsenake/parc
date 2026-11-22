import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTestsMediaAndPlainTextTests {
    private func blocks(_ source: String) -> [NoteBlock] { NoteMarkdown.parse(source).blocks }

    @Test
    func mediaSourcesAndExplicitOverridesDetermineBlockKind() {
        let media = blocks("![](a.png)\n\n![](b.MOV)\n\n![](c.flac)\n\n![](d.zip)\n\n![](https://youtu.be/x)\n\n![](https://cdn.example.com/photo?id=1)\n\n![x](a.png) <!-- parc paragraph -->\n")
        #expect(media.map(\.kind) == [.image, .video, .audio, .file, .embed, .image, .paragraph], "media kind follows the extension: \(media.map(\.kind))")
    }

    @Test
    func mediaAndLinkBlocksSurviveAModelRoundTrip() {
        var image = NoteBlock(.image)
        image.props.source = "Attachments/My Photo (1).png"
        image.props.alt = "A [bracketed] *alt*"
        image.props.caption = NoteText(pieces: [("Caption with ", .plain), ("bold", { var m = NoteMarks(); m.bold = true; return m }()), (" and \"quotes\" & \\ slashes", .plain)])
        image.props.width = 412.5
        image.props.alignment = .right
        var video = NoteBlock(.video)
        video.props.source = "https://example.com/stream"
        var file = NoteBlock(.file)
        file.props.source = "Attachments/archive.tar.gz"
        file.props.alt = "archive.tar.gz"
        var embed = NoteBlock(.embed)
        embed.props.source = "https://www.figma.com/file/abc"
        var bookmark = NoteBlock(.bookmark)
        bookmark.props.source = "https://example.com/article"
        bookmark.props.bookmark = NoteBookmark(title: "An *article* [title]", summary: "Summary with \"quotes\" and --> arrows", siteName: "Example",
                                               iconURL: "https://example.com/favicon.ico", imageURL: "https://example.com/og.png")
        bookmark.props.caption = "My caption"
        var untitled = NoteBlock(.bookmark)
        untitled.props.source = "https://example.com/plain"
        untitled.props.bookmark = NoteBookmark()
        untitled.props.caption = "caption without title"
        var pageLink = NoteBlock(.pageLink, text: "Meeting *notes*")
        pageLink.props.target = "Meetings/2026-11-20%20Standup.md"
        let linkParagraph = NoteBlock.paragraph(NoteText("Just a link", marks: { var m = NoteMarks(); m.link = "Other.md"; return m }()))
        let mentionParagraph = NoteBlock.paragraph(.atom(.page(target: "Other.md", title: "Other")))
        let imageParagraph = NoteBlock.paragraph(.atom(.raw("![x](y.png)")))
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [image, video, file, embed, bookmark, untitled, pageLink, linkParagraph, mentionParagraph, imageParagraph]), "media and links")
    }

    @Test
    func plainTextLoadsAsOneParagraphPerLine() {
        let source = "first line\n\n  indented # not markdown *at all*\nlast"
        let page = NotePlainText.parse(source)
        #expect(page.blocks.count == 4 && page.blocks.allSatisfy { $0.kind == .paragraph }, "one paragraph per line")
    }

    @Test
    func plainTextSavesVerbatim() {
        let source = "first line\n\n  indented # not markdown *at all*\nlast"
        let page = NotePlainText.parse(source)
        #expect(NotePlainText.serialize(page) == source, "plain text saves verbatim")
    }

    @Test
    func plainTextKeepsATrailingNewline() {
        #expect(NotePlainText.serialize(NotePlainText.parse("trailing\n")) == "trailing\n", "a trailing newline survives")
    }

    @Test
    func anEmptyTextFileStaysEmpty() {
        #expect(NotePlainText.serialize(NotePlainText.parse("")) == "", "an empty file stays empty")
    }
}
