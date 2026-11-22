import Foundation
import Testing
@testable import ParcCore

struct NoteCustomEmojiCodecTestsIconAndExportTests {
    private typealias Fixture = NoteCustomEmojiCodecTestsSupport

    private func iconPage() -> NotePage {
        var settings = NotePageSettings()
        settings.icon = ":party:"
        var props = NoteBlockProps()
        props.icon = ":parrot:"
        return NotePage(settings: settings, blocks: [NoteBlock(.callout, text: "Heads up", props: props)])
    }

    @Test
    func aPageIconWritesAQuotedShortcode() {
        let markdown = NoteMarkdown.serialize(iconPage(), customEmoji: Fixture.names)
        #expect(markdown.hasPrefix("---\nicon: \":party:\"\n---\n"), "the page icon is a quoted shortcode, got \(markdown.debugDescription)")
    }

    @Test
    func aCalloutIconWritesItsShortcodeInTheComment() {
        let markdown = NoteMarkdown.serialize(iconPage(), customEmoji: Fixture.names)
        #expect(markdown.contains("icon=\":parrot:\""), "a callout keeps its custom icon in the Parc comment")
    }

    @Test
    func aPageIconReadsBackAsAShortcode() {
        let markdown = NoteMarkdown.serialize(iconPage(), customEmoji: Fixture.names)
        let back = NoteMarkdown.parse(markdown, customEmoji: Fixture.names)
        #expect(back.settings.icon == ":party:", "the page icon reads back")
    }

    @Test
    func aCalloutIconReadsBackAsAShortcode() {
        let markdown = NoteMarkdown.serialize(iconPage(), customEmoji: Fixture.names)
        let back = NoteMarkdown.parse(markdown, customEmoji: Fixture.names)
        #expect(back.blocks.first?.kind == .callout && back.blocks.first?.props.icon == ":parrot:", "the callout icon reads back")
    }

    @Test
    func aSecondSaveKeepsBothIconShortcodes() {
        let markdown = NoteMarkdown.serialize(iconPage(), customEmoji: Fixture.names)
        let back = NoteMarkdown.parse(markdown, customEmoji: Fixture.names)
        #expect(NoteMarkdown.serialize(back, customEmoji: Fixture.names) == markdown, "icons round-trip")
    }

    @Test
    func tabSummariesReadCustomEmojiIconsFromFrontMatter() {
        let markdown = NoteMarkdown.serialize(iconPage(), customEmoji: Fixture.names)
        let summary = NoteFileSummary.frontMatter(markdown.components(separatedBy: "\n"))
        #expect(summary.icon == ":party:", "tab icons read the shortcode from front matter")
    }

    private var image: URL {
        URL(fileURLWithPath: "/tmp/notes/.parc/emoji/party.png")
    }

    private func document() -> String {
        let assets: (String) -> URL? = { $0 == ":party:" ? self.image : nil }
        var settings = NotePageSettings()
        settings.icon = ":party:"
        var props = NoteBlockProps()
        props.icon = ":party:"
        let page = NotePage(settings: settings, blocks: [.paragraph(Fixture.text("Yay ", Fixture.atom("party"), " and ", Fixture.atom("gone"))),
                                                         NoteBlock(.callout, text: "Note", props: props)])
        return NotePageHTML.document(page, title: "Plans", assets: assets, embedImages: false)
    }

    @Test
    func inlineEmojiExportAsImages() {
        let document = document()
        #expect(document.contains("<img class=\"custom-emoji inline-emoji\" alt=\":party:\" title=\":party:\" src=\"\(image.absoluteString)\">"), "inline custom emoji export as images")
    }

    @Test
    func unavailableEmojiExportTheirShortcode() {
        let document = document()
        #expect(document.contains("and :gone:"), "missing ones export as their shortcode")
    }

    @Test
    func aCustomPageIconExportsAsAnImage() {
        let document = document()
        #expect(document.contains("class=\"page-icon page-icon-image custom-emoji\""), "the page icon exports as an image")
    }

    @Test
    func aCustomCalloutIconExportsAsAnImage() {
        let document = document()
        #expect(document.contains("class=\"callout-icon custom-emoji\""), "the callout icon exports as an image")
    }

    @Test
    func clipboardHTMLSizesCustomEmojiInline() {
        let image = self.image
        let assets: (String) -> URL? = { $0 == ":party:" ? image : nil }
        var settings = NotePageSettings()
        settings.icon = ":party:"
        var props = NoteBlockProps()
        props.icon = ":party:"
        let page = NotePage(settings: settings, blocks: [.paragraph(Fixture.text("Yay ", Fixture.atom("party"), " and ", Fixture.atom("gone"))),
                                                         NoteBlock(.callout, text: "Note", props: props)])
        let fragment = NotePageHTML.fragment(page.blocks, assets: assets)
        #expect(fragment.contains("style=\"height:1.2em;width:auto;vertical-align:-0.2em\""), "copied HTML sizes custom emoji inline")
    }
}
