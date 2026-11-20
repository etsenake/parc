import Foundation

@main @MainActor
struct NoteCustomEmojiCodecTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    nonisolated static let names: Set<String> = ["party", "parrot", "b", "a", "+1"]

    static func main() {
        naming()
        reading()
        writing()
        roundTrips()
        settingsAndCallouts()
        html()
        print("NoteCustomEmojiCodecTests passed")
    }

    static func atom(_ name: String) -> NoteText { .atom(.customEmoji(name)) }

    static func text(_ pieces: NoteText...) -> NoteText {
        var value = NoteText()
        for piece in pieces { value.append(piece) }
        return value
    }

    static func firstText(_ markdown: String, names: Set<String> = names) -> NoteText {
        NoteMarkdown.parse(markdown, customEmoji: names).blocks.first?.text ?? NoteText()
    }

    static func naming() {
        expect(NoteCustomEmojiName.normalized("Party Parrot!") == "party-parrot", "spaces and punctuation become one dash")
        expect(NoteCustomEmojiName.normalized("  :Fiesta: ") == "fiesta", "colons and case fall away")
        expect(NoteCustomEmojiName.normalized("Crème brûlée") == "creme-brulee", "accents fold")
        expect(NoteCustomEmojiName.normalized("😀") == nil, "a name needs letters or digits")
        expect(NoteCustomEmojiName.normalized("__--__") == nil, "dashes alone aren't a name")
        expect(NoteCustomEmojiName.normalized(String(repeating: "a", count: 80))?.count == NoteCustomEmojiName.maximumLength, "names are capped")
        expect(NoteCustomEmojiName.normalized("thumbs_up+1") == "thumbs_up+1", "underscores and plus stay")
        expect(NoteCustomEmojiName.isValid("party") && !NoteCustomEmojiName.isValid("Party") && !NoteCustomEmojiName.isValid("par ty"), "names are lowercase words")
        expect(NoteCustomEmojiName.name(inReference: ":party:") == "party", "references read back")
        expect(NoteCustomEmojiName.name(inReference: "party") == nil && NoteCustomEmojiName.name(inReference: "::") == nil, "bare words aren't references")
        expect(NoteCustomEmojiName.name(inReference: "🎉") == nil, "emoji aren't references")
        expect(NoteAtom.customEmoji("party").fallbackText == ":party:", "a custom emoji falls back to its shortcode")
        let page = NotePage(blocks: [NoteBlock.paragraph(text("Hi ", atom("party"))), NoteBlock(.table, props: {
            var props = NoteBlockProps()
            props.table = NoteTable(rows: [[atom("parrot")]])
            return props
        }())])
        expect(NoteCustomEmojiName.names(in: page) == ["party", "parrot"], "pages list the custom emoji they use, cells included")
    }

    static func reading() {
        expect(firstText("Hi :party: there") == text("Hi ", atom("party"), " there"), "a known name reads as a custom emoji")
        expect(firstText("Hi :party: there", names: []) == "Hi :party: there", "without a library it stays text")
        expect(firstText("Hi :nope: there") == "Hi :nope: there", "names the library lacks stay text")
        expect(firstText("Hi \\:party: there") == "Hi :party: there", "an escaped colon keeps the text")
        expect(firstText("`:party:`").string == ":party:" && firstText("`:party:`").marks(at: 0).code, "code spans stay code")
        expect(firstText(":party::parrot:") == text(atom("party"), atom("parrot")), "neighbours read one by one")
        expect(firstText("10:30:00") == "10:30:00", "times don't turn into emoji")
        expect(firstText("x:a:b:") == text("x", atom("a"), "b:"), "the first match wins and its colon is spent")
        expect(firstText("thumbs :+1:") == text("thumbs ", atom("+1")), "plus signs work in names")
        let bold = firstText("**:party:**")
        expect(bold.length == 1 && bold.marks(at: 0).bold && bold.marks(at: 0).atom == .customEmoji("party"), "custom emoji take marks")
        let linked = firstText("[go :party:](https://example.com)")
        expect(linked.marks(at: 3).atom == .customEmoji("party") && linked.marks(at: 3).link == "https://example.com", "custom emoji live inside links")
        let heading = NoteMarkdown.parse("## Plans :party:", customEmoji: names).blocks.first
        expect(heading?.kind == .heading && heading?.text == text("Plans ", atom("party")), "headings read them too")
        let table = NoteMarkdown.parse("| a | b |\n| - | - |\n| :party: | x |", customEmoji: names).blocks.first
        expect(table?.props.table?.rows[1][0] == atom("party"), "table cells read them too")
        expect(NotePlainText.serialize(NotePage(blocks: [.paragraph(text("Yay ", atom("party")))])) == "Yay :party:", "plain text keeps the shortcode")
    }

    static func write(_ value: NoteText, names: Set<String> = names) -> String {
        NoteMarkdown.serialize(NotePage(blocks: [.paragraph(value)]), customEmoji: names)
    }

    static func writing() {
        expect(write(text("Hi ", atom("party"), " there")) == "Hi :party: there\n", "a custom emoji writes as its shortcode")
        expect(write(text("Hi ", atom("party")), names: []) == "Hi :party:\n", "it writes plainly without a library too")
        expect(write("Hi :party: there") == "Hi \\:party: there\n", "text that would read as a known emoji is escaped")
        expect(write("Hi :party: there", names: []) == "Hi :party: there\n", "unknown shortcodes are left alone")
        expect(write("Hi :nope: there") == "Hi :nope: there\n", "names the library lacks are left alone")
        expect(write(text("Hi :party: and ", atom("party")), names: []) == "Hi \\:party: and :party:\n", "text beside a used emoji gets escaped")
        expect(write("10:30:00") == "10:30:00\n", "ordinary colons are never escaped")
        expect(write(text(atom("party"), "**")).hasPrefix(":party:"), "atoms lead cleanly")
    }

    static func roundTrips() {
        let samples: [NoteText] = [
            text("Hi ", atom("party"), " there"),
            text(":b", atom("a")),
            text(":", atom("a"), ":"),
            text("x:a:", atom("b"), ":a"),
            text(atom("a"), "b:"),
            text("a", atom("party"), "b"),
            text("Hi :party: there"),
            text(":parrot", atom("party"), "parrot:"),
            text("`", atom("party"), "`"),
            NoteText(pieces: [("bold ", NoteMarks(bold: true)), (NoteAtom.character, { var m = NoteMarks(bold: true); m.atom = .customEmoji("party"); return m }()), (" end", .plain)]),
        ]
        for sample in samples {
            let markdown = write(sample)
            let back = firstText(markdown)
            expect(back == sample, "round trip keeps \(sample.plainText.debugDescription), wrote \(markdown.debugDescription)")
        }
        let file = "Plans :party:\n\nEscaped \\:party: stays\n\nUnknown :nope: stays\n"
        expect(NoteMarkdown.serialize(NoteMarkdown.parse(file, customEmoji: names), customEmoji: names) == file, "files come back byte for byte")
        let readme = "Ship it :tada: and :+1:\n"
        expect(NoteMarkdown.serialize(NoteMarkdown.parse(readme)) == readme, "GitHub shortcodes in other files stay untouched")
    }

    static func settingsAndCallouts() {
        var settings = NotePageSettings()
        settings.icon = ":party:"
        var props = NoteBlockProps()
        props.icon = ":parrot:"
        let page = NotePage(settings: settings, blocks: [NoteBlock(.callout, text: "Heads up", props: props)])
        let markdown = NoteMarkdown.serialize(page, customEmoji: names)
        expect(markdown.hasPrefix("---\nicon: \":party:\"\n---\n"), "the page icon is a quoted shortcode, got \(markdown.debugDescription)")
        expect(markdown.contains("icon=\":parrot:\""), "a callout keeps its custom icon in the Parc comment")
        let back = NoteMarkdown.parse(markdown, customEmoji: names)
        expect(back.settings.icon == ":party:", "the page icon reads back")
        expect(back.blocks.first?.kind == .callout && back.blocks.first?.props.icon == ":parrot:", "the callout icon reads back")
        expect(NoteMarkdown.serialize(back, customEmoji: names) == markdown, "icons round-trip")
        let summary = NoteFileSummary.frontMatter(markdown.components(separatedBy: "\n"))
        expect(summary.icon == ":party:", "tab icons read the shortcode from front matter")
    }

    static func html() {
        let image = URL(fileURLWithPath: "/tmp/notes/.parc/emoji/party.png")
        let assets: (String) -> URL? = { $0 == ":party:" ? image : nil }
        var settings = NotePageSettings()
        settings.icon = ":party:"
        var props = NoteBlockProps()
        props.icon = ":party:"
        let page = NotePage(settings: settings, blocks: [.paragraph(text("Yay ", atom("party"), " and ", atom("gone"))),
                                                         NoteBlock(.callout, text: "Note", props: props)])
        let document = NotePageHTML.document(page, title: "Plans", assets: assets, embedImages: false)
        expect(document.contains("<img class=\"custom-emoji inline-emoji\" alt=\":party:\" title=\":party:\" src=\"\(image.absoluteString)\">"),
               "inline custom emoji export as images")
        expect(document.contains("and :gone:"), "missing ones export as their shortcode")
        expect(document.contains("class=\"page-icon page-icon-image custom-emoji\""), "the page icon exports as an image")
        expect(document.contains("class=\"callout-icon custom-emoji\""), "the callout icon exports as an image")
        let fragment = NotePageHTML.fragment(page.blocks, assets: assets)
        expect(fragment.contains("style=\"height:1.2em;width:auto;vertical-align:-0.2em\""), "copied HTML sizes custom emoji inline")
    }
}
