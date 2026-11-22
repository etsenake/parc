import Foundation
import Testing
@testable import ParcCore

enum NoteHTMLRoundTripTestsSupport {
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
            tinted(.heading(3, "Pink band"), .background(.pink))
        ]
    }

    private static func tinted(_ block: NoteBlock, _ style: NoteColorStyle) -> NoteBlock {
        var copy = block
        copy.color = style
        return copy
    }
}
