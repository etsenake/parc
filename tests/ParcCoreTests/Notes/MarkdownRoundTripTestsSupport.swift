import Foundation
import Testing
@testable import ParcCore

enum MarkdownRoundTripTestsSupport {
    struct MarkdownRandom {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            var value = state
            value ^= value >> 33
            value = value &* 0xff51afd7ed558ccd
            value ^= value >> 33
            return value
        }

        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
        }

        mutating func chance(_ percent: Int) -> Bool { int(1...100) <= percent }

        mutating func pick<T>(_ values: [T]) -> T { values[int(0...(values.count - 1))] }
    }

    struct MarkdownPageGenerator {
        var random: MarkdownRandom
        var allowBreaks = true

        static let words = ["alpha", "beta", "note", "Parc", "file", "a", "1.", "2)", "#", "##", "-", "+", "*", "**", "_", "__", "~", "~~", "==", "`", "``",
                            "[", "]", "[x]", "](", "![", "<", ">", "<b>", "</b>", "<div>", "&", "&amp;", "&#32;", "$", "$5", "$x$", "\\", "|", ":::", "---",
                            "===", "```", "http://x.y", "www.a.bc", "me@x.io", "[[w]]", "[^1]", "!", "@", "{", "}", "(", ")", "\"", "'", "ü", "🎉", "中文",
                            "snake_case", "C#", "2*3", "x_y", ".", ",", ";", "?", "%", "^", "=", "<!--", "-->", "&copy;", "   ", "\t"]

        mutating func plainString(maxWords: Int = 6) -> String {
            var parts: [String] = []
            for _ in 0..<random.int(1...maxWords) { parts.append(random.pick(Self.words)) }
            return parts.joined(separator: random.chance(80) ? " " : "")
        }

        mutating func marks() -> NoteMarks {
            var marks = NoteMarks()
            if random.chance(20) { marks.bold = true }
            if random.chance(20) { marks.italic = true }
            if random.chance(10) { marks.underline = true }
            if random.chance(10) { marks.strikethrough = true }
            if random.chance(10) { marks.code = true }
            if random.chance(10) { marks.link = random.pick(["https://example.com/a", "Other.md", "https://x.org/(p)", "../up dir/n.md", "mailto:a@b.co", "#anchor"]) }
            if random.chance(10) {
                marks.color = random.chance(50) ? .text(random.pick(NoteColor.allCases)) : .background(random.pick(NoteColor.allCases))
            }
            return marks
        }

        mutating func atom() -> NoteAtom {
            switch random.int(0...4) {
            case 0: return .equation(random.pick(["x^2", "a_1 + b", "\\frac{1}{2}", "e^{i\\pi}", "$ odd", "trail ", "5"]))
            case 1:
                if random.chance(50) { return .page(target: "Folder/My Note.md", title: "My Note") }
                return .page(target: random.pick(["Ideas", "Daily/2026-11-20"]), title: random.pick(["Ideas", "Today", "A | B"]))
            case 2:
                var date = NoteDateMention(year: 2026, month: random.int(1...12), day: random.int(1...28), hour: random.chance(50) ? random.int(0...23) : nil,
                                           minute: nil, remind: random.chance(30)).withMinute(random.chance(50))
                if random.chance(30) {
                    date.end = NoteDateEnd(year: 2026, month: date.month, day: min(28, date.day + random.int(0...3)), hour: date.hour.map { min(23, $0 + 1) },
                                           minute: date.minute)
                }
                if date.remind, random.chance(50) { date.remindBefore = random.pick([5, 30, 60, 90, 1440, 10080]) }
                if date.hour != nil, random.chance(25) { date.timeZone = random.pick(["Europe/Paris", "America/New_York", "Asia/Kolkata"]) }
                if random.chance(20) { date.format = random.pick(NoteDateFormat.allCases) }
                if random.chance(20) { date.timeFormat = random.pick(NoteTimeFormat.allCases) }
                return .date(date)
            case 3: return .link(url: random.pick(["https://example.com", "https://a.b/c?d=e&f=g"]), title: plainString(maxWords: 3))
            default: return .raw(random.pick(["<kbd>", "</kbd>", "![img](pic.png)", "<sup>", "<wbr>"]))
            }
        }

        mutating func text(maxPieces: Int = 5, breaks: Bool = true) -> NoteText {
            var text = NoteText()
            for _ in 0..<random.int(1...maxPieces) {
                if random.chance(12) {
                    text.append(.atom(atom(), marks: random.chance(30) ? marks().withoutCode : .plain))
                } else if breaks, allowBreaks, random.chance(10) {
                    text.append(NoteText(random.chance(50) ? "\n" : "\u{2028}", marks: random.chance(20) ? marks().withoutCode : .plain))
                } else {
                    text.append(NoteText(plainString(), marks: random.chance(45) ? marks() : .plain))
                }
            }
            return text
        }

        mutating func leaf(depth: Int) -> NoteBlock {
            var block: NoteBlock
            switch random.int(0...16) {
            case 0, 1, 2:
                block = .paragraph(random.chance(8) ? NoteText() : text())
            case 3:
                block = .heading(random.int(1...6), random.chance(5) ? NoteText() : text(breaks: false))
                if block.props.level <= 2, !block.text.isEmpty, random.chance(40) { block.props.fence = block.props.level == 1 ? "=" : "-" }
            case 4:
                block = NoteBlock(.code, text: NoteText(random.pick(["let x = 1", "```\nfence inside\n```", "", "a\n\nb", "~~~", "  indented\n\tmore", "tail\n"])))
                block.props.language = random.pick(["", "swift", "c++", "js"])
                if random.chance(20), !block.props.language.isEmpty { block.props.info = "title=\"a b\"" }
                block.props.fence = random.pick([nil, "~~~", "````", "    "])
                if block.props.fence == "    ", !block.props.language.isEmpty || block.props.info != nil || block.text.isEmpty || block.text.string.hasSuffix("\n") {
                    block.props.fence = nil
                }
                if let fence = block.props.fence, fence != "    " {
                    let written = NoteMDWriter.fence(for: block.text.string, preferred: fence, info: block.props.language)
                    block.props.fence = written == NoteMDWriter.fence(for: block.text.string, preferred: nil, info: block.props.language) ? nil : written
                }
                if random.chance(15) { block.props.wrap = true }
                if random.chance(15) { block.props.caption = text(breaks: false) }
            case 5:
                block = NoteBlock(.equation, text: NoteText(random.pick(["E = mc^2", "a\n$$\nb", "", "\\sum_{i=1}^n i", "x $$"])))
                if random.chance(20), !NoteMDWriter.equationNeedsFence(block.text.string) { block.props.fence = "````" }
            case 6:
                block = NoteBlock(.divider)
                block.props.fence = random.pick([nil, "***", "___", "* * *"])
            case 7:
                block = NoteBlock(random.pick([.image, .video, .audio, .file, .embed]))
                block.props.source = random.pick(["Attachments/pic.png", "clip.MOV", "https://youtu.be/x", "a b/c(d).pdf", "song.mp3", "https://cdn.x/y", ""])
                if random.chance(50) { block.props.alt = plainString(maxWords: 3) }
                if random.chance(40) { block.props.caption = text(breaks: false) }
                if random.chance(30) { block.props.width = Double(random.int(40...900)) + (random.chance(50) ? 0.5 : 0) }
                if random.chance(30) { block.props.alignment = random.pick([.left, .right]) }
            case 8:
                block = NoteBlock(.bookmark)
                block.props.source = random.pick(["https://example.com/post", "https://a.b/c d"])
                var bookmark = NoteBookmark()
                if random.chance(70) { bookmark.title = plainString(maxWords: 4) }
                if random.chance(50) { bookmark.summary = plainString(maxWords: 5) }
                if random.chance(30) { bookmark.siteName = "Site" }
                if random.chance(30) { bookmark.iconURL = "https://example.com/i.ico" }
                if random.chance(30) { bookmark.imageURL = "https://example.com/i.png" }
                block.props.bookmark = bookmark
                if random.chance(30) { block.props.caption = text(breaks: false) }
            case 9:
                block = NoteBlock(.pageLink, text: random.chance(10) ? NoteText() : text(maxPieces: 2, breaks: false))
                block.text.updateMarks(in: 0..<block.text.length) { $0.link = nil }
                block.props.target = random.pick(["Other.md", "Folder/Some%20Note.md", "../Up.markdown"])
            case 10:
                var table = NoteTable(rows: (0..<random.int(1...4)).map { _ in (0..<random.int(1...3)).map { _ in random.chance(15) ? NoteText() : text(maxPieces: 3) } })
                table.normalize()
                table.alignments = table.alignments.map { _ in random.pick([nil, .left, .center, .right]) }
                if random.chance(20) { table.headerRow = false }
                if random.chance(20) { table.headerColumn = true }
                if random.chance(20) { table.columnWidths = table.columnWidths.map { _ in random.chance(50) ? Double(random.int(60...300)) : nil } }
                block = NoteBlock(.table)
                block.props.table = table
            case 11:
                block = NoteBlock(.tableOfContents)
            case 12:
                block = NoteBlock(.html, text: NoteText(random.pick(["<div align=\"center\">\n  <img src=\"a.png\">\n</div>", "<!-- note to self -->", "<table>\n<tr><td>x</td></tr>\n</table>"])))
                return block
            case 13:
                block = NoteBlock(.raw, text: NoteText(random.pick(["[docs]: https://example.com/docs", "[^n]: A footnote.\n    Continued."])))
                return block
            case 14:
                block = .paragraph()
                return block
            default:
                block = .paragraph(text())
            }
            if random.chance(12) { block.color = random.chance(50) ? .text(random.pick(NoteColor.allCases)) : .background(random.pick(NoteColor.allCases)) }
            if block.kind == .code, block.props.fence == "    ", block.color != nil || block.props.wrap || !block.props.caption.isEmpty { block.props.fence = nil }
            if block.kind == .paragraph || block.kind == .heading, depth < 3, random.chance(20) {
                block.children = blocks(depth: depth + 1, count: random.int(1...3), trailingEmpty: true)
            }
            return block
        }

        mutating func button(depth: Int) -> NoteBlock {
            var actions: [NoteButtonAction] = []
            for _ in 0..<random.int(0...3) {
                switch random.int(0...3) {
                case 0, 1:
                    actions.append(.insert(placement: random.pick(NoteButtonPlacement.allCases),
                                           blocks: blocks(depth: depth + 1, count: random.int(0...3), trailingEmpty: true)))
                case 2:
                    actions.append(.confirm(message: random.chance(20) ? "" : plainString(maxWords: 4)))
                default:
                    actions.append(.open(target: random.pick(["https://example.com/a?b=c&d", "Other%20Note.md", "../Up.md", ""])))
                }
            }
            let icon: String? = random.chance(40) ? random.pick(["✅", "🚀", "📓"]) : nil
            var block = NoteBlock.button(name: NoteButton.normalizedName(plainString(maxWords: 4)), icon: icon, actions: actions)
            if random.chance(20) { block.props.expanded = true }
            if random.chance(15) { block.color = random.chance(50) ? .text(.blue) : .background(.yellow) }
            return block
        }

        mutating func container(depth: Int) -> NoteBlock {
            switch random.int(0...5) {
            case 0:
                var block = NoteBlock(.toggle, text: text(breaks: false), children: blocks(depth: depth + 1, count: random.int(0...3), trailingEmpty: true))
                block.props.expanded = random.chance(50)
                if random.chance(30) { block.kind = .heading; block.props.level = random.int(1...6); block.props.toggleable = true }
                if random.chance(15) { block.color = .background(.yellow) }
                return block
            case 1:
                var block = NoteBlock(.quote, text: random.chance(15) ? NoteText() : text(), children: blocks(depth: depth + 1, count: random.int(0...2), trailingEmpty: true))
                if random.chance(15) { block.color = .text(.purple) }
                return block
            case 2:
                var block = NoteBlock(.callout, children: blocks(depth: depth + 1, count: random.int(0...2), trailingEmpty: true))
                block.props.alert = random.pick([nil, "TIP", "WARNING", "faq", "Danger"])
                block.text = random.chance(15) ? NoteText() : text(breaks: block.props.alert == nil || block.props.alert == "TIP" || block.props.alert == "WARNING")
                if random.chance(70) { block.props.icon = random.pick(["💡", "⚠️", "📌", "Attachments/icon.png"]) }
                if random.chance(20) { block.props.toggleable = true; block.props.expanded = random.chance(50) }
                if random.chance(30) { block.color = .background(random.pick(NoteColor.allCases)) }
                return block
            case 3:
                var columns = NoteBlock(.columns)
                for _ in 0..<random.int(1...3) {
                    var column = NoteBlock(.column, children: blocks(depth: depth + 1, count: random.int(1...3), trailingEmpty: true))
                    if random.chance(40) { column.props.width = Double(random.int(1...99)) / Double(random.pick([100, 3, 7])) }
                    columns.children.append(column)
                }
                return columns
            case 4:
                return button(depth: depth)
            default:
                return leaf(depth: depth)
            }
        }

        mutating func listRun(depth: Int) -> [NoteBlock] {
            let kind: NoteBlockKind = random.pick([.bulletedItem, .numberedItem, .todo])
            let loose = random.chance(25)
            let bullet: String? = random.pick([nil, "*", "+"])
            let ordered = kind == .numberedItem || (kind == .todo && random.chance(20))
            let delimiter: String? = kind == .todo ? (ordered ? random.pick([".", ")"]) : nil) : kind == .numberedItem ? random.pick([nil, ")"]) : nil
            var run: [NoteBlock] = []
            let count = random.int(1...4)
            for index in 0..<count {
                var item = NoteBlock(kind, text: random.chance(10) ? NoteText() : text())
                item.props.looseList = loose && count > 1
                if !ordered { item.props.bulletMarker = bullet }
                item.props.orderedDelimiter = delimiter
                if kind == .todo { item.props.checked = random.chance(50) }
                if ordered, index == 0, random.chance(30) { item.props.listStart = random.int(2...40) }
                if random.chance(20) { item.color = .text(.red) }
                if depth < 3, random.chance(30) { item.children = blocks(depth: depth + 1, count: random.int(1...2), trailingEmpty: false) }
                run.append(item)
            }
            return run
        }

        mutating func blocks(depth: Int, count: Int, trailingEmpty: Bool) -> [NoteBlock] {
            var result: [NoteBlock] = []
            var lastListKey: String?
            for _ in 0..<count {
                if random.chance(30) {
                    let run = listRun(depth: depth)
                    let key = Self.listKey(run[0])
                    if key == lastListKey { result.append(.paragraph("separator")) }
                    result.append(contentsOf: run)
                    lastListKey = key
                } else {
                    result.append(depth < 3 && random.chance(30) ? container(depth: depth) : leaf(depth: depth))
                    lastListKey = nil
                }
            }
            if !trailingEmpty {
                while let last = result.last, last.kind == .paragraph, last.text.isEmpty, last.color == nil { result.removeLast() }
            }
            for index in result.indices where result[index].kind == .code && result[index].props.fence == "    " {
                if let previous = result[..<index].last(where: { !NoteMDWriter.isBareEmptyParagraph($0) }), previous.kind.isListItem || previous.kind == .raw {
                    result[index].props.fence = nil
                }
            }
            var lastNumber: Int?
            for index in result.indices {
                let block = result[index]
                let ordered = block.kind == .numberedItem || (block.kind == .todo && block.props.orderedDelimiter != nil)
                guard ordered else { lastNumber = nil; continue }
                let expected = (lastNumber ?? 0) + 1
                if result[index].props.listStart == expected { result[index].props.listStart = nil }
                lastNumber = result[index].props.listStart ?? expected
            }
            return result
        }

        static func listKey(_ block: NoteBlock) -> String {
            if block.kind == .numberedItem { return "o" + (block.props.orderedDelimiter ?? ".") }
            if block.kind == .todo, let delimiter = block.props.orderedDelimiter { return "o" + delimiter }
            return "b" + (block.props.bulletMarker ?? "-")
        }
    }
}

private extension NoteMarks {
    var withoutCode: NoteMarks {
        var value = self
        value.code = false
        return value
    }
}

private extension NoteDateMention {
    func withMinute(_ include: Bool) -> NoteDateMention {
        var value = self
        if hour != nil { value.minute = include ? 30 : 0 }
        return value
    }
}
