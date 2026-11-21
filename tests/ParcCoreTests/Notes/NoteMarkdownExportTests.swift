import Foundation
import Testing
@testable import ParcCore

struct NoteMarkdownExportTests {
    typealias Check = NoteMarkdownCheck

    let source = """
    Before

    <!-- parc synced id="k3x9qa" -->

    Weekly goals

    - Ship it

    <!-- parc /synced -->

    <!-- parc synced from="Project%20plan.md#zz12ab" -->

    Copied *line*

    <!-- parc /synced -->

    After
    """

    func exported(_ page: NotePage) -> String {
        NoteMarkdown.serialize(page, purpose: .export)
    }

    @Test func syncedBlocksExportTheirContent() {
        let page = NoteMarkdown.parse(source)
        let output = exported(page)
        #expect(!output.contains("<!--"), "no markers in the export:\n\(output)")
        #expect(output == "Before\n\nWeekly goals\n\n- Ship it\n\nCopied *line*\n\nAfter\n", "synced contents export in place:\n\(output)")
        var nested = NoteBlock(.synced, children: [NoteBlock(.bulletedItem, text: "Inside a list")])
        nested.props.anchor = "abc123"
        let list = NotePage(blocks: [NoteBlock(.bulletedItem, text: "Outer", children: [nested])])
        #expect(exported(list) == "- Outer\n  - Inside a list\n", "nested synced blocks unwrap too:\n\(exported(list))")
    }

    @Test func savingKeepsParcMarkup() {
        let page = NoteMarkdown.parse(source)
        let saved = NoteMarkdown.serialize(page)
        #expect(saved == NoteMarkdown.serialize(page, purpose: .file), "the default purpose is the file")
        #expect(saved.contains("<!-- parc synced id=\"k3x9qa\" -->") && saved.contains("<!-- parc synced from=\"Project%20plan.md#zz12ab\" -->"), "saving still writes the synced markers")
        #expect(saved == source + "\n", "saving is byte-identical:\n\(saved)")
    }

    @Test func blockMarkupIsPlain() {
        var colored = NoteBlock.paragraph("Blue words")
        colored.color = .text(.blue)
        colored.props.anchor = "a1b2c3"
        var callout = NoteBlock(.callout, text: "Remember this")
        callout.props.icon = "\u{1F4A1}"
        var alert = NoteBlock(.callout, text: "Careful")
        alert.props.alert = "WARNING"
        var code = NoteBlock(.code, text: "let x = 1")
        code.props.language = "swift"
        code.props.caption = "Setup"
        code.props.wrap = true
        var button = NoteBlock(.button)
        button.props.button = NoteButton(name: "Add task", actions: [.insert(placement: .below, blocks: [NoteBlock(.todo, text: "Task")])])
        let page = NotePage(blocks: [colored, callout, alert, code, NoteBlock(.breadcrumb), button])
        let output = exported(page)
        #expect(!output.contains("<!--") && !output.contains("data-"), "no Parc comments or attributes:\n\(output)")
        #expect(output.hasPrefix("Blue words\n"), "colour and anchor drop:\n\(output)")
        #expect(output.contains("> \u{1F4A1} Remember this\n"), "a plain callout is a quote led by its icon:\n\(output)")
        #expect(output.contains("> [!WARNING]\n> Careful\n"), "alert callouts stay GitHub alerts:\n\(output)")
        #expect(output.contains("```swift\nlet x = 1\n```\n\n*Setup*\n"), "code captions follow as text:\n\(output)")
        #expect(output.contains("<details>\n<summary>Add task</summary>\n\n- [ ] Task\n\n</details>"), "buttons export like the HTML export, as their template in a toggle:\n\(output)")
        let file = NoteMarkdown.serialize(page)
        #expect(file.contains("<!-- parc color=\"blue\" id=\"a1b2c3\" -->") && file.contains("<!-- parc breadcrumb -->"), "the file keeps them:\n\(file)")
    }

    @Test func inlineMarkupIsPlain() {
        var red = NoteMarks.plain
        red.color = .text(.red)
        var green = NoteMarks.plain
        green.color = .background(.green)
        var text = NoteText("Red", marks: red)
        text.append(NoteText(" and "))
        text.append(NoteText("green", marks: green))
        text.append(NoteText(" on "))
        text.append(.atom(.date(NoteDateMention(year: 2026, month: 11, day: 20))))
        text.append(NoteText(", see "))
        text.append(.atom(.page(target: "Trip%20notes.md", title: "Trip plans")))
        text.append(NoteText(" and "))
        text.append(.atom(.link(url: "https://example.com/a", title: "Example")))
        text.append(NoteText(" "))
        text.append(.atom(.equation("x^2")))
        text.append(.atom(.raw("<!-- parc color=\"red\" -->")))
        let output = exported(NotePage(blocks: [NoteBlock.paragraph(text)]))
        let date = NoteDateText.label(NoteDateMention(year: 2026, month: 11, day: 20), now: nil)
        let expected = "Red and <mark>green</mark> on @\(date), see [Trip plans](Trip%20notes.md) and [Example](https://example.com/a) $x^2$\n"
        #expect(output == expected, "inline marks export as plain Markdown:\n\(output)\nexpected:\n\(expected)")
        let file = NoteMarkdown.serialize(NotePage(blocks: [NoteBlock.paragraph(text)]))
        #expect(file.contains("data-color") && file.contains("<time") && file.contains("data-mention"), "the file keeps them:\n\(file)")
    }

    @Test func layoutBlocksFlatten() {
        var column = NoteBlock(.column, children: [NoteBlock.paragraph("Left")])
        column.props.width = 0.5
        let columns = NoteBlock(.columns, children: [column, NoteBlock(.column, children: [NoteBlock.paragraph("Right")])])
        let indented = NoteBlock(.paragraph, text: "Parent", children: [NoteBlock.paragraph("Child")])
        let output = exported(NotePage(blocks: [columns, indented]))
        #expect(output == "Left\n\nRight\n\nParent\n\nChild\n", "columns and indents become plain blocks:\n\(output)")
    }

    @Test func mediaExportsPortably() {
        var image = NoteBlock(.image)
        image.props.source = "Attachments/photo.jpg"
        image.props.alt = "Lake"
        image.props.width = 320
        image.props.alignment = .left
        image.props.credit = NoteMediaCredit(name: "Ana", link: "https://unsplash.com/@ana")
        var file = NoteBlock(.file)
        file.props.source = "Attachments/Budget%202026.xlsx"
        var embed = NoteBlock(.embed)
        embed.props.source = "https://www.youtube.com/watch?v=abc"
        var bookmark = NoteBlock(.bookmark)
        bookmark.props.source = "https://example.com"
        bookmark.props.bookmark = NoteBookmark(title: "Example", summary: "A site")
        let output = exported(NotePage(blocks: [image, file, embed, bookmark]))
        #expect(!output.contains("<!--"), "no media attributes:\n\(output)")
        #expect(output.hasPrefix("![Lake](Attachments/photo.jpg)\n\n*Photo by [Ana](https://unsplash.com/@ana?"), "images keep Markdown and credit their photographer:\n\(output)")
        #expect(output.contains("\n[Budget 2026.xlsx](Attachments/Budget%202026.xlsx)\n"), "files are links:\n\(output)")
        #expect(output.contains("\nhttps://www.youtube.com/watch?v=abc\n"), "embeds are links:\n\(output)")
        #expect(output.hasSuffix("[Example](https://example.com)\n"), "bookmarks are links:\n\(output)")
    }

    @Test func frontMatterKeepsContent() {
        var settings = NotePageSettings()
        settings.icon = "\u{1F30A}"
        settings.font = .serif
        settings.fullWidth = true
        settings.smallText = true
        settings.properties = [NotePageProperty(key: "status", value: .text("Draft"))]
        let output = exported(NotePage(settings: settings, blocks: [NoteBlock.paragraph("Body")]))
        #expect(output == "---\nicon: \u{1F30A}\nstatus: Draft\n---\n\nBody\n", "front matter keeps the icon and properties only:\n\(output)")
    }

    @Test func tableOfContentsLinksHeadings() {
        var first = NoteBlock(.heading, text: "Getting started")
        first.props.level = 1
        var second = NoteBlock(.heading, text: "Install & run")
        second.props.level = 2
        var again = NoteBlock(.heading, text: "Getting started")
        again.props.level = 1
        let output = exported(NotePage(blocks: [NoteBlock(.tableOfContents), first, second, again]))
        #expect(output.hasPrefix("- [Getting started](#getting-started)\n  - [Install & run](#install--run)\n- [Getting started](#getting-started-1)\n"), "the table of contents is a list of heading links:\n\(output)")
        #expect(!output.contains("<!--"), "no toc marker:\n\(output)")
    }
}
