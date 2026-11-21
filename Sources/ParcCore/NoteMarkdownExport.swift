import Foundation

enum NoteMDExport {
    static func portable(_ page: NotePage) -> NotePage {
        var settings = page.settings
        settings.font = .standard
        settings.smallText = false
        settings.fullWidth = false
        settings.locked = false
        settings.backlinks = nil
        settings.cover?.position = 0.5
        let blocks = sequence(page.blocks)
        return NotePage(settings: settings, blocks: contents(blocks, outline: outline(blocks)))
    }

    static func sequence(_ blocks: [NoteBlock]) -> [NoteBlock] {
        blocks.flatMap(convert)
    }

    private static func convert(_ original: NoteBlock) -> [NoteBlock] {
        var block = original
        block.color = nil
        block.props.anchor = nil
        block.text = text(block.text)
        block.props.caption = text(block.props.caption)
        if var table = block.props.table {
            table.rows = table.rows.map { $0.map(text) }
            table.columnWidths = []
            table.merges = []
            table.cellColors = [:]
            block.props.table = table
        }
        switch block.kind {
        case .synced, .columns, .column:
            return sequence(block.children)
        case .breadcrumb:
            return []
        case .button:
            let value = block.buttonValue
            let label = NoteMDButtonFormat.label(name: value.displayName, icon: block.props.icon.flatMap { $0.isEmpty ? nil : $0 })
            return [NoteBlock(.toggle, text: NoteText(label), props: collapsed(), children: sequence(value.templateBlocks))]
        case .paragraph,
             .heading where !block.props.toggleable:
            let children = sequence(block.children)
            block.children = []
            return [block] + children
        case .callout where block.props.alert == nil:
            var quote = NoteBlock(.quote, text: block.text, children: sequence(block.children), id: block.id)
            if let icon = block.props.icon, !icon.isEmpty, !isImage(icon) {
                quote.text = block.text.isEmpty ? NoteText(icon) : NoteText(icon + " ") + block.text
            }
            return [quote]
        case .file, .embed, .video, .audio, .pdf:
            guard block.kind == .file || block.kind == .embed || NoteMDMedia.inferredKind(block.props.source ?? "") != block.kind
            else { return [media(block)] + credit(block) }
            return [link(block)] + credit(block)
        case .image:
            return [media(block)] + credit(block)
        case .code where !block.props.caption.isEmpty:
            var caption = block.props.caption
            caption.updateMarks(in: 0..<caption.length) { $0.italic = true }
            block.props.caption = NoteText()
            return [block, NoteBlock.paragraph(caption)]
        default:
            block.children = sequence(block.children)
            return [block]
        }
    }

    private static func collapsed() -> NoteBlockProps {
        var props = NoteBlockProps()
        props.expanded = false
        return props
    }

    private static func isImage(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file:") || lower.hasPrefix("data:")
            || NoteMDMedia.imageExtensions.contains(NoteMDMedia.pathExtension(value))
    }

    private static func media(_ block: NoteBlock) -> NoteBlock {
        var plain = block
        plain.props.width = nil
        plain.props.height = nil
        plain.props.alignment = .center
        plain.props.crop = nil
        plain.props.mask = nil
        plain.props.credit = nil
        return plain
    }

    private static func link(_ block: NoteBlock) -> NoteBlock {
        let source = block.props.source ?? ""
        var label = block.props.alt.flatMap { $0.isEmpty ? nil : $0 } ?? block.props.caption.plainText
        if label.isEmpty {
            let decoded = source.removingPercentEncoding ?? source
            label = block.kind == .file ? (decoded as NSString).lastPathComponent : decoded
        }
        if label.isEmpty { label = source }
        var marks = NoteMarks.plain
        marks.link = source
        return NoteBlock.paragraph(source.isEmpty ? NoteText(label) : NoteText(label, marks: marks))
    }

    private static func credit(_ block: NoteBlock) -> [NoteBlock] {
        guard NoteMDMedia.carriesCredit(block.kind), let credit = block.props.credit, !credit.name.isEmpty else { return [] }
        let pieces = credit.parts.map { part -> (String, NoteMarks) in
            var marks = NoteMarks.plain
            marks.italic = true
            switch part {
            case .text(let value): return (value, marks)
            case .link(let value, let url):
                marks.link = url.absoluteString
                return (value, marks)
            }
        }
        return [NoteBlock.paragraph(NoteText(pieces: pieces))]
    }

    static func text(_ original: NoteText) -> NoteText {
        guard original.spans.contains(where: { $0.marks.color != nil || $0.marks.atom != nil }) else { return original }
        var pieces: [(String, NoteMarks)] = []
        let string = original.string as NSString
        for run in original.runs() {
            var marks = run.marks
            if let color = marks.color { marks.color = color.isBackground ? .background(.yellow) : nil }
            guard let atom = marks.atom else {
                pieces.append((string.substring(with: NSRange(location: run.range.lowerBound, length: run.range.count)), marks))
                continue
            }
            var plain = marks
            plain.atom = nil
            for _ in run.range {
                switch atom {
                case .date(let date):
                    pieces.append(("@" + NoteDateText.label(date, now: nil), plain))
                case .link(let url, let title):
                    var linked = plain
                    linked.link = url
                    pieces.append((title.isEmpty ? url : title, linked))
                case .page(let target, let title):
                    var linked = plain
                    linked.link = target
                    pieces.append((title.isEmpty ? "Untitled" : title, linked))
                case .raw(let source) where NoteMDAttributes.parse(source) != nil:
                    continue
                case .equation, .raw, .customEmoji:
                    pieces.append((NoteAtom.character, marks))
                }
            }
        }
        return NoteText(pieces: pieces)
    }

    struct Heading {
        var level: Int
        var title: String
        var slug: String
    }

    static func outline(_ blocks: [NoteBlock]) -> [Heading] {
        var used: [String: Int] = [:]
        var result: [Heading] = []
        func walk(_ list: [NoteBlock]) {
            for block in list {
                if block.kind == .heading {
                    let title = block.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let base = slug(title)
                    let count = used[base, default: 0]
                    used[base] = count + 1
                    result.append(Heading(level: min(max(block.props.level, 1), 6), title: title, slug: count == 0 ? base : base + "-" + String(count)))
                }
                walk(block.children)
            }
        }
        walk(blocks)
        return result
    }

    static func slug(_ title: String) -> String {
        var result = ""
        for character in title.lowercased() {
            if character == " " { result.append("-") } else if character == "-" || character == "_" || character.isLetter || character.isNumber {
                result.append(character)
            }
        }
        return result
    }

    private static func contents(_ blocks: [NoteBlock], outline: [Heading]) -> [NoteBlock] {
        blocks.flatMap { block -> [NoteBlock] in
            if block.kind == .tableOfContents { return list(outline) }
            var copy = block
            copy.children = contents(block.children, outline: outline)
            return [copy]
        }
    }

    private static func list(_ outline: [Heading]) -> [NoteBlock] {
        let base = outline.map(\.level).min() ?? 1
        var root: [NoteBlock] = []
        func insert(_ item: NoteBlock, depth: Int, into list: inout [NoteBlock]) {
            if depth > 0, !list.isEmpty {
                insert(item, depth: depth - 1, into: &list[list.count - 1].children)
            } else {
                list.append(item)
            }
        }
        for heading in outline {
            var marks = NoteMarks.plain
            marks.link = "#" + heading.slug
            insert(NoteBlock(.bulletedItem, text: NoteText(heading.title.isEmpty ? "Untitled" : heading.title, marks: marks)),
                   depth: heading.level - base, into: &root)
        }
        return root
    }
}
