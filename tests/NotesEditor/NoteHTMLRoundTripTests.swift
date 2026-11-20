import Foundation

@main
struct NoteHTMLRoundTripTests {
    static func expect(_ value: Bool, _ message: @autoclosure () -> String, line: UInt = #line) {
        NoteHTMLCheck.expect(value, value ? "" : message(), line: line)
    }

    static func main() {
        roundTrip()
        fragmentShape()
        documentShape()
        embeddedImages()
        NoteHTMLCheck.finish("NoteHTMLRoundTripTests")
    }

    static func styled(_ configure: (inout NoteMarks) -> Void) -> NoteMarks {
        var marks = NoteMarks.plain
        configure(&marks)
        return marks
    }

    static func block(_ kind: NoteBlockKind, _ text: NoteText = NoteText(), color: NoteColorStyle? = nil,
                      children: [NoteBlock] = [], _ configure: (inout NoteBlockProps) -> Void = { _ in }) -> NoteBlock {
        var props = NoteBlockProps()
        configure(&props)
        return NoteBlock(kind, text: text, props: props, color: color, children: children)
    }

    static var richText: NoteText {
        var text = NoteText(pieces: [
            ("Plain, ", .plain),
            ("bold", styled { $0.bold = true }),
            (" and ", .plain),
            ("italic", styled { $0.italic = true }),
            (", ", .plain),
            ("under", styled { $0.underline = true }),
            (" ", .plain),
            ("struck", styled { $0.strikethrough = true }),
            (" ", .plain),
            ("code <&>", styled { $0.code = true }),
            (" ", .plain),
            ("bold link", styled { $0.bold = true; $0.link = "https://parc.example/a?b=1&c=2" }),
            (" plain link", styled { $0.link = "https://parc.example/a?b=1&c=2" }),
            (" ", .plain),
            ("red", styled { $0.color = .text(.red) }),
            (" ", .plain),
            ("highlight", styled { $0.color = .background(.yellow); $0.italic = true }),
            (" ", .plain),
            ("grey", styled { $0.color = .text(.gray) }),
            (" two  spaces\tand a tab\nnew line ", .plain)
        ])
        text.append(.atom(.equation("x^2 + \\frac{1}{2}")))
        text.append(NoteText(" mention "))
        text.append(.atom(.page(target: "Ideas/Big ideas.md", title: "Big ideas")))
        text.append(NoteText(" on "))
        text.append(.atom(.date(NoteDateMention(year: 2026, month: 11, day: 20, hour: 9, minute: 30, remind: true))))
        text.append(NoteText(" via "))
        text.append(.atom(.link(url: "https://parc.example/post", title: "Parc post")))
        text.append(NoteText("."))
        return text
    }

    static var page: [NoteBlock] {
        var table = NoteTable(rows: [["Name", "Role"], ["Ann", NoteText("Lead", marks: styled { $0.bold = true })],
                                     ["Bo", "Multi\nline"]], headerRow: true, headerColumn: true)
        table.alignments = [nil, .center]
        return [
            .heading(1, "Big title"),
            block(.heading, "Folded heading", color: .text(.blue), children: [.paragraph("Inside the fold")]) {
                $0.level = 2
                $0.toggleable = true
                $0.expanded = false
            },
            .paragraph(richText),
            block(.paragraph, "Text with kids", children: [.paragraph("Nested text"), block(.heading, "Nested heading", children: [
                block(.bulletedItem, "Under the heading")]) { $0.level = 3 }]),
            block(.paragraph, children: [.paragraph("Under an empty line")]),
            .paragraph(),
            block(.bulletedItem, "Bullet", children: [.paragraph("A child paragraph"), block(.bulletedItem, "Nested bullet")]),
            block(.bulletedItem, "Second bullet", color: .background(.green)),
            block(.numberedItem, "Fourth") { $0.listStart = 4 },
            block(.numberedItem, "Fifth"),
            block(.todo, "Done thing", children: [block(.todo, "Sub task")]) { $0.checked = true },
            block(.todo, "Open thing"),
            block(.toggle, "Collapsed toggle", children: [.paragraph("Hidden child"), block(.code, "print(1)") { $0.language = "python" }]) {
                $0.expanded = false
            },
            block(.toggle, "Open toggle", children: [.paragraph("Shown child")]),
            block(.quote, "A wise quote", color: .text(.purple), children: [block(.bulletedItem, "with a point")]),
            block(.quote, children: [.paragraph("Quote whose text is empty")]),
            block(.callout, "Compass callout", color: .background(.blue), children: [.paragraph("Callout child")]) { $0.icon = "🧭" },
            block(.callout, "Careful now") { $0.alert = "WARNING" },
            block(.callout, "Plain callout"),
            NoteBlock(.divider),
            block(.code, "\nlet tag = \"<b>\" & more\n\tindented") {
                $0.language = "swift"
                $0.caption = "A caption"
            },
            block(.equation, "\\int_0^1 x\\,dx"),
            block(.image) {
                $0.source = "Attachments/cat photo.png"
                $0.alt = "Cat"
                $0.caption = NoteText(pieces: [("Meow ", .plain), ("loudly", styled { $0.italic = true })])
            },
            block(.video) { $0.source = "Attachments/clip.mov" },
            block(.audio) { $0.source = "Attachments/song.m4a" },
            block(.file) { $0.source = "Attachments/report.pdf" },
            block(.file) {
                $0.source = "Attachments/x.zip"
                $0.alt = "Archive"
            },
            block(.bookmark) {
                $0.source = "https://example.com/article"
                $0.bookmark = NoteBookmark(title: "An article", summary: "Worth a read", siteName: "Example", iconURL: nil, imageURL: nil)
            },
            block(.embed) { $0.source = "https://www.youtube.com/embed/xyz" },
            block(.table) { $0.table = table },
            NoteBlock(.tableOfContents),
            NoteBlock(.columns, children: [
                NoteBlock(.column, children: [.paragraph("Left"), block(.bulletedItem, "Left list")]),
                NoteBlock(.column, children: [.heading(3, "Right")])
            ]),
            block(.pageLink, "Other note") { $0.target = "Other note.md" },
            NoteBlock(.html, text: "<div class=\"x\">hi &amp; bye</div>"),
            NoteBlock(.raw, text: "::: weird\n<stuff> & things"),
            NoteBlock(.paragraph, text: "Green words", color: .text(.green)),
            NoteBlock.heading(3, "Pink band").tinted(.background(.pink))
        ]
    }

    static func roundTrip() {
        let original = page
        let html = NotePageHTML.fragment(original)
        let back = NoteHTMLReader.blocks(from: html, baseURL: nil)
        let problems = NoteHTMLCheck.same(original, back)
        expect(problems.isEmpty, "round trip differs:\n" + problems.prefix(12).joined(separator: "\n") + "\n" + NoteHTMLCheck.outline(back))
        let again = NotePageHTML.fragment(back)
        expect(again == html, "a second trip writes the same HTML")
    }

    static func fragmentShape() {
        let html = NotePageHTML.fragment(page)
        expect(!html.contains("<html") && !html.contains("<style"), "fragments are bare HTML")
        expect(html.contains("<h1 id=\"big-title\">Big title</h1>"), "semantic headings with anchors for the outline")
        expect(html.contains("<strong>bold</strong>") && html.contains("<em>italic</em>") && html.contains("<u>under</u>")
               && html.contains("<s>struck</s>") && html.contains("<code>code &lt;&amp;&gt;</code>"), "semantic inline marks")
        expect(html.contains("<a href=\"https://parc.example/a?b=1&amp;c=2\"><strong>bold link</strong> plain link</a>"),
               "one anchor spans a link's runs")
        expect(html.contains("style=\"color:#D44C47\""), "colours carry inline styles for Mail and Docs")
        expect(html.contains("<ol start=\"4\">"), "list start")
        expect(html.contains("<input type=\"checkbox\" disabled checked>"), "task list checkboxes")
        expect(html.contains("<pre><code class=\"language-swift\">"), "code language class")
        expect(html.contains("<thead><tr><th scope=\"col\""), "table header row")
        expect(html.contains("two &nbsp;spaces"), "runs of spaces survive")
        expect(html.contains("<p>Text with kids</p><div class=\"indented\" style=\"padding-left:1.5em\"><p>Nested text</p>"),
               "text children sit in an indented div right after their parent")
        let notion = NoteHTMLReader.blocks(from: "<p>Parent</p><div class=\"indented\"><p>Child</p></div><h2>Head</h2><div class=\"indented\"><p>Kid</p></div>", baseURL: nil)
        expect(notion.count == 2 && notion[0].children.map(\.text.string) == ["Child"] && notion[1].children.map(\.text.string) == ["Kid"],
               "Notion's exported indented divs nest under the block before them")
        let blank = NotePageHTML.fragment([])
        expect(blank.isEmpty, "nothing in, nothing out")
        let resolved = NotePageHTML.fragment([block(.image) { $0.source = "Attachments/a.png" }]) { source in
            URL(fileURLWithPath: "/Users/me/Notes").appendingPathComponent(source)
        }
        expect(resolved.contains("src=\"file:///Users/me/Notes/Attachments/a.png\""), "assets resolve for the clipboard: \(resolved)")
    }

    static func documentShape() {
        var settings = NotePageSettings()
        settings.icon = "🌿"
        settings.cover = NoteCover(source: "Attachments/cover.jpg", position: 0.25)
        settings.font = .serif
        settings.smallText = true
        settings.fullWidth = true
        settings.properties = [NotePageProperty(key: "Tags", value: .list(["home", "plans"])),
                               NotePageProperty(key: "Done", value: .checkbox(true))]
        let note = NotePage(settings: settings, blocks: page)
        let html = NotePageHTML.document(note, title: "Weekend <plans>", assets: { _ in nil }, embedImages: false)
        expect(html.hasPrefix("<!DOCTYPE html>"), "standalone document")
        expect(html.contains("<title>Weekend &lt;plans&gt;</title>") && html.contains("<h1 class=\"page-title\">Weekend &lt;plans&gt;</h1>"),
               "escaped title")
        expect(html.contains("class=\"page-font-serif small-text full-width has-cover has-icon\""), "page settings become body classes")
        expect(html.contains("<div class=\"page-icon\">🌿</div>"), "emoji icon")
        expect(html.contains("class=\"page-cover\"") && html.contains("object-position:center 25%"), "cover with position")
        expect(html.contains("--font:\"Nunito\",ui-rounded"), "Nunito-first font stack")
        expect(html.contains("prefers-color-scheme:dark") && html.contains("@media print"), "dark mode and print styles")
        expect(html.contains("<details open"), "toggles print open in documents")
        expect(html.contains("<span class=\"tex\">\\int_0^1 x\\,dx</span>"), "equations show their TeX")
        expect(html.contains("id=\"big-title\"") && html.contains("href=\"#big-title\""), "table of contents links to headings")
        expect(html.contains("class=\"highlight-red\""), "document colours use classes")
        expect(html.contains("<span class=\"property-chip\">home</span>"), "properties render")
        expect(html.contains("class=\"bookmark-card\""), "bookmarks render as cards")
        expect(!html.contains("/*"), "no comments sneak into the CSS")
        let images = NotePageHTML.document(NotePage(blocks: [block(.equation, "E=mc^2"), .paragraph(.atom(.equation("a")))]), title: "",
                                           assets: { _ in nil }, embedImages: false) { tex, display, _ in
            URL(string: "https://math.example/" + (display ? "block" : "inline") + "/" + (tex == "a" ? "a" : "e") + ".svg")
                .map { NoteEquationArt(url: $0) }
        }
        expect(images.contains("<title>Untitled</title>"), "empty titles get a name")
        expect(images.contains("src=\"https://math.example/block/e.svg\"") && images.contains("src=\"https://math.example/inline/a.svg\""),
               "equation images replace TeX when given")
        let reread = NoteHTMLReader.blocks(from: html, baseURL: nil)
        expect(reread.contains { $0.kind == .table } && reread.contains { $0.kind == .callout && $0.props.icon == "🧭" },
               "an exported document reads back in")
    }

    static func embeddedImages() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NoteHTML-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pixel = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        let file = folder.appendingPathComponent("dot.png")
        try? pixel.write(to: file)
        var settings = NotePageSettings()
        settings.icon = "Attachments/dot.png"
        let note = NotePage(settings: settings, blocks: [block(.image) { $0.source = "Attachments/dot.png" },
                                                          block(.video) { $0.source = "Attachments/dot.png" },
                                                          block(.image) { $0.source = "https://cdn.example/remote.png" }])
        let resolve: (String) -> URL? = { $0.hasPrefix("Attachments/") ? folder.appendingPathComponent(($0 as NSString).lastPathComponent) : nil }
        let embedded = NotePageHTML.document(note, title: "Dots", assets: resolve, embedImages: true)
        let uri = "data:image/png;base64," + pixel.base64EncodedString()
        expect(embedded.components(separatedBy: uri).count == 3, "local images and the icon embed as data URIs")
        expect(embedded.contains("<video src=\"" + file.absoluteString + "\""), "video stays a link")
        expect(embedded.contains("src=\"https://cdn.example/remote.png\""), "remote images stay remote")
        let linked = NotePageHTML.document(note, title: "Dots", assets: resolve, embedImages: false)
        expect(!linked.contains("data:image") && linked.contains("src=\"" + file.absoluteString + "\""), "without embedding, files link")
    }
}

extension NoteBlock {
    func tinted(_ style: NoteColorStyle) -> NoteBlock {
        var copy = self
        copy.color = style
        return copy
    }
}
